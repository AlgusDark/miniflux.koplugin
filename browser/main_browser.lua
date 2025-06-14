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
local BrowserUtils = require("browser/utils/browser_utils")
local EntryUtils = require("browser/utils/entry_utils")
local _ = require("gettext")

---@class BrowserMenuItem
---@field text string Menu item display text
---@field mandatory? string Optional mandatory text (right side)
---@field action_type string Action type for menu selection
---@field entry_data? MinifluxEntry Entry data for entry items
---@field feed_data? MinifluxFeed Feed data for feed items
---@field category_data? MinifluxCategory Category data for category items

---@class MainBrowser : BaseBrowser
---@field browser_type string Browser type identifier
---@field navigation_manager NavigationManager Navigation state manager
---@field page_state_manager PageStateManager Page state manager
---@field main_screen MainScreen Main screen handler
---@field feeds_screen FeedsScreen Feeds screen handler
---@field categories_screen CategoriesScreen Categories screen handler
---@field unread_count number Unread entries count
---@field feeds_count number Total feeds count
---@field categories_count number Total categories count
---@field close_callback function Callback for browser close
local MainBrowser = BaseBrowser:extend{}

---Initialize the main browser
---@return nil
function MainBrowser:init()
    -- Ensure we have the required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir
    
    -- Initialize screens first (before BaseBrowser.init)
    self.main_screen = MainScreen:new()
    self.main_screen:init(self)
    
    self.feeds_screen = FeedsScreen:new()
    self.feeds_screen:init(self)
    
    self.categories_screen = CategoriesScreen:new()
    self.categories_screen:init(self)
    
    -- Initialize with counts if available and set initial items
    if self.unread_count or self.feeds_count or self.categories_count then
        self:initWithCounts(self.unread_count, self.feeds_count, self.categories_count)
    end
    
    -- Generate the initial item table
    self.item_table = self.main_screen:genItemTable()
    
    -- Now call the parent init with the proper item_table set
    BaseBrowser.init(self)
    
    -- Set browser type
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

---Handle menu selection by delegating to appropriate screens
---@param item BrowserMenuItem Menu item that was selected
---@return nil
function MainBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        return
    end
    
    if item.action_type == "unread" then
        if self.main_screen and self.main_screen.showUnreadEntries then
            self.main_screen:showUnreadEntries()
        end
        
    elseif item.action_type == "feeds" then
        if self.feeds_screen and self.feeds_screen.show then
            self.feeds_screen:show()
        end
        
    elseif item.action_type == "categories" then
        if self.categories_screen and self.categories_screen.show then
            self.categories_screen:show()
        end
        
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            if self.feeds_screen and self.feeds_screen.showFeedEntries then
                self.feeds_screen:showFeedEntries(feed_data.id, feed_data.title)
            end
        end
        
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            if self.categories_screen and self.categories_screen.showCategoryEntries then
                self.categories_screen:showCategoryEntries(category_data.id, category_data.title)
            end
        end
        
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data and self.api then
            -- Pass current context for proper metadata storage
            local context_data = nil
            if self.current_context and self.current_context.data then
                context_data = self.current_context.data
            end
            
            EntryUtils.showEntry({
                entry = entry_data,
                api = self.api,
                download_dir = self.download_dir,
                browser = self,
                context = context_data  -- Pass category/feed context
            })
        end
    end
end

---Back navigation handler
---@return boolean True if navigation was handled
function MainBrowser:goBack()
    return self.navigation_manager:goBack()
end

---Override updateBrowser to integrate with navigation features
---@param title string New browser title
---@param items table[] New menu items
---@param subtitle? string New browser subtitle
---@param nav_data? NavigationData Navigation context data
---@return nil
function MainBrowser:updateBrowser(title, items, subtitle, nav_data)
    -- Call parent first to update the UI completely
    BaseBrowser.updateBrowser(self, title, items, subtitle, nav_data)
    
    -- Then let navigation manager handle the navigation logic after UI is stable
    if nav_data then
        self.navigation_manager:updateBrowser(title, items, subtitle, nav_data)
    end
end

