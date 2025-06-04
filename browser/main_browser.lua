--[[--
Main Browser for Miniflux Plugin

This is the main browser coordinator that manages navigation between different screens.
It delegates specific functionality to specialized screen and feature modules.

@module miniflux.browser.main_browser
--]]--

local BaseBrowser = require("browser/lib/base_browser")
local NavigationManager = require("browser/features/navigation_manager")
local PageStateManager = require("browser/features/page_state_manager")
local MainScreen = require("browser/screens/main_screen")
local FeedsScreen = require("browser/screens/feeds_screen")
local CategoriesScreen = require("browser/screens/categories_screen")
local BrowserUtils = require("browser/lib/browser_utils")
local _ = require("gettext")

local MainBrowser = BaseBrowser:extend{}

function MainBrowser:init()
    -- Ensure we have the required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.debug = self.debug
    self.download_dir = self.download_dir
    
    if self.debug then
        self.debug:info("MainBrowser:init() called with counts: unread=" .. tostring(self.unread_count) .. ", feeds=" .. tostring(self.feeds_count) .. ", categories=" .. tostring(self.categories_count))
        if self.download_dir then
            self.debug:info("MainBrowser:init() download_dir: " .. self.download_dir)
        end
    end
    
    -- Initialize screens first (before BaseBrowser.init)
    self.main_screen = MainScreen:new()
    self.main_screen:init(self)
    
    self.feeds_screen = FeedsScreen:new()
    self.feeds_screen:init(self)
    
    self.categories_screen = CategoriesScreen:new()
    self.categories_screen:init(self)
    
    -- Initialize with counts if available and set initial items
    if self.unread_count or self.feeds_count or self.categories_count then
        if self.debug then
            self.debug:info("Calling initWithCounts with unread=" .. tostring(self.unread_count) .. ", feeds=" .. tostring(self.feeds_count) .. ", categories=" .. tostring(self.categories_count))
        end
        self:initWithCounts(self.unread_count, self.feeds_count, self.categories_count)
    else
        if self.debug then
            self.debug:info("No counts available, skipping initWithCounts")
        end
    end
    
    -- Generate the initial item table
    self.item_table = self.main_screen:genItemTable()
    
    if self.debug then
        self.debug:info("Generated item_table with " .. #self.item_table .. " items")
        for i, item in ipairs(self.item_table) do
            self.debug:info("Item " .. i .. ": " .. item.text .. " (" .. tostring(item.mandatory) .. ")")
        end
    end
    
    -- Now call the parent init with the proper item_table set
    BaseBrowser.init(self)
    
    -- Set browser type for debugging
    self.browser_type = "MinifluxBrowser"
    
    -- Initialize features with proper browser reference
    self.navigation_manager = NavigationManager:new()
    self.navigation_manager:init(self)
    
    self.page_state_manager = PageStateManager:new()
    self.page_state_manager:init(self)
    
    -- Set up back navigation using NavigationManager
    self.onReturn = function()
        return self.navigation_manager:goBack()
    end
    
    -- Store current context for refresh functionality
    self.current_context = {
        type = "main",
        data = nil
    }
end

-- Handle menu selection by delegating to appropriate screens
function MainBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        if self.debug then
            self:debugLog("onMenuSelect: item or action_type is missing")
        end
        return
    end
    
    if self.debug then
        self:debugLog("=== onMenuSelect called ===")
        self:debugLog("action_type: " .. tostring(item.action_type))
        self:debugLog("item.text: " .. tostring(item.text))
        self:debugLog("=== onMenuSelect processing ===")
    end
    
    if item.action_type == "unread" then
        if self.debug then
            self:debugLog("Processing unread action")
        end
        if self.main_screen and self.main_screen.showUnreadEntries then
            self.main_screen:showUnreadEntries()
        else
            if self.debug then
                self:debugLog("Error: main_screen or showUnreadEntries method not available")
            end
        end
        
    elseif item.action_type == "feeds" then
        if self.debug then
            self:debugLog("Processing feeds action")
        end
        if self.feeds_screen and self.feeds_screen.show then
            self.feeds_screen:show()
        else
            if self.debug then
                self:debugLog("Error: feeds_screen or show method not available")
            end
        end
        
    elseif item.action_type == "categories" then
        if self.debug then
            self:debugLog("Processing categories action")
        end
        if self.categories_screen and self.categories_screen.show then
            self.categories_screen:show()
        else
            if self.debug then
                self:debugLog("Error: categories_screen or show method not available")
            end
        end
        
    elseif item.action_type == "feed_entries" then
        if self.debug then
            self:debugLog("Processing feed_entries action")
        end
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            if self.feeds_screen and self.feeds_screen.showFeedEntries then
                self.feeds_screen:showFeedEntries(feed_data.id, feed_data.title)
            else
                if self.debug then
                    self:debugLog("Error: feeds_screen or showFeedEntries method not available")
                end
            end
        else
            if self.debug then
                self:debugLog("Error: feed_data is missing or incomplete")
            end
        end
        
    elseif item.action_type == "category_entries" then
        if self.debug then
            self:debugLog("Processing category_entries action")
        end
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            if self.categories_screen and self.categories_screen.showCategoryEntries then
                self.categories_screen:showCategoryEntries(category_data.id, category_data.title)
            else
                if self.debug then
                    self:debugLog("Error: categories_screen or showCategoryEntries method not available")
                end
            end
        else
            if self.debug then
                self:debugLog("Error: category_data is missing or incomplete")
            end
        end
        
    elseif item.action_type == "read_entry" then
        if self.debug then
            self:debugLog("Processing read_entry action")
        end
        local entry_data = item.entry_data
        local nav_context = item.navigation_context
        if entry_data and self.api then
            BrowserUtils.showEntry(entry_data, self.api, self.debug, self.download_dir, nav_context)
        else
            if self.debug then
                self:debugLog("Error: entry_data or api not available")
            end
        end
        
    else
        if self.debug then
            self:debugLog("Unknown action type: " .. tostring(item.action_type))
        end
    end
end

-- Back navigation handler
function MainBrowser:goBack()
    return self.navigation_manager:goBack()
end

-- Override updateBrowser to integrate with navigation features
function MainBrowser:updateBrowser(title, items, subtitle, nav_data)
    if self.debug then
        self:debugLog("=== MainBrowser:updateBrowser called ===")
        self:debugLog("Current title: " .. tostring(self.title))
        self:debugLog("New title: " .. tostring(title))
        self:debugLog("Items count: " .. #items)
    end
    
    -- Call parent first to update the UI completely
    BaseBrowser.updateBrowser(self, title, items, subtitle, nav_data)
    
    -- Then let navigation manager handle the navigation logic after UI is stable
    if nav_data then
        self.navigation_manager:updateBrowser(title, items, subtitle, nav_data)
    end
    
    if self.debug then
        self:debugLog("=== MainBrowser:updateBrowser end ===")
    end
end

-- Override refreshCurrentView to refresh the current screen
function MainBrowser:refreshCurrentView()
    if self.debug then
        self.debug:info("MainBrowser:refreshCurrentView called")
    end
    
    local context = self.current_context
    if not context or not context.type then
        if self.debug then
            self.debug:info("No current context available for refresh, defaulting to main screen")
        end
        -- Default to main screen if no context
        if self.main_screen and self.main_screen.show then
            self.main_screen:show()
        end
        return
    end
    
    if self.debug then
        self.debug:info("Refreshing current context:", tostring(context.type))
    end
    
    -- Always make fresh API calls for consistency and simplicity
    if context.type == "main" then
        if self.main_screen and self.main_screen.show then
            self.main_screen:show()
        end
    elseif context.type == "feeds" then
        if self.feeds_screen and self.feeds_screen.show then
            self.feeds_screen:show()
        end
    elseif context.type == "categories" then
        if self.categories_screen and self.categories_screen.show then
            self.categories_screen:show()
        end
    elseif context.type == "feed_entries" then
        local data = context.data
        local feed_id = data and (data.feed_id or data.id)
        local feed_title = data and (data.feed_title or data.title)
        
        if feed_id and feed_title then
            -- Use regular method that makes fresh API call with current settings
            if self.feeds_screen and self.feeds_screen.showFeedEntries then
                self.feeds_screen:showFeedEntries(feed_id, feed_title, true) -- paths_updated = true for refresh
            end
        else
            -- Fallback to feeds screen
            if self.feeds_screen and self.feeds_screen.show then
                self.feeds_screen:show()
            end
        end
    elseif context.type == "category_entries" then
        local data = context.data
        local category_id = data and (data.category_id or data.id)
        local category_title = data and (data.category_title or data.title)
        
        if category_id and category_title then
            -- Use regular method that makes fresh API call with current settings
            if self.categories_screen and self.categories_screen.showCategoryEntries then
                self.categories_screen:showCategoryEntries(category_id, category_title, true) -- paths_updated = true for refresh
            end
        else
            -- Fallback to categories screen
            if self.categories_screen and self.categories_screen.show then
                self.categories_screen:show()
            end
        end
    elseif context.type == "unread_entries" then
        -- Use regular method that makes fresh API call with current settings
        if self.main_screen and self.main_screen.showUnreadEntries then
            self.main_screen:showUnreadEntries(true) -- is_refresh = true
        end
    else
        if self.debug then
            self.debug:info("Unknown context type for refresh:", context.type, "- defaulting to main screen")
        end
        -- Fallback to main screen for unknown context types
        if self.main_screen and self.main_screen.show then
            self.main_screen:show()
        end
    end
end

-- Show entries list (used by multiple screens)
function MainBrowser:showEntriesList(entries, title_prefix, is_category, navigation_data)
    if self.debug then
        self:debugLog("showEntriesList called with " .. #entries .. " entries")
    end
    
    -- Update current context with proper field names
    if title_prefix:find(_("Unread")) then
        self.current_context = { type = "unread_entries" }
    elseif is_category then
        -- Get category data from navigation_data.current_data (not category_data)
        local category_data = navigation_data and navigation_data.current_data
        if category_data and (category_data.category_id or category_data.id) and (category_data.category_title or category_data.title) then
            self.current_context = { 
                type = "category_entries", 
                data = { 
                    category_id = category_data.category_id or category_data.id,
                    category_title = category_data.category_title or category_data.title
                }
            }
            if self.debug then
                self:debugLog("Set category context: id=" .. tostring(self.current_context.data.category_id) .. ", title=" .. tostring(self.current_context.data.category_title))
            end
        else
            if self.debug then
                self:debugLog("No valid category data in navigation_data, setting context without data")
            end
            self.current_context = { type = "category_entries" }
        end
    else
        -- Get feed data from navigation_data.current_data (not feed_data)
        local feed_data = navigation_data and navigation_data.current_data
        if feed_data and (feed_data.feed_id or feed_data.id) and (feed_data.feed_title or feed_data.title) then
            self.current_context = { 
                type = "feed_entries", 
                data = { 
                    feed_id = feed_data.feed_id or feed_data.id,
                    feed_title = feed_data.feed_title or feed_data.title
                }
            }
            if self.debug then
                self:debugLog("Set feed context: id=" .. tostring(self.current_context.data.feed_id) .. ", title=" .. tostring(self.current_context.data.feed_title))
            end
        else
            if self.debug then
                self:debugLog("No valid feed data in navigation_data, setting context without data")
            end
            self.current_context = { type = "feed_entries" }
        end
    end
    
    local menu_items = {}
    local has_no_entries_message = false
    
    for i, entry in ipairs(entries) do
        -- Check if this is a special non-entry item (like "no entries" message)
        if entry.action_type == "no_action" then
            -- This is a special message item, use it directly without entry processing
            local menu_item = {
                text = entry.text,
                mandatory = entry.mandatory or "",
                action_type = entry.action_type,
            }
            table.insert(menu_items, menu_item)
            has_no_entries_message = true
        else
            -- This is a regular entry, process it normally
            local entry_title = entry.title or _("Untitled Entry")
            local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
            
            -- Add read/unread status indicator
            local status_indicator = ""
            if entry.status == "read" then
                status_indicator = "○ "  -- Open circle for read entries
            else
                status_indicator = "● "  -- Filled circle for unread entries
            end
            
            local display_text = status_indicator .. entry_title
            if is_category then
                display_text = status_indicator .. entry_title .. " (" .. feed_title .. ")"
            end
            
            local menu_item = {
                text = display_text,
                -- Remove mandatory field - we don't want anything on the right
                entry_data = entry,
                action_type = "read_entry",
                -- Add navigation context for previous/next functionality
                navigation_context = {
                    entries = entries,
                    current_index = i,
                    total_entries = #entries
                }
            }
            
            table.insert(menu_items, menu_item)
        end
    end
    
    if #menu_items == 0 then
        menu_items = {{
            text = _("No entries found"),
            action_type = "none",
        }}
    end
    
    -- Build subtitle with appropriate icon and count
    local subtitle = ""
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    
    -- For unread entries view, always show the "show only unread" icon (⊘)
    -- regardless of the global setting, since this view is specifically for unread entries
    local is_unread_entries_view = self.current_context and self.current_context.type == "unread_entries"
    
    if is_unread_entries_view then
        -- Unread entries view: ALWAYS show ⊘ and "unread entries" text
        if has_no_entries_message then
            subtitle = "⊘ 0 " .. _("unread entries")
        else
            subtitle = "⊘ " .. #entries .. " " .. _("unread entries")
        end
    else
        -- Other views (feeds, categories): follow normal logic
        local should_show_unread_icon = hide_read_entries
        local eye_icon = should_show_unread_icon and "⊘ " or "◯ "
        
        if has_no_entries_message then
            -- For empty feeds/categories, show appropriate message based on settings
            if hide_read_entries then
                subtitle = eye_icon .. "0 " .. _("unread entries")
            else
                subtitle = eye_icon .. "0 " .. _("entries")
            end
        else
            -- Regular case with actual entries
            subtitle = eye_icon .. #entries .. _(" entries")
        end
    end
    
    self:updateBrowser(title_prefix, menu_items, subtitle, navigation_data)
end

-- Initialize browser with counts
function MainBrowser:initWithCounts(unread_count, feeds_count, categories_count)
    self.unread_count = unread_count or 0
    self.feeds_count = feeds_count or 0 
    self.categories_count = categories_count or 0
    
    -- Regenerate main menu with updated counts
    if self.main_screen then
        self.item_table = self.main_screen:genItemTable()
    end
end

-- Content restoration methods (called by navigation manager)
function MainBrowser:showMainContent()
    -- Update current context
    self.current_context = { type = "main" }
    
    self.main_screen:show()
end

function MainBrowser:showFeedsContent(paths_updated, page_info)
    -- Update current context
    self.current_context = { type = "feeds" }
    
    self.feeds_screen:showContent(paths_updated, page_info)
end

function MainBrowser:showCategoriesContent(paths_updated, page_info)
    -- Update current context  
    self.current_context = { type = "categories" }
    
    self.categories_screen:showContent(paths_updated, page_info)
end

-- Methods called by BaseBrowser:goBack() for direct navigation
function MainBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    -- Update current context
    self.current_context = { type = "feed_entries", data = { feed_id = feed_id, feed_title = feed_title } }
    
    self.feeds_screen:showFeedEntries(feed_id, feed_title, paths_updated)
end

function MainBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    -- Update current context
    self.current_context = { type = "category_entries", data = { category_id = category_id, category_title = category_title } }
    
    self.categories_screen:showCategoryEntries(category_id, category_title, paths_updated)
end

-- Override onSettingsChanged to handle specific settings changes
function MainBrowser:onSettingsChanged(setting_name, new_value)
    if self.debug then
        self.debug:info("MainBrowser:onSettingsChanged -", setting_name, "=", tostring(new_value))
    end
    
    -- Call parent implementation for all settings - we want fresh API calls
    BaseBrowser.onSettingsChanged(self, setting_name, new_value)
end

-- Override invalidateEntryCaches to actually invalidate relevant caches
function MainBrowser:invalidateEntryCaches()
    if self.debug then
        self.debug:info("MainBrowser:invalidateEntryCaches called")
    end
    
    -- Invalidate feeds cache (contains entry counts per feed)
    if self.feeds_screen and self.feeds_screen.invalidateCache then
        if self.debug then
            self.debug:info("Invalidating feeds screen cache")
        end
        self.feeds_screen:invalidateCache()
    end
    
    -- Invalidate categories cache (contains entry counts per category)  
    if self.categories_screen and self.categories_screen.invalidateCache then
        if self.debug then
            self.debug:info("Invalidating categories screen cache")
        end
        self.categories_screen:invalidateCache()
    end
    
    -- Invalidate main screen cache (contains unread count)
    if self.main_screen and self.main_screen.invalidateCache then
        if self.debug then
            self.debug:info("Invalidating main screen cache")
        end
        self.main_screen:invalidateCache()
    end
    
    if self.debug then
        self.debug:info("All entry-related caches invalidated")
    end
end

return MainBrowser 