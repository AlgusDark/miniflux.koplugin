--[[--
Page State Manager for Miniflux Browser

This module handles page management and navigation with safe page restoration.

@module miniflux.browser.features.page_state_manager
--]]--

local PageStateManager = {}

function PageStateManager:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function PageStateManager:init(browser)
    self.browser = browser
end

-- Get current page info for navigation
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

-- Restore page info safely (only for back navigation)
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

-- Create navigation data structure
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