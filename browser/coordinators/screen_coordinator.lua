--[[--
Screen Coordinator for Miniflux Browser

This module handles screen management, initialization, and coordination between
different screens. It provides a clean interface for screen operations.

@module miniflux.browser.coordinators.screen_coordinator
--]]--

local MainScreen = require("browser/screens/main_screen")
local FeedsScreen = require("browser/screens/feeds_screen")
local CategoriesScreen = require("browser/screens/categories_screen")

---@class ScreenCoordinator
---@field browser MainBrowser Reference to the main browser
---@field main_screen MainScreen Main screen handler
---@field feeds_screen FeedsScreen Feeds screen handler
---@field categories_screen CategoriesScreen Categories screen handler
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

return ScreenCoordinator 