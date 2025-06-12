--[[--
Feeds Screen for Miniflux Browser

This module handles the display of feeds list and navigation to individual feeds.
It manages feed data presentation and user interactions.

@module miniflux.browser.screens.feeds_screen
--]]--

local BrowserUtils = require("browser/lib/browser_utils")
local _ = require("gettext")

---@class FeedMenuItem
---@field text string Menu item display text
---@field mandatory string Count display (unread/total format)
---@field feed_data MinifluxFeed Feed data
---@field action_type string Action type identifier
---@field unread_count number Unread count for sorting

---@class FeedsScreen
---@field browser BaseBrowser Reference to the browser instance
---@field cached_feeds? MinifluxFeed[] Cached feeds data
---@field cached_counters? FeedCounters Cached feed counters
---@field cached_entry_counts? table<string, number> Cached accurate entry counts per feed
---@field restore_page_info? table Page restoration info
local FeedsScreen = {}

---Create a new feeds screen instance
---@return FeedsScreen
function FeedsScreen:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the feeds screen
---@param browser BaseBrowser Browser instance to manage
---@return nil
function FeedsScreen:init(browser)
    self.browser = browser
end

---Show feeds list screen
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function FeedsScreen:show(paths_updated, page_info)
    if self.browser.debug then
        self.browser:debugLog("FeedsScreen:show called")
        if page_info then
            self.browser:debugLog("Page info provided (but restoration is disabled): page=" .. tostring(page_info.page))
            self.browser:debugLog("Added page_info as restore_page_info: page=" .. tostring(page_info.page))
            -- Store page_info to use during updateBrowser
            self.restore_page_info = page_info
        end
    end
    
    -- Get cached feeds or fetch new ones
    local feeds = self:getCachedFeeds()
    local feed_counters = self:getCachedCounters()
    
    if not feeds then
        local loading_info = self.browser:showLoadingMessage(_("Fetching feeds..."))
        
        local success, result
        local ok, err = pcall(function()
            success, result = self.browser.api:getFeeds()
        end)
        
        self.browser:closeLoadingMessage(loading_info)
        
        if not ok then
            if self.browser.debug then
                self.browser.debug:warn("Exception during getFeeds:", err)
            end
            self.browser:showErrorMessage(_("Failed to fetch feeds: ") .. tostring(err))
            return
        end
        
        if not self.browser:handleApiError(success, result, _("Failed to fetch feeds")) then
            return
        end
        
        if not self.browser:validateData(result, "feeds") then
            return
        end
        
        feeds = result
        self:cacheFeeds(feeds)
    end
    
    -- Fetch feed counters if not cached
    if not feed_counters then
        local loading_info = self.browser:showLoadingMessage(_("Fetching feed counters..."))
        
        local success, result
        local ok, err = pcall(function()
            success, result = self.browser.api:getFeedCounters()
        end)
        
        self.browser:closeLoadingMessage(loading_info)
        
        if not ok then
            if self.browser.debug then
                self.browser.debug:warn("Exception during getFeedCounters:", err)
            end
            -- Continue with empty counters rather than failing completely
            feed_counters = { reads = {}, unreads = {} }
        elseif success and result then
            feed_counters = result
            self:cacheCounters(feed_counters)
        else
            if self.browser.debug then
                self.browser.debug:info("Failed to fetch feed counters, using feeds data only")
            end
            feed_counters = { reads = {}, unreads = {} }
        end
    end
    
    -- DEBUGGING: Log what the feeds list reports for entry counts
    if self.browser.debug then
        self.browser.debug:info("=== FEEDS LIST ENTRY COUNTS DEBUG ===")
        self.browser.debug:info("Total feeds returned: " .. #feeds)
        if feed_counters.reads then
            local reads_count = 0
            local unreads_count = 0
            for _ in pairs(feed_counters.reads) do reads_count = reads_count + 1 end
            for _ in pairs(feed_counters.unreads) do unreads_count = unreads_count + 1 end
            self.browser.debug:info("Feed counters - reads: " .. reads_count .. ", unreads: " .. unreads_count)
        end
        
        -- Show counts for first few feeds for comparison
        for i = 1, math.min(3, #feeds) do
            local feed = feeds[i]
            local feed_id_str = tostring(feed.id)
            local read_count = feed_counters.reads and feed_counters.reads[feed_id_str] or 0
            local unread_count = feed_counters.unreads and feed_counters.unreads[feed_id_str] or 0
            
            self.browser.debug:info("Feed " .. i .. ": " .. tostring(feed.title))
            self.browser.debug:info("  id: " .. tostring(feed.id))
            self.browser.debug:info("  counter unread_count: " .. tostring(unread_count))
            self.browser.debug:info("  counter read_count: " .. tostring(read_count))
        end
        self.browser.debug:info("=======================================")
    end
    
    local menu_items = {}
    for _, feed in ipairs(feeds) do
        local feed_id_str = tostring(feed.id)
        local read_count = feed_counters.reads and feed_counters.reads[feed_id_str] or 0
        local unread_count = feed_counters.unreads and feed_counters.unreads[feed_id_str] or 0
        
        local feed_title = feed.title or _("Untitled Feed")
        
        -- Try to get accurate total count from cache, fall back to read+unread
        local total_count = self:getAccurateEntryCount(feed.id)
        if not total_count then
            total_count = read_count + unread_count
        end
        
        -- Always show unread/total format for feeds (categories only show unread)
        local count_info = string.format("(%d/%d)", unread_count, total_count)
        
        if self.browser.debug then
            self.browser.debug:info("Feed " .. feed_title .. ":")
            self.browser.debug:info("  Unread from counters: " .. unread_count)
            self.browser.debug:info("  Read from counters: " .. read_count)
            self.browser.debug:info("  Total count used: " .. total_count .. (self:getAccurateEntryCount(feed.id) and " (cached)" or " (fallback)"))
            self.browser.debug:info("  Display: " .. count_info)
        end
        
        local menu_item = {
            text = feed_title,
            mandatory = count_info,
            feed_data = feed,
            action_type = "feed_entries",
            -- Add unread count for sorting
            unread_count = unread_count,
        }
        
        table.insert(menu_items, menu_item)
    end
    
    -- Sort feeds by unread count (descending) like in Miniflux web interface
    -- This respects the "Categories sorting: Unread count" setting from the server
    -- Note: Entries within feeds are sorted by server settings (order/direction)
    table.sort(menu_items, function(a, b)
        local a_unread = a.unread_count or 0
        local b_unread = b.unread_count or 0
        local a_title = a.text or ""
        local b_title = b.text or ""
        
        -- First priority: feeds with unread entries come before feeds without
        if a_unread > 0 and b_unread == 0 then
            return true
        elseif a_unread == 0 and b_unread > 0 then
            return false
        elseif a_unread > 0 and b_unread > 0 then
            -- Both have unread entries: sort by unread count descending
            if a_unread ~= b_unread then
                return a_unread > b_unread
            else
                -- Same unread count: sort alphabetically
                return a_title:lower() < b_title:lower()
            end
        else
            -- Both have no unread entries: sort alphabetically
            return a_title:lower() < b_title:lower()
        end
    end)
    
    if self.browser.debug then
        self.browser.debug:info("Feeds sorted by unread count. First 5 feeds:")
        for i = 1, math.min(5, #menu_items) do
            local item = menu_items[i]
            self.browser.debug:info("  " .. i .. ": " .. item.text .. " - unread: " .. (item.unread_count or 0))
        end
    end
    
    -- Create navigation data to save our current state
    local navigation_data = self.browser.page_state_manager:createNavigationData(
        paths_updated or false,  -- Don't add to history if paths were just updated  
        "main",
        nil,
        page_info  -- Pass page_info for restoration if provided
    )
    
    -- Build subtitle with status icon
    local hide_read_entries = self.browser.settings and self.browser.settings:getHideReadEntries()
    local eye_icon = hide_read_entries and "⊘ " or "◯ "
    local subtitle = eye_icon .. #feeds .. _(" feeds")
    
    self.browser:updateBrowser(_("Feeds"), menu_items, subtitle, navigation_data)
end

-- Build menu items for feeds
function FeedsScreen:buildFeedMenuItems(feeds, unread_counts)
    local menu_items = {}
    
    for i, feed in ipairs(feeds) do
        local feed_title = feed.title or _("Untitled Feed")
        local feed_id_str = tostring(feed.id)
        local unread_count = unread_counts[feed_id_str] or 0
        
        local menu_item = {
            text = feed_title,
            action_type = "feed_entries",
            feed_data = {
                id = feed.id,
                title = feed_title,
                unread_count = unread_count,
            }
        }
        
        if unread_count > 0 then
            menu_item.mandatory = tostring(unread_count)
        end
        
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

-- Show entries for a specific feed
function FeedsScreen:showFeedEntries(feed_id, feed_title, paths_updated)
    if self.browser.debug then
        self.browser:debugLog("FeedsScreen:showFeedEntries called for: " .. tostring(feed_title))
    end
    
    local loading_info = self.browser:showLoadingMessage(_("Fetching entries for feed..."))
    
    -- DEBUGGING: First get feed counters to compare
    if self.browser.debug then
        self.browser.debug:info("=== FEED COUNTERS COMPARISON DEBUG ===")
        self.browser.debug:info("Fetching feed counters for comparison...")
        
        local counter_success, counter_result = self.browser.api:getFeedCounters()
        if counter_success and counter_result then
            -- Find this feed in the counters
            for _, counter in ipairs(counter_result) do
                if counter.feed_id == tonumber(feed_id) then
                    self.browser.debug:info("Feed ID " .. feed_id .. " (" .. feed_title .. ") counters:")
                    self.browser.debug:info("  unread_count: " .. tostring(counter.unread_count))
                    if counter.read_count then
                        self.browser.debug:info("  read_count: " .. tostring(counter.read_count))
                    end
                    if counter.total_count then
                        self.browser.debug:info("  total_count: " .. tostring(counter.total_count))
                    end
                    break
                end
            end
        else
            self.browser.debug:info("Failed to get feed counters:", tostring(counter_result))
        end
        self.browser.debug:info("=========================================")
    end
    
    local options = BrowserUtils.getApiOptions(self.browser.settings)
    local success, result
    local ok, err = pcall(function()
        success, result = self.browser.api:getFeedEntries(feed_id, options)
    end)
    
    self.browser:closeLoadingMessage(loading_info)
    
    if not ok then
        if self.browser.debug then
            self.browser.debug:warn("Exception during getFeedEntries:", err)
        end
        self.browser:showErrorMessage(_("Failed to fetch feed entries: ") .. tostring(err))
        return
    end
    
    if not self.browser:handleApiError(success, result, _("Failed to fetch feed entries")) then
        return
    end

    -- The API already filtered based on settings, use the results directly
    local entries = result.entries or {}
    
    -- Cache the accurate entry count for future display
    if result.total then
        self:cacheAccurateEntryCount(feed_id, result.total)
    end

    -- Check if we have no entries and show appropriate message
    if #entries == 0 then
        local hide_read_entries = self.browser.settings and self.browser.settings:getHideReadEntries()
        -- Show "no entries" message
        local no_entries_items = {
            {
                text = hide_read_entries and _("There are no unread entries.") or _("There are no entries."),
                mandatory = "",
                action_type = "no_action",
            }
        }
        
        -- Create navigation data
        local navigation_data = self.browser.page_state_manager:createNavigationData(
            paths_updated or false,
            "feeds", 
            {
                feed_id = feed_id,
                feed_title = feed_title,
            },
            nil,  -- page_info
            paths_updated  -- is_settings_refresh when paths_updated is true
        )
        
        self.browser:showEntriesList(no_entries_items, feed_title, false, navigation_data)
        return
    end

    -- DEBUGGING: Compare what we got vs feed counters
    if self.browser.debug then
        self.browser.debug:info("=== FEED ENTRIES vs COUNTERS COMPARISON ===")
        self.browser.debug:info("Entries fetched: " .. #result.entries)
        
        local unread_fetched = 0
        local read_fetched = 0
        local status_counts = {} -- Track all status types
        
        for _, entry in ipairs(result.entries) do
            local status = entry.status or "nil"
            status_counts[status] = (status_counts[status] or 0) + 1
            
            if entry.status == "unread" then
                unread_fetched = unread_fetched + 1
            elseif entry.status == "read" then
                read_fetched = read_fetched + 1
            end
        end
        
        self.browser.debug:info("Unread entries fetched: " .. unread_fetched)
        self.browser.debug:info("Read entries fetched: " .. read_fetched)
        self.browser.debug:info("Total entries fetched: " .. (unread_fetched + read_fetched))
        
        -- Show distribution of all statuses
        self.browser.debug:info("Entry status distribution:")
        for status, count in pairs(status_counts) do
            self.browser.debug:info("  " .. tostring(status) .. ": " .. count)
        end
        
        if result.total then
            self.browser.debug:info("Total field from API response: " .. tostring(result.total))
        end
        
        -- DEBUGGING: Try fetching with NO LIMIT to see real total
        self.browser.debug:info("--- Testing with NO LIMIT ---")
        local no_limit_options = {
            order = options.order,
            direction = options.direction,
        }
        -- Add status filter if it was in original options
        if options.status then
            no_limit_options.status = options.status
        end
        
        local no_limit_success, no_limit_result = self.browser.api:getFeedEntries(feed_id, no_limit_options)
        if no_limit_success and no_limit_result and no_limit_result.entries then
            local unread_no_limit = 0
            local read_no_limit = 0
            for _, entry in ipairs(no_limit_result.entries) do
                if entry.status == "unread" then
                    unread_no_limit = unread_no_limit + 1
                elseif entry.status == "read" then
                    read_no_limit = read_no_limit + 1
                end
            end
            
            self.browser.debug:info("NO LIMIT results:")
            self.browser.debug:info("  Total entries returned: " .. #no_limit_result.entries)
            self.browser.debug:info("  Unread: " .. unread_no_limit)
            self.browser.debug:info("  Read: " .. read_no_limit)
            if no_limit_result.total then
                self.browser.debug:info("  Total field from API: " .. tostring(no_limit_result.total))
            end
        else
            self.browser.debug:info("NO LIMIT test failed:", tostring(no_limit_result))
        end
        
        self.browser.debug:info("=============================================")
    end
    
    -- Create navigation data - ensure we capture current page state unless paths are being updated  
    local navigation_data = self.browser.page_state_manager:createNavigationData(
        paths_updated or false,  -- Default to false so we capture current state
        "feeds", 
        {
            feed_id = feed_id,
            feed_title = feed_title,
        },
        nil,  -- page_info
        paths_updated  -- is_settings_refresh when paths_updated is true
    )
    
    self.browser:showEntriesList(entries, feed_title, false, navigation_data)
end

-- Handle feed screen content restoration from navigation
function FeedsScreen:showContent(paths_updated, page_info)
    if self.browser.debug then
        self.browser:debugLog("FeedsScreen:showContent called - from navigation back")
        if page_info then
            self.browser:debugLog("Restoring to page: " .. tostring(page_info.page))
        end
    end
    
    -- Show feeds but prevent adding to navigation history and include page restoration
    self:show(paths_updated or true, page_info)
end

-- Cache management methods
function FeedsScreen:getCachedFeeds()
    if self.browser.debug then
        self.browser.debug:info("FeedsScreen:getCachedFeeds called")
    end
    
    -- Simple in-memory cache for feeds data
    return self.cached_feeds
end

function FeedsScreen:cacheFeeds(feeds)
    if self.browser.debug then
        self.browser.debug:info("FeedsScreen:cacheFeeds called with " .. #feeds .. " feeds")
    end
    
    -- Simple in-memory cache for feeds data
    self.cached_feeds = feeds
end

function FeedsScreen:invalidateCache()
    if self.browser.debug then
        self.browser.debug:info("FeedsScreen:invalidateCache called")
    end
    
    -- Clear the in-memory cache
    self.cached_feeds = nil
    self.cached_counters = nil
    self.cached_entry_counts = nil
end

function FeedsScreen:getCachedCounters()
    if self.browser.debug then
        self.browser.debug:info("FeedsScreen:getCachedCounters called")
    end
    
    -- Simple in-memory cache for counters data
    return self.cached_counters
end

function FeedsScreen:cacheCounters(counters)
    if self.browser.debug then
        local count_str = "unknown"
        if counters and counters.reads and counters.unreads then
            local reads_count = 0
            local unreads_count = 0
            for _ in pairs(counters.reads) do reads_count = reads_count + 1 end
            for _ in pairs(counters.unreads) do unreads_count = unreads_count + 1 end
            count_str = "reads: " .. reads_count .. ", unreads: " .. unreads_count
        end
        self.browser.debug:info("FeedsScreen:cacheCounters called with " .. count_str)
    end
    
    -- Simple in-memory cache for counters data
    self.cached_counters = counters
end

-- Get accurate entry count for a feed (cached)
function FeedsScreen:getAccurateEntryCount(feed_id)
    -- Try to get from cache first
    local cache_key = "feed_" .. tostring(feed_id) .. "_count"
    if self.cached_entry_counts and self.cached_entry_counts[cache_key] then
        return self.cached_entry_counts[cache_key]
    end
    
    -- If not cached, return nil (will be updated when entries are actually fetched)
    return nil
end

-- Cache the accurate entry count when we fetch entries
function FeedsScreen:cacheAccurateEntryCount(feed_id, total_count)
    if not self.cached_entry_counts then
        self.cached_entry_counts = {}
    end
    
    local cache_key = "feed_" .. tostring(feed_id) .. "_count" 
    self.cached_entry_counts[cache_key] = total_count
    
    if self.browser.debug then
        self.browser.debug:info("Cached accurate count for feed " .. feed_id .. ": " .. total_count)
    end
end

return FeedsScreen 