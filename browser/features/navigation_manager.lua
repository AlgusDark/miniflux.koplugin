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

---Debug method to check navigation paths state
---@param context? string Debug context description
---@return nil
function NavigationManager:debugNavigationPaths(context)
    if not self.browser.debug then 
        return 
    end
    
    self.browser:debugLog("=== Navigation Paths Debug (" .. (context or "unknown") .. ") ===")
    if self.navigation_paths then
        self.browser:debugLog("navigation_paths exists with " .. #self.navigation_paths .. " items")
        for i, path in ipairs(self.navigation_paths) do
            local path_info = i .. ": " .. path.title .. " (" .. path.type .. ")"
            if path.page_info then
                path_info = path_info .. " [page=" .. tostring(path.page_info.page) .. "]"
            end
            if path.nav_data then
                path_info = path_info .. " {has_nav_data}"
            end
            self.browser:debugLog("  " .. path_info)
        end
    else
        self.browser:debugLog("navigation_paths is nil")
    end
    self.browser:debugLog("=== End Navigation Paths Debug ===")
end

---Update browser navigation state
---@param title string Browser title
---@param items table[] Menu items
---@param subtitle string Browser subtitle
---@param nav_data NavigationData Navigation context data
---@return nil
function NavigationManager:updateBrowser(title, items, subtitle, nav_data)
    if self.browser.debug then
        self:debugNavigationPaths("before updateBrowser")
    end
    
    if nav_data then
        if self.browser.debug then
            self.browser:debugLog("Navigation data: yes")
            self.browser:debugLog("Paths updated: " .. tostring(nav_data.paths_updated))
            self.browser:debugLog("Current paths count: " .. tostring(#self.navigation_paths))
        end
        
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
            
            if self.browser.debug then
                self.browser:debugLog("Added current navigation path: " .. current_path.title .. " (type: " .. current_path.type .. ")")
                if current_path.page_info then
                    self.browser:debugLog("Saved page info - page: " .. tostring(current_path.page_info.page))
                end
                self.browser:debugLog("New paths count: " .. tostring(#self.navigation_paths))
            end
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
        if self.browser.debug then
            self.browser:debugLog("Enabling back navigation (" .. #self.navigation_paths .. " paths available)")
        end
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
        if self.browser.debug then
            self.browser:debugLog("Disabling back navigation (no paths available)")
        end
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
        if not success and self.browser.debug then
            self.browser:debugLog("Warning: updatePageInfo failed safely: " .. tostring(err))
        end
    end
end

---Handle back navigation
---@return boolean True if navigation was handled, false otherwise
function NavigationManager:goBack()
    if self.browser.debug then
        self.browser:debugLog("=== NavigationManager:goBack called ===")
        self:debugNavigationPaths("goBack start")
    end
    
    if not self.navigation_paths or #self.navigation_paths == 0 then
        if self.browser.debug then
            self.browser:debugLog("No navigation paths found, cannot go back")
        end
        return false
    end
    
    if self.browser.debug then
        self.browser:debugLog("Using nav_paths with count: " .. tostring(#self.navigation_paths))
        for i, path in ipairs(self.navigation_paths) do
            self.browser:debugLog("Path " .. i .. ": title='" .. tostring(path.title) .. "', type='" .. tostring(path.type) .. "'")
            if path.page_info then
                self.browser:debugLog("  - Has page info: page=" .. tostring(path.page_info.page))
            end
        end
    end
    
    -- Remove and get the last path - this is where we want to go back TO
    local target_path = table.remove(self.navigation_paths)
    if self.browser.debug then
        self.browser:debugLog("Removed path: title='" .. tostring(target_path.title) .. "', type='" .. tostring(target_path.type) .. "'")
        if target_path.page_info then
            self.browser:debugLog("Target has page info: page=" .. tostring(target_path.page_info.page))
        end
        self.browser:debugLog("Remaining paths count: " .. #self.navigation_paths)
    end
    
    -- Navigate to the target path (the one we just removed)
    if self.browser.debug then
        self.browser:debugLog("Going back to: " .. target_path.title .. " (type: " .. target_path.type .. ")")
    end
    
    if target_path.type == "main" then
        if self.browser.debug then
            self.browser:debugLog("Calling showMainContent()")
        end
        self.browser:showMainContent()
    elseif target_path.type == "categories" then
        if self.browser.debug then
            self.browser:debugLog("Calling showCategoriesContent() with page info")
        end
        self.browser:showCategoriesContent(true, target_path.page_info)
    elseif target_path.type == "feeds" then
        if self.browser.debug then
            self.browser:debugLog("Calling showFeedsContent() with page info")
        end
        self.browser:showFeedsContent(true, target_path.page_info)
    else
        if self.browser.debug then
            self.browser:debugLog("Unknown path type: " .. tostring(target_path.type))
        end
        self.browser:showMainContent() -- fallback
    end
    
    if self.browser.debug then
        self.browser:debugLog("=== NavigationManager:goBack end ===")
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