--[[--
Context Manager for Miniflux Browser

This module handles browser context tracking, context-based refreshing,
and context state management across different screens and navigation states.

@module miniflux.browser.coordinators.context_manager
--]]--

local _ = require("gettext")

---@class BrowserContext
---@field type string Context type: "main", "feeds", "categories", "unread_entries", "feed_entries", "category_entries"
---@field data? table Optional context data (feed_id, feed_title, category_id, category_title)

---@class ContextManager
---@field browser MainBrowser Reference to the main browser
---@field current_context BrowserContext Current browsing context
local ContextManager = {}

---Create a new context manager
---@return ContextManager
function ContextManager:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the context manager
---@param browser MainBrowser The main browser instance
---@return nil
function ContextManager:init(browser)
    self.browser = browser
    
    -- Initialize with main context
    self.current_context = {
        type = "main",
        data = nil
    }
end

---Get the current context
---@return BrowserContext
function ContextManager:getCurrentContext()
    return self.current_context
end

---Set the current context
---@param context_type string Context type
---@param context_data? table Optional context data
---@return nil
function ContextManager:setContext(context_type, context_data)
    self.current_context = {
        type = context_type,
        data = context_data
    }
end

---Update context for main screen
---@return nil
function ContextManager:setMainContext()
    self:setContext("main")
end

---Update context for feeds screen
---@return nil
function ContextManager:setFeedsContext()
    self:setContext("feeds")
end

---Update context for categories screen
---@return nil
function ContextManager:setCategoriesContext()
    self:setContext("categories")
end

---Update context for unread entries
---@return nil
function ContextManager:setUnreadEntriesContext()
    self:setContext("unread_entries")
end

---Update context for feed entries
---@param feed_id number The feed ID
---@param feed_title string The feed title
---@return nil
function ContextManager:setFeedEntriesContext(feed_id, feed_title)
    self:setContext("feed_entries", {
        feed_id = feed_id,
        feed_title = feed_title
    })
end

---Update context for category entries
---@param category_id number The category ID
---@param category_title string The category title
---@return nil
function ContextManager:setCategoryEntriesContext(category_id, category_title)
    self:setContext("category_entries", {
        category_id = category_id,
        category_title = category_title
    })
end

---Update context based on entries list display
---@param title_prefix string Screen title
---@param is_category boolean Whether this is a category view
---@param navigation_data table Navigation context data
---@return nil
function ContextManager:updateContextFromEntriesList(title_prefix, is_category, navigation_data)
    -- Update current context with proper field names
    if title_prefix:find(_("Unread")) then
        self:setUnreadEntriesContext()
    elseif is_category then
        local category_data = navigation_data and navigation_data.current_data
        if category_data and (category_data.category_id or category_data.id) and (category_data.category_title or category_data.title) then
            local category_id = category_data.category_id or category_data.id
            local category_title = category_data.category_title or category_data.title
            self:setCategoryEntriesContext(category_id, category_title)
        else
            self:setContext("category_entries")
        end
    else
        local feed_data = navigation_data and navigation_data.current_data
        if feed_data and (feed_data.feed_id or feed_data.id) and (feed_data.feed_title or feed_data.title) then
            local feed_id = feed_data.feed_id or feed_data.id
            local feed_title = feed_data.feed_title or feed_data.title
            self:setFeedEntriesContext(feed_id, feed_title)
        else
            self:setContext("feed_entries")
        end
    end
end

---Refresh the current view based on context
---@param screen_coordinator ScreenCoordinator Screen coordinator for screen operations
---@return nil
function ContextManager:refreshCurrentView(screen_coordinator)
    local context = self.current_context
    if not context or not context.type then
        -- Default to main screen if no context
        screen_coordinator:showMainContent()
        return
    end
    
    -- Always make fresh API calls for consistency and simplicity
    if context.type == "main" then
        screen_coordinator:showMainContent()
    elseif context.type == "feeds" then
        screen_coordinator:showFeedsContent()
    elseif context.type == "categories" then
        screen_coordinator:showCategoriesContent()
    elseif context.type == "feed_entries" then
        local data = context.data
        local feed_id = data and (data.feed_id or data.id)
        local feed_title = data and (data.feed_title or data.title)
        
        if feed_id and feed_title then
            -- Use regular method that makes fresh API call with current settings
            screen_coordinator:showFeedEntries(feed_id, feed_title, true) -- paths_updated = true for refresh
        else
            -- Fallback to feeds screen
            screen_coordinator:showFeedsContent()
        end
    elseif context.type == "category_entries" then
        local data = context.data
        local category_id = data and (data.category_id or data.id)
        local category_title = data and (data.category_title or data.title)
        
        if category_id and category_title then
            -- Use regular method that makes fresh API call with current settings
            screen_coordinator:showCategoryEntries(category_id, category_title, true) -- paths_updated = true for refresh
        else
            -- Fallback to categories screen
            screen_coordinator:showCategoriesContent()
        end
    elseif context.type == "unread_entries" then
        -- Use regular method that makes fresh API call with current settings
        screen_coordinator:showUnreadEntries(true) -- is_refresh = true
    else
        -- Fallback to main screen for unknown context types
        screen_coordinator:showMainContent()
    end
end

---Get navigation context for entry reading
---@param entry_data MinifluxEntry Entry data
---@return nil
function ContextManager:setEntryNavigationContext(entry_data)
    -- Set global navigation context based on current browsing context
    local NavigationContext = require("browser/utils/navigation_context")
    
    if self.current_context and self.current_context.type == "feed_entries" then
        local feed_data = self.current_context.data
        local feed_id = feed_data and (feed_data.feed_id or feed_data.id)
        if feed_id then
            NavigationContext.setFeedContext(feed_id, entry_data.id)
        else
            NavigationContext.setGlobalContext(entry_data.id)
        end
    elseif self.current_context and self.current_context.type == "category_entries" then
        local category_data = self.current_context.data
        local category_id = category_data and (category_data.category_id or category_data.id)
        if category_id then
            NavigationContext.setCategoryContext(category_id, entry_data.id)
        else
            NavigationContext.setGlobalContext(entry_data.id)
        end
    else
        -- Global context (unread entries or unknown context)
        NavigationContext.setGlobalContext(entry_data.id)
    end
end

return ContextManager 