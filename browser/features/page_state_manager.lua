--[[--
Page State Manager for Miniflux Browser

This module handles page management and navigation with safe page restoration.

@module miniflux.browser.features.page_state_manager
--]]--

---@class PageInfo
---@field page number Current page number
---@field perpage number Items per page

---@class PageStateManager
---@field browser BaseBrowser Reference to the browser instance
local PageStateManager = {}

---Create a new page state manager instance
---@return PageStateManager
function PageStateManager:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the page state manager
---@param browser BaseBrowser Browser instance to manage page state for
---@return nil
function PageStateManager:init(browser)
    self.browser = browser
end

---Get current page info for navigation
---@return PageInfo|nil Page information or nil if browser not available
function PageStateManager:getCurrentPageInfo()
    if not self.browser then
        return nil
    end
    
    if self.browser.debug then
        self.browser:debugLog("Getting current page info")
    end
    
    -- Get basic page info
    local page_info = {
        page = self.browser.page or 1,
        perpage = self.browser.perpage or 20,
    }
    
    if self.browser.debug then
        self.browser:debugLog("Current page info - page: " .. tostring(page_info.page) .. ", perpage: " .. tostring(page_info.perpage))
    end
    
    return page_info
end

---Restore page info safely (only for back navigation)
---@param page_info PageInfo|nil Page information to restore
---@return nil
function PageStateManager:restorePageInfo(page_info)
    if self.browser.debug then
        if page_info then
            self.browser:debugLog("Page restoration requested - page: " .. tostring(page_info.page))
        else
            self.browser:debugLog("No page info to restore")
        end
    end
    
    -- Page restoration is handled directly in BaseBrowser:updateBrowser method
    -- This method is kept for compatibility but actual restoration happens there
end

---Create navigation data structure
---@param paths_updated? boolean Whether navigation paths were updated
---@param current_type? string Current context type
---@param current_data? table Current context data
---@param page_info? PageInfo Page information for restoration
---@param is_settings_refresh? boolean Whether this is a settings refresh
---@return NavigationData Navigation data structure
function PageStateManager:createNavigationData(paths_updated, current_type, current_data, page_info, is_settings_refresh)
    local navigation_data = {
        paths_updated = paths_updated or false,
        current_type = current_type,
        current_data = current_data,
        is_settings_refresh = is_settings_refresh or false,
    }
    
    -- Capture page info for navigation (now used for restoration)
    if not paths_updated then
        local current_page_info = self:getCurrentPageInfo()
        navigation_data.page_info = current_page_info
        
        -- IMPORTANT: Capture the current title BEFORE it changes
        -- This way we save where we came FROM, not where we're going TO
        navigation_data.current_title = self.browser.title
        
        if self.browser.debug and current_page_info then
            self.browser:debugLog("Captured current page state for navigation: page=" .. tostring(current_page_info.page) .. ", title=" .. tostring(self.browser.title))
        end
    end
    
    -- Add page restoration info if provided
    if page_info then
        navigation_data.restore_page_info = page_info
        if self.browser.debug then
            self.browser:debugLog("Page info provided for restoration: page=" .. tostring(page_info.page))
        end
    end
    
    return navigation_data
end

return PageStateManager 