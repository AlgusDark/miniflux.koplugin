--[[--
Screen Coordinator for Miniflux Browser

This module handles screen management, initialization, and coordination between
different screens. It provides a clean interface for screen operations.

@module miniflux.browser.coordinators.screen_coordinator
--]]--

local MainScreen = require("browser/screens/main_screen")
local FeedsScreen = require("browser/screens/feeds_screen")
local CategoriesScreen = require("browser/screens/categories_screen")
local _ = require("gettext")

---@class BrowserContext
---@field type string Context type: "main", "feeds", "categories", "unread_entries", "feed_entries", "category_entries"
---@field data? table Optional context data (feed_id, feed_title, category_id, category_title)

---@class ScreenCoordinator
---@field browser MainBrowser Reference to the main browser
---@field main_screen MainScreen Main screen handler
---@field feeds_screen FeedsScreen Feeds screen handler
---@field categories_screen CategoriesScreen Categories screen handler
---@field current_context BrowserContext Current browsing context
local ScreenCoordinator = {}

---Create a new screen coordinator
---@return ScreenCoordinator
function ScreenCoordinator:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the screen coordinator
---@param browser MainBrowser The main browser instance
---@return nil
function ScreenCoordinator:init(browser)
    self.browser = browser
    
    -- Initialize context tracking
    self.current_context = {
        type = "main",
        data = nil
    }
    
    -- Initialize all screens
    self.main_screen = MainScreen:new()
    self.main_screen:init(browser)
    
    self.feeds_screen = FeedsScreen:new()
    self.feeds_screen:init(browser)
    
    self.categories_screen = CategoriesScreen:new()
    self.categories_screen:init(browser)
end

---Get the main screen instance
---@return MainScreen
function ScreenCoordinator:getMainScreen()
    return self.main_screen
end

---Get the feeds screen instance
---@return FeedsScreen
function ScreenCoordinator:getFeedsScreen()
    return self.feeds_screen
end

---Get the categories screen instance
---@return CategoriesScreen
function ScreenCoordinator:getCategoriesScreen()
    return self.categories_screen
end

---Initialize browser with counts
---@param unread_count number Number of unread entries
---@param feeds_count number Total number of feeds
---@param categories_count number Total number of categories
---@return table Initial item table
function ScreenCoordinator:initWithCounts(unread_count, feeds_count, categories_count)
    -- Update counts in browser
    self.browser.unread_count = unread_count or 0
    self.browser.feeds_count = feeds_count or 0
    self.browser.categories_count = categories_count or 0
    
    -- Generate initial main menu items
    return self.main_screen:genItemTable()
end

---Show main content
---@return nil
function ScreenCoordinator:showMainContent()
    self.main_screen:show()
end

---Show feeds content
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function ScreenCoordinator:showFeedsContent(paths_updated, page_info)
    self.feeds_screen:showContent(paths_updated, page_info)
end

---Show categories content
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function ScreenCoordinator:showCategoriesContent(paths_updated, page_info)
    self.categories_screen:showContent(paths_updated, page_info)
end

---Show feed entries
---@param feed_id number The feed ID
---@param feed_title string The feed title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function ScreenCoordinator:showFeedEntries(feed_id, feed_title, paths_updated)
    self.feeds_screen:showFeedEntries(feed_id, feed_title, paths_updated)
end

---Show category entries
---@param category_id number The category ID
---@param category_title string The category title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function ScreenCoordinator:showCategoryEntries(category_id, category_title, paths_updated)
    self.categories_screen:showCategoryEntries(category_id, category_title, paths_updated)
end

---Show unread entries
---@param is_refresh? boolean Whether this is a refresh operation
---@return nil
function ScreenCoordinator:showUnreadEntries(is_refresh)
    self.main_screen:showUnreadEntries(is_refresh)
end

---Invalidate all screen caches
---@return nil
function ScreenCoordinator:invalidateEntryCaches()
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

-- =============================================================================
-- CONTEXT MANAGEMENT (merged from context_manager.lua)
-- =============================================================================

---Get the current context
---@return BrowserContext
function ScreenCoordinator:getCurrentContext()
    return self.current_context
end

---Set the current context
---@param context_type string Context type
---@param context_data? table Optional context data
---@return nil
function ScreenCoordinator:setContext(context_type, context_data)
    self.current_context = {
        type = context_type,
        data = context_data
    }
end

---Update context for main screen
---@return nil
function ScreenCoordinator:setMainContext()
    self:setContext("main")
end

---Update context for feeds screen
---@return nil
function ScreenCoordinator:setFeedsContext()
    self:setContext("feeds")
end

---Update context for categories screen
---@return nil
function ScreenCoordinator:setCategoriesContext()
    self:setContext("categories")
end

---Update context for unread entries
---@return nil
function ScreenCoordinator:setUnreadEntriesContext()
    self:setContext("unread_entries")
end

---Update context for feed entries
---@param feed_id number The feed ID
---@param feed_title string The feed title
---@return nil
function ScreenCoordinator:setFeedEntriesContext(feed_id, feed_title)
    self:setContext("feed_entries", {
        feed_id = feed_id,
        feed_title = feed_title
    })
end

---Update context for category entries
---@param category_id number The category ID
---@param category_title string The category title
---@return nil
function ScreenCoordinator:setCategoryEntriesContext(category_id, category_title)
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
function ScreenCoordinator:updateContextFromEntriesList(title_prefix, is_category, navigation_data)
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
---@return nil
function ScreenCoordinator:refreshCurrentView()
    local context = self.current_context
    if not context or not context.type then
        -- Default to main screen if no context
        self:showMainContent()
        return
    end
    
    -- Always make fresh API calls for consistency and simplicity
    if context.type == "main" then
        self:showMainContent()
    elseif context.type == "feeds" then
        self:showFeedsContent()
    elseif context.type == "categories" then
        self:showCategoriesContent()
    elseif context.type == "feed_entries" then
        local data = context.data
        local feed_id = data and (data.feed_id or data.id)
        local feed_title = data and (data.feed_title or data.title)
        
        if feed_id and feed_title then
            -- Use regular method that makes fresh API call with current settings
            self:showFeedEntries(feed_id, feed_title, true) -- paths_updated = true for refresh
        else
            -- Fallback to feeds screen
            self:showFeedsContent()
        end
    elseif context.type == "category_entries" then
        local data = context.data
        local category_id = data and (data.category_id or data.id)
        local category_title = data and (data.category_title or data.title)
        
        if category_id and category_title then
            -- Use regular method that makes fresh API call with current settings
            self:showCategoryEntries(category_id, category_title, true) -- paths_updated = true for refresh
        else
            -- Fallback to categories screen
            self:showCategoriesContent()
        end
    elseif context.type == "unread_entries" then
        -- Use regular method that makes fresh API call with current settings
        self:showUnreadEntries(true) -- is_refresh = true
    else
        -- Fallback to main screen for unknown context types
        self:showMainContent()
    end
end

---Get navigation context for entry reading
---@param entry_data MinifluxEntry Entry data
---@return nil
function ScreenCoordinator:setEntryNavigationContext(entry_data)
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

return ScreenCoordinator 