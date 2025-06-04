--[[--
Main Screen for Miniflux Browser

This module handles the main menu display with Unread, Feeds, and Categories options.
It manages the initial screen presentation and navigation to other screens.

@module miniflux.browser.screens.main_screen
--]]--

local BrowserUtils = require("browser/lib/browser_utils")
local _ = require("gettext")

local MainScreen = {}

function MainScreen:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function MainScreen:init(browser)
    self.browser = browser
end

-- Generate main menu items table
function MainScreen:genItemTable()
    -- Use the counts passed during initialization
    local unread_count = self.browser.unread_count or 0
    local feeds_count = self.browser.feeds_count or 0
    local categories_count = self.browser.categories_count or 0
    
    return {
        {
            text = _("Unread"),
            mandatory = tostring(unread_count),
            action_type = "unread",
        },
        {
            text = _("Feeds"),
            mandatory = tostring(feeds_count),
            action_type = "feeds",
        },
        {
            text = _("Categories"),
            mandatory = tostring(categories_count),
            action_type = "categories",
        },
    }
end

-- Show main content screen
function MainScreen:show()
    if self.browser.debug then
        self.browser:debugLog("MainScreen:show called")
    end
    
    local main_items = self:genItemTable()
    
    -- Build subtitle with status icon
    local hide_read_entries = self.browser.settings and self.browser.settings:getHideReadEntries()
    local eye_icon = hide_read_entries and "⊘ " or "◯ "
    local subtitle = eye_icon .. ""  -- Just the icon for main screen
    
    self.browser:updateBrowser(_("Miniflux"), main_items, subtitle, {paths_updated = true})
end

-- Show unread entries screen
function MainScreen:showUnreadEntries(is_refresh)
    if self.browser.debug then
        self.browser:debugLog("MainScreen:showUnreadEntries called, is_refresh=" .. tostring(is_refresh))
    end
    
    local loading_info = self.browser:showLoadingMessage(_("Fetching entries..."))
    
    -- HARDCODE: Always fetch only unread entries for this view, regardless of user settings
    local options = {
        status = {"unread"},  -- Always unread only
        order = self.browser.settings:getOrder(),
        direction = self.browser.settings:getDirection(),
        limit = self.browser.settings:getLimit(),
    }
    
    local success, result
    local ok, err = pcall(function()
        success, result = self.browser.api:getEntries(options)
    end)
    
    self.browser:closeLoadingMessage(loading_info)
    
    if not ok then
        if self.browser.debug then
            self.browser.debug:warn("Exception during getEntries:", err)
        end
        self.browser:showErrorMessage(_("Failed to fetch entries: ") .. tostring(err))
        return
    end
    
    if not self.browser:handleApiError(success, result, _("Failed to fetch entries")) then
        return
    end
    
    -- Check if we have no entries and show appropriate message
    local entries = result.entries or {}
    if #entries == 0 then
        -- Always show "unread entries" message since this view is specifically for unread
        local no_entries_items = {
            {
                text = _("There are no unread entries."),
                mandatory = "",
                action_type = "no_action",
            }
        }
        
        -- Create navigation data
        local navigation_data = self.browser.page_state_manager:createNavigationData(
            is_refresh or false,  -- Use is_refresh parameter if provided
            "main",
            nil,
            nil,  -- page_info 
            is_refresh -- is_settings_refresh when this is a refresh
        )
        
        -- Always use "Unread Entries" title since this view is specifically for unread
        self.browser:showEntriesList(no_entries_items, _("Unread Entries"), true, navigation_data)
        return
    end
    
    -- Create navigation data
    local navigation_data = self.browser.page_state_manager:createNavigationData(
        is_refresh or false,  -- Use is_refresh parameter if provided
        "main",
        nil,
        nil,  -- page_info 
        is_refresh -- is_settings_refresh when this is a refresh
    )
    
    -- Always use "Unread Entries" title since this view is specifically for unread
    self.browser:showEntriesList(entries, _("Unread Entries"), true, navigation_data)
end

-- Show unread entries screen (refresh version - no navigation context)
function MainScreen:showUnreadEntriesRefresh()
    if self.browser.debug then
        self.browser:debugLog("MainScreen:showUnreadEntriesRefresh called")
    end
    
    -- Call the main method with is_refresh = true
    self:showUnreadEntries(true)
end

-- Cache management methods
function MainScreen:getCachedUnreadCount()
    if self.browser.debug then
        self.browser.debug:info("MainScreen:getCachedUnreadCount called")
    end
    
    -- Simple in-memory cache for unread count
    return self.cached_unread_count
end

function MainScreen:cacheUnreadCount(count)
    if self.browser.debug then
        self.browser.debug:info("MainScreen:cacheUnreadCount called with count: " .. tostring(count))
    end
    
    -- Simple in-memory cache for unread count
    self.cached_unread_count = count
end

function MainScreen:invalidateCache()
    if self.browser.debug then
        self.browser.debug:info("MainScreen:invalidateCache called")
    end
    
    -- Clear the in-memory cache
    self.cached_unread_count = nil
end

return MainScreen 