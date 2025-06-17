--[[--
Simplified Main Browser for Miniflux Plugin

This is a simplified browser that orchestrates everything directly using providers.
No complex screen coordinators or separate screen classes - just data providers and direct browser management.

@module miniflux.browser.main_browser_simple
--]]--

local BaseBrowser = require("browser/lib/base_browser")
local NavigationManager = require("browser/features/navigation_manager")
local PageStateManager = require("browser/features/page_state_manager")
local EntryUtils = require("browser/utils/entry_utils")
local SortingUtils = require("browser/utils/sorting_utils")

-- Simple data providers
local CategoriesProvider = require("browser/providers/categories_provider")
local FeedsProvider = require("browser/providers/feeds_provider")
local EntriesProvider = require("browser/providers/entries_provider")

local _ = require("gettext")

---@class SimpleBrowser : BaseBrowser
---@field navigation_manager NavigationManager Navigation state manager
---@field page_state_manager PageStateManager Page state manager
---@field categories_provider CategoriesProvider Categories data provider
---@field feeds_provider FeedsProvider Feeds data provider
---@field entries_provider EntriesProvider Entries data provider
---@field unread_count number Unread entries count
---@field feeds_count number Total feeds count
---@field categories_count number Total categories count
---@field current_context table Current browsing context
local SimpleBrowser = BaseBrowser:extend{}

---Initialize the browser
---@return nil
function SimpleBrowser:init()
    -- Ensure we have the required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir
    
    -- Initialize providers
    self.categories_provider = CategoriesProvider:new()
    self.feeds_provider = FeedsProvider:new()
    self.entries_provider = EntriesProvider:new()
    
    -- Set up initial context
    self.current_context = { type = "main" }
    
    -- Generate initial main menu items
    self.item_table = self:generateMainMenu()
    
    -- Call parent init
    BaseBrowser.init(self)
    
    -- Initialize features
    self.navigation_manager = NavigationManager:new()
    self.navigation_manager:init(self)
    
    self.page_state_manager = PageStateManager:new()
    self.page_state_manager:init(self)
end

---Generate main menu with counts
---@return table[] Main menu items
function SimpleBrowser:generateMainMenu()
    local unread_count = self.unread_count or 0
    local feeds_count = self.feeds_count or 0
    local categories_count = self.categories_count or 0
    
    return {
        {
            text = _("Unread"),
            mandatory = tostring(unread_count),
            action_type = "unread"
        },
        {
            text = _("Feeds"),
            mandatory = tostring(feeds_count),
            action_type = "feeds"
        },
        {
            text = _("Categories"),
            mandatory = tostring(categories_count),
            action_type = "categories"
        }
    }
end

---Handle menu selection with direct routing
---@param item table Menu item that was selected
---@return nil
function SimpleBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        return
    end
    
    if item.action_type == "unread" then
        self:showUnreadEntries()
    elseif item.action_type == "feeds" then
        self:showFeeds()
    elseif item.action_type == "categories" then
        self:showCategories()
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            self:showFeedEntries(feed_data.id, feed_data.title)
        end
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            self:showCategoryEntries(category_data.id, category_data.title)
        end
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data then
            self:openEntry(entry_data)
        end
    end
end

