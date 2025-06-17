--[[--
Main Browser for Miniflux Plugin

This is the main browser coordinator that manages navigation between different screens.
It delegates specific functionality to specialized coordinator modules.

@module miniflux.browser.main_browser
--]]--

local BaseBrowser = require("browser/lib/base_browser")
local NavigationManager = require("browser/features/navigation_manager")
local PageStateManager = require("browser/features/page_state_manager")
local ScreenCoordinator = require("browser/coordinators/screen_coordinator")
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
---@field screen_coordinator ScreenCoordinator Screen management and context coordinator
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
    
    -- Initialize screen coordinator (includes context management)
    self.screen_coordinator = ScreenCoordinator:new()
    self.screen_coordinator:init(self)
    
    -- Initialize with counts if available and set initial items
    if self.unread_count or self.feeds_count or self.categories_count then
        self.item_table = self.screen_coordinator:initWithCounts(self.unread_count, self.feeds_count, self.categories_count)
    else
        -- Generate initial item table from main screen
        self.item_table = self.screen_coordinator:getMainScreen():genItemTable()
    end
    
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
end

---Handle menu selection with inline routing
---@param item BrowserMenuItem Menu item that was selected
---@return nil
function MainBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        return
    end
    
    if item.action_type == "unread" then
        if self.screen_coordinator:getMainScreen() and self.screen_coordinator:getMainScreen().showUnreadEntries then
            self.screen_coordinator:showUnreadEntries()
        end
        
    elseif item.action_type == "feeds" then
        if self.screen_coordinator:getFeedsScreen() and self.screen_coordinator:getFeedsScreen().show then
            self.screen_coordinator:getFeedsScreen():show()
        end
        
    elseif item.action_type == "categories" then
        if self.screen_coordinator:getCategoriesScreen() and self.screen_coordinator:getCategoriesScreen().show then
            self.screen_coordinator:getCategoriesScreen():show()
        end
        
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            if self.screen_coordinator:getFeedsScreen() and self.screen_coordinator:getFeedsScreen().showFeedEntries then
                self.screen_coordinator:showFeedEntries(feed_data.id, feed_data.title)
            end
        end
        
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            if self.screen_coordinator:getCategoriesScreen() and self.screen_coordinator:getCategoriesScreen().showCategoryEntries then
                self.screen_coordinator:showCategoryEntries(category_data.id, category_data.title)
            end
        end
        
            elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data and self.api then
            -- Set navigation context based on current browsing context
            self.screen_coordinator:setEntryNavigationContext(entry_data)
            
            -- Show the entry
            EntryUtils.showEntry({
                entry = entry_data,
                api = self.api,
                download_dir = self.download_dir,
                browser = self
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
---@return nil
function MainBrowser:refreshCurrentView()
    self.screen_coordinator:refreshCurrentView()
end

---Show entries list with navigation data (overrides BaseBrowser)
---@param entries table[] List of entries or message items
---@param title_prefix string Screen title
---@param is_category boolean Whether this is a category view
---@param navigation_data table Navigation context data
---@return nil
function MainBrowser:showEntriesList(entries, title_prefix, is_category, navigation_data)
    -- Update context via screen coordinator
    self.screen_coordinator:updateContextFromEntriesList(title_prefix, is_category, navigation_data)
    
    local menu_items = {}
    local has_no_entries_message = false
    
    for _, entry in ipairs(entries) do
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
    local current_context = self.screen_coordinator:getCurrentContext()
    local is_unread_entries_view = current_context and current_context.type == "unread_entries"
    
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

---Initialize browser with counts
---@param unread_count number Number of unread entries
---@param feeds_count number Total number of feeds
---@param categories_count number Total number of categories
---@return nil
function MainBrowser:initWithCounts(unread_count, feeds_count, categories_count)
    self.item_table = self.screen_coordinator:initWithCounts(unread_count, feeds_count, categories_count)
end

---Show main content (called by navigation manager)
---@return nil
function MainBrowser:showMainContent()
    self.screen_coordinator:setMainContext()
    self.screen_coordinator:showMainContent()
end

---Show feeds content (called by navigation manager)
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function MainBrowser:showFeedsContent(paths_updated, page_info)
    self.screen_coordinator:setFeedsContext()
    self.screen_coordinator:showFeedsContent(paths_updated, page_info)
end

---Show categories content (called by navigation manager)
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function MainBrowser:showCategoriesContent(paths_updated, page_info)
    self.screen_coordinator:setCategoriesContext()
    self.screen_coordinator:showCategoriesContent(paths_updated, page_info)
end

---Show feed entries (called by BaseBrowser for direct navigation)
---@param feed_id number The feed ID
---@param feed_title string The feed title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function MainBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    self.screen_coordinator:setFeedEntriesContext(feed_id, feed_title)
    self.screen_coordinator:showFeedEntries(feed_id, feed_title, paths_updated)
end

---Show category entries (called by BaseBrowser for direct navigation)
---@param category_id number The category ID
---@param category_title string The category title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function MainBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    self.screen_coordinator:setCategoryEntriesContext(category_id, category_title)
    self.screen_coordinator:showCategoryEntries(category_id, category_title, paths_updated)
end

-- Override onSettingsChanged to handle specific settings changes
function MainBrowser:onSettingsChanged(setting_name, new_value)
    -- Call parent implementation for all settings - we want fresh API calls
    BaseBrowser.onSettingsChanged(self, setting_name, new_value)
end

---Override invalidateEntryCaches to actually invalidate relevant caches
---@return nil
function MainBrowser:invalidateEntryCaches()
    self.screen_coordinator:invalidateEntryCaches()
end

return MainBrowser 