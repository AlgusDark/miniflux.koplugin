--[[--
Menu Router for Miniflux Browser

This module handles menu item selection routing, directing different action types
to their appropriate handlers through the screen coordinator and context manager.

@module miniflux.browser.coordinators.menu_router
--]]--

local EntryUtils = require("browser/utils/entry_utils")

---@class MenuRouter
---@field browser MainBrowser Reference to the main browser
---@field screen_coordinator ScreenCoordinator Screen coordinator for screen operations
---@field context_manager ContextManager Context manager for context tracking
local MenuRouter = {}

---Create a new menu router
---@return MenuRouter
function MenuRouter:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the menu router
---@param browser MainBrowser The main browser instance
---@param screen_coordinator ScreenCoordinator Screen coordinator instance
---@param context_manager ContextManager Context manager instance
---@return nil
function MenuRouter:init(browser, screen_coordinator, context_manager)
    self.browser = browser
    self.screen_coordinator = screen_coordinator
    self.context_manager = context_manager
end

---Route menu selection to appropriate handler
---@param item BrowserMenuItem Menu item that was selected
---@return nil
function MenuRouter:routeMenuSelection(item)
    if not item or not item.action_type then
        return
    end
    
    if item.action_type == "unread" then
        self:handleUnreadAction()
        
    elseif item.action_type == "feeds" then
        self:handleFeedsAction()
        
    elseif item.action_type == "categories" then
        self:handleCategoriesAction()
        
    elseif item.action_type == "feed_entries" then
        self:handleFeedEntriesAction(item.feed_data)
        
    elseif item.action_type == "category_entries" then
        self:handleCategoryEntriesAction(item.category_data)
        
    elseif item.action_type == "read_entry" then
        self:handleReadEntryAction(item.entry_data)
    end
end

---Handle unread entries action
---@return nil
function MenuRouter:handleUnreadAction()
    if self.screen_coordinator:getMainScreen() and self.screen_coordinator:getMainScreen().showUnreadEntries then
        self.screen_coordinator:showUnreadEntries()
    end
end

---Handle feeds action
---@return nil
function MenuRouter:handleFeedsAction()
    if self.screen_coordinator:getFeedsScreen() and self.screen_coordinator:getFeedsScreen().show then
        self.screen_coordinator:getFeedsScreen():show()
    end
end

---Handle categories action
---@return nil
function MenuRouter:handleCategoriesAction()
    if self.screen_coordinator:getCategoriesScreen() and self.screen_coordinator:getCategoriesScreen().show then
        self.screen_coordinator:getCategoriesScreen():show()
    end
end

---Handle feed entries action
---@param feed_data MinifluxFeed Feed data from menu item
---@return nil
function MenuRouter:handleFeedEntriesAction(feed_data)
    if feed_data and feed_data.id and feed_data.title then
        if self.screen_coordinator:getFeedsScreen() and self.screen_coordinator:getFeedsScreen().showFeedEntries then
            self.screen_coordinator:showFeedEntries(feed_data.id, feed_data.title)
        end
    end
end

---Handle category entries action
---@param category_data MinifluxCategory Category data from menu item
---@return nil
function MenuRouter:handleCategoryEntriesAction(category_data)
    if category_data and category_data.id and category_data.title then
        if self.screen_coordinator:getCategoriesScreen() and self.screen_coordinator:getCategoriesScreen().showCategoryEntries then
            self.screen_coordinator:showCategoryEntries(category_data.id, category_data.title)
        end
    end
end

---Handle read entry action
---@param entry_data MinifluxEntry Entry data from menu item
---@return nil
function MenuRouter:handleReadEntryAction(entry_data)
    if entry_data and self.browser.api then
        -- Set navigation context based on current browsing context
        self.context_manager:setEntryNavigationContext(entry_data)
        
        -- Show the entry
        EntryUtils.showEntry({
            entry = entry_data,
            api = self.browser.api,
            download_dir = self.browser.download_dir,
            browser = self.browser
        })
    end
end

return MenuRouter 