---Show unread entries
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function SimpleBrowser:showUnreadEntries(paths_updated)
    local loading_info = self:showLoadingMessage(_("Fetching unread entries..."))
    
    local success, result = self.entries_provider:getUnreadEntries(self.api, self.settings)
    
    self:closeLoadingMessage(loading_info)
    
    if not self:handleApiError(success, result, _("Failed to fetch unread entries")) then
        return
    end
    
    local entries = result.entries or {}
    local menu_items
    
    if #entries == 0 then
        menu_items = { self.entries_provider:createNoEntriesItem(true) }
    else
        menu_items = self.entries_provider:toMenuItems(entries, true) -- true = category view (show feed names)
    end
    
    local subtitle = self.entries_provider:getSubtitle(#entries, false, true) -- true = unread only
    local nav_data = self:createNavigationData(paths_updated, "main")
    
    self.current_context = { type = "unread_entries" }
    self:updateBrowser(_("Unread Entries"), menu_items, subtitle, nav_data)
end

---Show feeds list
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function SimpleBrowser:showFeeds(paths_updated, page_info)
    local loading_info = self:showLoadingMessage(_("Fetching feeds..."))
    
    -- Get feeds
    local success, feeds = self.feeds_provider:getFeeds(self.api)
    if not self:handleApiError(success, feeds, _("Failed to fetch feeds")) then
        self:closeLoadingMessage(loading_info)
        return
    end
    
    -- Get counters (optional)
    local counters_success, feed_counters = self.feeds_provider:getCounters(self.api)
    if not counters_success then
        feed_counters = { reads = {}, unreads = {} } -- Empty counters on failure
    end
    
    self:closeLoadingMessage(loading_info)
    
    local menu_items = self.feeds_provider:toMenuItems(feeds, feed_counters)
    SortingUtils.sortByUnreadCount(menu_items) -- Sort by unread count
    
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local subtitle = self.feeds_provider:getSubtitle(#feeds, hide_read_entries)
    
    local nav_data = self:createNavigationData(paths_updated, "main", nil, page_info)
    if page_info then
        nav_data.restore_page_info = page_info
    end
    
    self.current_context = { type = "feeds" }
    self:updateBrowser(_("Feeds"), menu_items, subtitle, nav_data)
end

---Show categories list
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function SimpleBrowser:showCategories(paths_updated, page_info)
    local loading_info = self:showLoadingMessage(_("Fetching categories..."))
    
    local success, categories = self.categories_provider:getCategories(self.api)
    
    self:closeLoadingMessage(loading_info)
    
    if not self:handleApiError(success, categories, _("Failed to fetch categories")) then
        return
    end
    
    local menu_items = self.categories_provider:toMenuItems(categories)
    SortingUtils.sortByUnreadCount(menu_items) -- Sort by unread count
    
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local subtitle = self.categories_provider:getSubtitle(#categories, hide_read_entries)
    
    local nav_data = self:createNavigationData(paths_updated, "main", nil, page_info)
    if page_info then
        nav_data.restore_page_info = page_info
    end
    
    self.current_context = { type = "categories" }
    self:updateBrowser(_("Categories"), menu_items, subtitle, nav_data)
end

---Show entries for a specific feed
---@param feed_id number Feed ID
---@param feed_title string Feed title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function SimpleBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    local loading_info = self:showLoadingMessage(_("Fetching feed entries..."))
    
    local success, result = self.entries_provider:getFeedEntries(self.api, self.settings, feed_id)
    
    self:closeLoadingMessage(loading_info)
    
    if not success then
        self:showErrorMessage(_("Failed to fetch feed entries: ") .. tostring(result))
        return
    end
    
    local entries = result.entries or {}
    local menu_items
    
    if #entries == 0 then
        local hide_read_entries = self.settings and self.settings:getHideReadEntries()
        menu_items = { self.entries_provider:createNoEntriesItem(hide_read_entries) }
    else
        menu_items = self.entries_provider:toMenuItems(entries, false) -- false = not category view
    end
    
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local subtitle = self.entries_provider:getSubtitle(#entries, hide_read_entries, false)
    
    local nav_data = self:createNavigationData(paths_updated, "feeds", {
        feed_id = feed_id,
        feed_title = feed_title
    })
    
    self.current_context = { 
        type = "feed_entries",
        feed_id = feed_id,
        feed_title = feed_title 
    }
    self:updateBrowser(feed_title, menu_items, subtitle, nav_data)
end

---Show entries for a specific category
---@param category_id number Category ID
---@param category_title string Category title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function SimpleBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    local loading_info = self:showLoadingMessage(_("Fetching category entries..."))
    
    local success, result = self.entries_provider:getCategoryEntries(self.api, self.settings, category_id)
    
    self:closeLoadingMessage(loading_info)
    
    if not success then
        self:showErrorMessage(_("Failed to fetch category entries: ") .. tostring(result))
        return
    end
    
    local entries = result.entries or {}
    local menu_items
    
    if #entries == 0 then
        local hide_read_entries = self.settings and self.settings:getHideReadEntries()
        menu_items = { self.entries_provider:createNoEntriesItem(hide_read_entries) }
    else
        menu_items = self.entries_provider:toMenuItems(entries, true) -- true = category view (show feed names)
    end
    
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local subtitle = self.entries_provider:getSubtitle(#entries, hide_read_entries, false)
    
    local nav_data = self:createNavigationData(paths_updated, "categories", {
        category_id = category_id,
        category_title = category_title
    })
    
    self.current_context = { 
        type = "category_entries",
        category_id = category_id,
        category_title = category_title 
    }
    self:updateBrowser(category_title, menu_items, subtitle, nav_data)
end

---Open an entry
---@param entry_data table Entry data
---@return nil
function SimpleBrowser:openEntry(entry_data)
    -- Set navigation context based on current browsing context
    local NavigationContext = require("browser/utils/navigation_context")
    
    if self.current_context.type == "feed_entries" then
        NavigationContext.setFeedContext(self.current_context.feed_id, entry_data.id)
    elseif self.current_context.type == "category_entries" then
        NavigationContext.setCategoryContext(self.current_context.category_id, entry_data.id)
    else
        NavigationContext.setGlobalContext(entry_data.id)
    end
    
    -- Show the entry
    EntryUtils.showEntry({
        entry = entry_data,
        api = self.api,
        download_dir = self.download_dir,
        browser = self
    })
end

---Show main menu
---@return nil
function SimpleBrowser:showMainContent()
    local main_items = self:generateMainMenu()
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local subtitle = hide_read_entries and "⊘ " or "◯ "
    
    self.current_context = { type = "main" }
    self:updateBrowser(_("Miniflux"), main_items, subtitle, {paths_updated = true})
end

---Override back navigation methods for compatibility
function SimpleBrowser:showFeedsContent(paths_updated, page_info)
    self:showFeeds(paths_updated, page_info)
end

function SimpleBrowser:showCategoriesContent(paths_updated, page_info)
    self:showCategories(paths_updated, page_info)
end

---Create navigation data
---@param paths_updated? boolean Whether navigation paths were updated
---@param parent_type string Parent screen type
---@param current_data? table Current screen data
---@param page_info? table Page information for restoration
---@return table Navigation data
function SimpleBrowser:createNavigationData(paths_updated, parent_type, current_data, page_info)
    return self.page_state_manager:createNavigationData(
        paths_updated or false,
        parent_type,
        current_data,
        page_info,
        false -- is_settings_refresh
    )
end

---Refresh current view
---@return nil
function SimpleBrowser:refreshCurrentView()
    local context = self.current_context
    if not context or not context.type then
        self:showMainContent()
        return
    end
    
    if context.type == "main" then
        self:showMainContent()
    elseif context.type == "feeds" then
        self:showFeeds(true) -- paths_updated = true for refresh
    elseif context.type == "categories" then
        self:showCategories(true) -- paths_updated = true for refresh
    elseif context.type == "feed_entries" then
        self:showFeedEntries(context.feed_id, context.feed_title, true)
    elseif context.type == "category_entries" then
        self:showCategoryEntries(context.category_id, context.category_title, true)
    elseif context.type == "unread_entries" then
        self:showUnreadEntries(true)
    else
        self:showMainContent()
    end
end

---Override updateBrowser to integrate with navigation features
---@param title string New browser title
---@param items table[] New menu items
---@param subtitle? string New browser subtitle
---@param nav_data? table Navigation context data
---@return nil
function SimpleBrowser:updateBrowser(title, items, subtitle, nav_data)
    -- Call parent first to update the UI
    BaseBrowser.updateBrowser(self, title, items, subtitle, nav_data)
    
    -- Then let navigation manager handle the navigation logic
    if nav_data then
        self.navigation_manager:updateBrowser(title, items, subtitle, nav_data)
    end
end

---Invalidate caches (simplified - no complex cache management)
---@return nil
function SimpleBrowser:invalidateEntryCaches()
    -- In the simplified version, we don't maintain complex caches
    -- Just clear any simple cached data if needed
end

return SimpleBrowser 