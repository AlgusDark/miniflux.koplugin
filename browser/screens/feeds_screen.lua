--[[--
Feeds Screen for Miniflux Browser

This module handles the display of feeds list and navigation to individual feeds.
It manages feed data presentation and user interactions.

@module miniflux.browser.screens.feeds_screen
--]]--

local BrowserUtils = require("browser/utils/browser_utils")
local SortingUtils = require("browser/utils/sorting_utils")
local ErrorUtils = require("browser/utils/error_utils")
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
    -- Get cached feeds or fetch new ones
    local feeds = self:getCachedFeeds()
    local feed_counters = self:getCachedCounters()
    
    if not feeds then
        feeds = ErrorUtils.handleApiCall({
            browser = self.browser,
            operation_name = "fetch feeds",
            api_call_func = function()
                return self.browser.api:getFeeds()
            end,
            loading_message = _("Fetching feeds..."),
            data_name = "feeds"
        })
        
        if not feeds then
            return
        end
        
        self:cacheFeeds(feeds)
    end
    
    -- Fetch feed counters if not cached
    if not feed_counters then
        feed_counters = ErrorUtils.handleApiCall({
            browser = self.browser,
            operation_name = "fetch feed counters",
            api_call_func = function()
                return self.browser.api:getFeedCounters()
            end,
            loading_message = _("Fetching feed counters..."),
            data_name = "feed counters",
            skip_validation = true  -- Skip validation since we handle failure gracefully
        })
        
        -- Use empty counters if fetch failed instead of stopping
        if not feed_counters then
            -- Feed counters endpoint might not be available on older Miniflux versions
            -- Continue with empty counters to show basic feed list
            feed_counters = { reads = {}, unreads = {} }
        else
            self:cacheCounters(feed_counters)
        end
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
    SortingUtils.sortByUnreadCount(menu_items)
    
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

---Show entries for a specific feed
---@param feed_id number The feed ID
---@param feed_title string The feed title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function FeedsScreen:showFeedEntries(feed_id, feed_title, paths_updated)
    local options = BrowserUtils.getApiOptions(self.browser.settings)
    
    local result = ErrorUtils.handleApiCall({
        browser = self.browser,
        operation_name = "fetch feed entries",
        api_call_func = function()
            return self.browser.api:getFeedEntries(feed_id, options)
        end,
        loading_message = _("Fetching entries for feed..."),
        data_name = "feed entries",
        skip_validation = true  -- Skip validation since we handle empty entries properly
    })
    
    if not result then
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

---Handle feed screen content restoration from navigation
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function FeedsScreen:showContent(paths_updated, page_info)
    -- Show feeds but prevent adding to navigation history and include page restoration
    self:show(paths_updated or true, page_info)
end

---Get cached feeds
---@return MinifluxFeed[]|nil Cached feeds data or nil if not cached
function FeedsScreen:getCachedFeeds()
    -- Simple in-memory cache for feeds data
    return self.cached_feeds
end

---Cache feeds data
---@param feeds MinifluxFeed[] Feeds data to cache
---@return nil
function FeedsScreen:cacheFeeds(feeds)
    -- Simple in-memory cache for feeds data
    self.cached_feeds = feeds
end

---Invalidate all cached data
---@return nil
function FeedsScreen:invalidateCache()
    -- Clear the in-memory cache
    self.cached_feeds = nil
    self.cached_counters = nil
    self.cached_entry_counts = nil
end

---Get cached feed counters
---@return FeedCounters|nil Cached feed counters or nil if not cached
function FeedsScreen:getCachedCounters()
    -- Simple in-memory cache for counters data
    return self.cached_counters
end

---Cache feed counters data
---@param counters FeedCounters Feed counters to cache
---@return nil
function FeedsScreen:cacheCounters(counters)
    -- Simple in-memory cache for counters data
    self.cached_counters = counters
end

---Get accurate entry count for a feed (cached)
---@param feed_id number The feed ID
---@return number|nil Cached entry count or nil if not cached
function FeedsScreen:getAccurateEntryCount(feed_id)
    -- Try to get from cache first
    local cache_key = "feed_" .. tostring(feed_id) .. "_count"
    if self.cached_entry_counts and self.cached_entry_counts[cache_key] then
        return self.cached_entry_counts[cache_key]
    end
    
    -- If not cached, return nil (will be updated when entries are actually fetched)
    return nil
end

---Cache the accurate entry count when we fetch entries
---@param feed_id number The feed ID
---@param total_count number The total entry count
---@return nil
function FeedsScreen:cacheAccurateEntryCount(feed_id, total_count)
    if not self.cached_entry_counts then
        self.cached_entry_counts = {}
    end
    
    local cache_key = "feed_" .. tostring(feed_id) .. "_count" 
    self.cached_entry_counts[cache_key] = total_count
end

return FeedsScreen 