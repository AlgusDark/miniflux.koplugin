--[[--
Path Service - Navigation Path Management

Handles navigation path creation, back button management, navigation history,
and back navigation logic for the Miniflux browser.

@module miniflux.services.path_service
--]]

local _ = require("gettext")

---@class PathService
---@field browser MinifluxBrowser Reference to the MinifluxBrowser instance
---@field view_service ViewService Reference to the ViewService
local PathService = {}
PathService.__index = PathService

function PathService:new(browser, view_service)
    local obj = setmetatable({}, PathService)
    obj.browser = browser
    obj.view_service = view_service
    return obj
end

-- =============================================================================
-- NAVIGATION DATA CREATION
-- =============================================================================

function PathService:createNavData(paths_updated, parent_type, current_data, page_info)
    local nav_data = {
        paths_updated = paths_updated or false,
        current_type = parent_type,
        current_data = current_data,
    }

    -- Capture current page info for back navigation
    if not paths_updated then
        nav_data.page_info = {
            page = self.browser.page or 1,
            perpage = self.browser.perpage or 20,
        }
        nav_data.current_title = self.browser.title
    end

    -- Add page restoration if provided
    if page_info then
        nav_data.restore_page_info = page_info
    end

    return nav_data
end

-- =============================================================================
-- BACK BUTTON MANAGEMENT
-- =============================================================================

function PathService:updateBackButton()
    if #self.browser.navigation_paths > 0 then
        self.browser.onReturn = function()
            return self:goBack()
        end
        -- Sync with Menu widget's paths for back button
        if not self.browser.paths then
            self.browser.paths = {}
        end
        while #self.browser.paths < #self.browser.navigation_paths do
            table.insert(self.browser.paths, true)
        end
    else
        self.browser.onReturn = nil
        if self.browser.paths then
            self.browser.paths = {}
        end
    end

    -- Update page info to show/hide back button
    if self.browser.updatePageInfo then
        pcall(function()
            self.browser:updatePageInfo()
        end)
    end
end

-- =============================================================================
-- BACK NAVIGATION LOGIC
-- =============================================================================

function PathService:goBack()
    if #self.browser.navigation_paths == 0 then
        return false
    end

    local target_path = table.remove(self.browser.navigation_paths)

    if target_path.type == "main" then
        self.view_service:showMainContent()
    elseif target_path.type == "categories" then
        self.view_service:showCategories(true, target_path.page_info)
    elseif target_path.type == "feeds" then
        self.view_service:showFeeds(true, target_path.page_info)
    else
        self.view_service:showMainContent()
    end

    return true
end

-- =============================================================================
-- NAVIGATION PATH MANAGEMENT
-- =============================================================================

function PathService:addToNavigationHistory(nav_data)
    if nav_data and not nav_data.paths_updated then
        -- Add current location to navigation history
        local current_path = {
            title = nav_data.current_title or self.browser.title,
            type = nav_data.current_type or "main",
            page_info = nav_data.page_info,
            nav_data = nav_data.current_data
        }
        table.insert(self.browser.navigation_paths, current_path)
    end
end

function PathService:clearNavigationHistory()
    self.browser.navigation_paths = {}
    self:updateBackButton()
end

function PathService:getNavigationHistoryLength()
    return #self.browser.navigation_paths
end

return PathService
