--[[--
Navigation Manager for Miniflux Browser

This module handles navigation state, back button functionality, and page restoration.
It maintains the navigation stack and provides methods for navigation operations.

@module miniflux.browser.features.navigation_manager
--]]--

---@class NavigationPath
---@field title string Title of the navigation path
---@field type string Type of content (main, feeds, categories)
---@field page_info? table Page information for restoration
---@field nav_data? table Additional navigation context data

---@class NavigationManager
---@field browser BaseBrowser Reference to the browser instance
---@field navigation_paths NavigationPath[] Stack of navigation paths
local NavigationManager = {}

---Create a new navigation manager instance
---@return NavigationManager
function NavigationManager:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize the navigation manager
---@param browser BaseBrowser Browser instance to manage navigation for
---@return nil
function NavigationManager:init(browser)
    self.browser = browser
    self.navigation_paths = {}
    
    -- Initialize Menu widget's paths property (needed for back button state)
    if not self.browser.paths then
        self.browser.paths = {}
    end
    
    -- Enable back navigation only when we have paths
    self:updateBackButtonState()
end

---Update browser navigation state
---@param title string Browser title
---@param items table[] Menu items
---@param subtitle string Browser subtitle
---@param nav_data NavigationData Navigation context data
---@return nil
function NavigationManager:updateBrowser(title, items, subtitle, nav_data)
    if nav_data then
        if not nav_data.paths_updated then
            -- Add current location to navigation history before changing
            -- Use the captured title from nav_data (where we came FROM) instead of browser title (where we're going TO)
            local current_path = {
                title = nav_data.current_title or self.browser.title, -- Use captured title if available
                type = nav_data.current_type or "main",
                page_info = nav_data.page_info, -- Use provided page info instead of capturing
                nav_data = nav_data.current_data -- Store any additional context
            }
            table.insert(self.navigation_paths, current_path)
        end
        
        -- Handle page restoration if specified
        if nav_data.restore_page_info then
            self.browser.page_state_manager:restorePageInfo(nav_data.restore_page_info)
        end
    end
    
    -- Update back button state
    self:updateBackButtonState()
end

---Update back button state based on navigation paths
---@return nil
function NavigationManager:updateBackButtonState()
    -- Only enable back navigation if we have navigation paths
    if self.navigation_paths and #self.navigation_paths > 0 then
        self.browser.onReturn = function()
            return self:goBack()
        end
        
        -- Synchronize with Menu widget's paths property for back button enablement
        if not self.browser.paths then
            self.browser.paths = {}
        end
        -- The Menu widget checks #self.paths > 0 to enable the back button
        -- We just need it to have items, content doesn't matter for back button state
        while #self.browser.paths < #self.navigation_paths do
            table.insert(self.browser.paths, true)
        end
        while #self.browser.paths > #self.navigation_paths do
            table.remove(self.browser.paths)
        end
    else
        self.browser.onReturn = nil
        
        -- Clear Menu widget's paths property 
        if self.browser.paths then
            self.browser.paths = {}
        end
    end
    
    -- Force page info update to show/hide return arrow, but safely
    if self.browser.updatePageInfo then
        -- Use pcall to safely update page info in case Menu widget is in transition
        local success, err = pcall(function()
            self.browser:updatePageInfo()
        end)
    end
end

---Handle back navigation
---@return boolean True if navigation was handled, false otherwise
function NavigationManager:goBack()
    if not self.navigation_paths or #self.navigation_paths == 0 then
        return false
    end
    
    -- Remove and get the last path - this is where we want to go back TO
    local target_path = table.remove(self.navigation_paths)
    
    -- Navigate to the target path (the one we just removed)
    if target_path.type == "main" then
        self.browser:showMainContent()
    elseif target_path.type == "categories" then
        self.browser:showCategoriesContent(true, target_path.page_info)
    elseif target_path.type == "feeds" then
        self.browser:showFeedsContent(true, target_path.page_info)
    else
        self.browser:showMainContent() -- fallback
    end
    
    return true
end

---Check if we can go back
---@return boolean True if back navigation is possible
function NavigationManager:canGoBack()
    return self.navigation_paths and #self.navigation_paths > 0
end

---Clear all navigation paths
---@return nil
function NavigationManager:clear()
    self.navigation_paths = {}
    -- Also clear Menu widget's paths property
    if self.browser.paths then
        self.browser.paths = {}
    end
    self:updateBackButtonState()
end

return NavigationManager 