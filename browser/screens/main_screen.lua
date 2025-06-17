--[[--
Main Screen for Miniflux Browser

This module handles the main menu display with Unread, Feeds, and Categories options.
It manages the initial screen presentation and navigation to other screens.

@module miniflux.browser.screens.main_screen
--]]--

local BaseScreen = require("browser/screens/base_screen")
local ScreenUI = require("browser/screens/ui_components")
local _ = require("gettext")

---@class MainMenuItem
---@field text string Menu item text
---@field mandatory string Menu item count or status
---@field action_type string Action type identifier

---@class MainScreen : BaseScreen
---@field cached_unread_count? number Cached unread count
local MainScreen = {}
setmetatable(MainScreen, BaseScreen)
MainScreen.__index = MainScreen

---Create a new MainScreen instance
---@return MainScreen
function MainScreen:new()
    local obj = BaseScreen:new()
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Generate main menu items table
---@return MainMenuItem[] Array of main menu items
function MainScreen:genItemTable()
    -- Use the counts passed during initialization
    local unread_count = self.browser.unread_count or 0
    local feeds_count = self.browser.feeds_count or 0
    local categories_count = self.browser.categories_count or 0
    
    return {
        ScreenUI.createMainMenuItem(_("Unread"), unread_count, "unread"),
        ScreenUI.createMainMenuItem(_("Feeds"), feeds_count, "feeds"),
        ScreenUI.createMainMenuItem(_("Categories"), categories_count, "categories"),
    }
end

---Show main content screen
---@return nil
function MainScreen:show()
    local main_items = self:genItemTable()
    
    -- Build subtitle with status icon (just the icon for main screen)
    local subtitle = self:getStatusIcon()
    
    self:updateBrowser(_("Miniflux"), main_items, subtitle, {paths_updated = true})
end

---Show unread entries screen
---@param is_refresh? boolean Whether this is a refresh operation
---@return nil
function MainScreen:showUnreadEntries(is_refresh)
    -- HARDCODE: Always fetch only unread entries for this view, regardless of user settings
    local options = {
        status = {"unread"},  -- Always unread only
        order = self.browser.settings:getOrder(),
        direction = self.browser.settings:getDirection(),
        limit = self.browser.settings:getLimit(),
    }
    
    local result = self:performApiCall({
        operation_name = "fetch entries",
        api_call_func = function()
            return self.browser.api:getEntries(options)
        end,
        loading_message = _("Fetching entries..."),
        data_name = "entries",
        skip_validation = true  -- Skip validation since we handle empty entries properly
    })
    
    if not result then
        return
    end
    
    -- Check if we have no entries and show appropriate message
    local entries = result.entries or {}
    if #entries == 0 then
        -- Create no entries item for unread-only view using ScreenUI
        local no_entries_items = { ScreenUI.createNoEntriesItem(true) }
        
        -- Create navigation data
        local navigation_data = self:createNavigationData(
            is_refresh or false,
            "main",
            nil,
            nil,  -- page_info 
            is_refresh
        )
        
        -- Always use "Unread Entries" title since this view is specifically for unread
        self:showEntriesList(no_entries_items, _("Unread Entries"), true, navigation_data)
        return
    end
    
    -- Create navigation data
    local navigation_data = self:createNavigationData(
        is_refresh or false,
        "main",
        nil,
        nil,  -- page_info 
        is_refresh
    )
    
    -- Always use "Unread Entries" title since this view is specifically for unread
    self:showEntriesList(entries, _("Unread Entries"), true, navigation_data)
end

---Show unread entries screen (refresh version - no navigation context)
---@return nil
function MainScreen:showUnreadEntriesRefresh()
    -- Call the main method with is_refresh = true
    self:showUnreadEntries(true)
end

---Get cached unread count
---@return number|nil Cached unread count or nil if not cached
function MainScreen:getCachedUnreadCount()
    -- Simple in-memory cache for unread count
    return self.cached_unread_count
end

---Cache unread count
---@param count number Unread count to cache
---@return nil
function MainScreen:cacheUnreadCount(count)
    -- Simple in-memory cache for unread count
    self.cached_unread_count = count
end

---Invalidate cache
---@return nil
function MainScreen:invalidateCache()
    -- Clear the in-memory cache
    self.cached_unread_count = nil
end

return MainScreen 