-- Override refreshCurrentView to refresh the current screen
function MainBrowser:refreshCurrentView()
    local context = self.current_context
    if not context or not context.type then
        -- Default to main screen if no context
        if self.main_screen and self.main_screen.show then
            self.main_screen:show()
        end
        return
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
        -- Fallback to main screen for unknown context types
        if self.main_screen and self.main_screen.show then
            self.main_screen:show()
        end
    end
end

---Show entries list with navigation data (overrides BaseBrowser)
---@param entries table[] List of entries or message items
---@param title_prefix string Screen title
---@param is_category boolean Whether this is a category view
---@param navigation_data table Navigation context data
---@return nil
function MainBrowser:showEntriesList(entries, title_prefix, is_category, navigation_data)
    -- Update current context with proper field names
    if title_prefix:find(_("Unread")) then
        self.current_context = { type = "unread_entries" }
    elseif is_category then
        local category_data = navigation_data and navigation_data.current_data
        if category_data and (category_data.category_id or category_data.id) and (category_data.category_title or category_data.title) then
            self.current_context = { 
                type = "category_entries", 
                data = { 
                    category_id = category_data.category_id or category_data.id,
                    category_title = category_data.category_title or category_data.title
                }
            }
        else
            self.current_context = { type = "category_entries" }
        end
    else
        local feed_data = navigation_data and navigation_data.current_data
        if feed_data and (feed_data.feed_id or feed_data.id) and (feed_data.feed_title or feed_data.title) then
            self.current_context = { 
                type = "feed_entries", 
                data = { 
                    feed_id = feed_data.feed_id or feed_data.id,
                    feed_title = feed_data.feed_title or feed_data.title
                }
            }
        else
            self.current_context = { type = "feed_entries" }
        end
    end
    
    local menu_items = {}
    local has_no_entries_message = false
    
    for i, entry in ipairs(entries) do
        if entry.action_type == "no_action" then
            local menu_item = {
                text = entry.text,
                mandatory = entry.mandatory or "",
                action_type = entry.action_type,
            }
            table.insert(menu_items, menu_item)
            has_no_entries_message = true
        else
            local entry_title = entry.title or _("Untitled Entry")
            local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
            
            local status_indicator = ""
            if entry.status == "read" then
                status_indicator = "○ "
            else
                status_indicator = "● "
            end
            
            local display_text = status_indicator .. entry_title
            if is_category then
                display_text = status_indicator .. entry_title .. " (" .. feed_title .. ")"
            end
            
            local menu_item = {
                text = display_text,
                entry_data = entry,
                action_type = "read_entry"
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
    
    -- Build subtitle with enhanced logic for different view types
    local subtitle = ""
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local is_unread_entries_view = self.current_context and self.current_context.type == "unread_entries"
    
    if is_unread_entries_view then
        if has_no_entries_message then
            subtitle = "⊘ 0 " .. _("unread entries")
        else
            subtitle = "⊘ " .. #entries .. " " .. _("unread entries")
        end
    else
        local eye_icon = hide_read_entries and "⊘ " or "◯ "
        if has_no_entries_message then
            if hide_read_entries then
                subtitle = eye_icon .. "0 " .. _("unread entries")
            else
                subtitle = eye_icon .. "0 " .. _("entries")
            end
        else
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
    -- Call parent implementation for all settings - we want fresh API calls
    BaseBrowser.onSettingsChanged(self, setting_name, new_value)
end

-- Override invalidateEntryCaches to actually invalidate relevant caches
function MainBrowser:invalidateEntryCaches()
    -- Invalidate feeds cache (contains entry counts per feed)
    if self.feeds_screen and self.feeds_screen.invalidateCache then
        self.feeds_screen:invalidateCache()
    end
    
    -- Invalidate categories cache (contains entry counts per category)  
    if self.categories_screen and self.categories_screen.invalidateCache then
        self.categories_screen:invalidateCache()
    end
    
    -- Invalidate main screen cache (contains unread count)
    if self.main_screen and self.main_screen.invalidateCache then
        self.main_screen:invalidateCache()
    end
end

return MainBrowser 