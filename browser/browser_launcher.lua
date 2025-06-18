--[[--
Browser Launcher Module

This module handles browser initialization, data fetching, and main screen creation.
It coordinates between the API, settings, and browser modules to launch the Miniflux browser.

@module koplugin.miniflux.browser.browser_launcher
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

---@class BrowserLauncher
---@field settings table Settings module instance
---@field api MinifluxAPI API client instance
---@field download_dir string Download directory path
---@field miniflux_browser any Current browser instance
local BrowserLauncher = {}

---Create a new browser launcher instance
---@param o? table Optional initialization table
---@return BrowserLauncher
function BrowserLauncher:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the browser launcher with required dependencies
---@param settings table Settings module instance
---@param api MinifluxAPI API client instance
---@param download_dir string Download directory path
---@return BrowserLauncher self for method chaining
function BrowserLauncher:init(settings, api, download_dir)
    self.settings = settings
    self.api = api
    self.download_dir = download_dir
    return self
end

---Show the main Miniflux browser screen
---@return nil
function BrowserLauncher:showMainScreen()
    if not self.settings:isConfigured() then
        UIManager:show(InfoMessage:new{
            text = _("Please configure server settings first"),
            timeout = 3,
        })
        return
    end
    
    -- Show loading message while fetching count
    local loading_info = InfoMessage:new{
        text = _("Loading Miniflux data..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint() -- Force immediate display before API calls
    
    -- Initialize API with current settings
    local api_success = pcall(function()
        local MinifluxAPI = require("api/miniflux_api")
        self.api = MinifluxAPI:new({
            server_address = self.settings:getServerAddress(),
            api_token = self.settings:getApiToken()
        })
    end)
    
    if not api_success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Failed to initialize API connection"),
            timeout = 5,
        })
        return
    end
    
    -- Fetch initial data for browser
    local unread_count, feeds_count, categories_count = self:fetchInitialData(loading_info)
    
    if not unread_count then
        -- Error already handled in fetchInitialData
        return
    end
    
    -- Close loading message and prepare for browser creation
    UIManager:close(loading_info)
    
    -- Ensure all values are numbers (fallback to 0 if nil)
    unread_count = unread_count or 0
    feeds_count = feeds_count or 0
    categories_count = categories_count or 0
    
    -- Add a small delay to ensure UI operations are complete before creating browser
    UIManager:scheduleIn(0.1, function()
        self:createAndShowBrowser(unread_count, feeds_count, categories_count)
    end)
end

---Fetch initial data needed for browser initialization
---@param loading_info InfoMessage Loading message to update
---@return number|nil unread_count, number|nil feeds_count, number|nil categories_count
function BrowserLauncher:fetchInitialData(loading_info)
    -- Get unread count
    local unread_count = self:fetchUnreadCount(loading_info)
    if not unread_count then
        return nil
    end
    
    -- Get feeds count
    local feeds_count = self:fetchFeedsCount(loading_info)
    if not feeds_count then
        return nil
    end
    
    -- Get categories count
    local categories_count = self:fetchCategoriesCount(loading_info)
    if not categories_count then
        return nil
    end
    
    return unread_count, feeds_count, categories_count
end

---Fetch unread entries count
---@param loading_info InfoMessage Loading message to close on error
---@return number|nil Unread count or nil on error
function BrowserLauncher:fetchUnreadCount(loading_info)
    -- Use proper settings for API call instead of hardcoded values
    local options = {
        order = self.settings:getOrder(),
        direction = self.settings:getDirection(),
    }
    options.limit = 1  -- We only need one entry to get the total count
    options.status = {"unread"}  -- Only unread for count
    
    -- Wrap API calls in pcall to catch network errors
    local success, result
    local api_call_success = pcall(function()
        success, result = self.api.entries:getEntries(options)
    end)
    
    if not api_call_success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Network error while fetching entries"),
            timeout = 5,
        })
        return nil
    end
    
    if not success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Failed to connect to Miniflux: ") .. tostring(result),
            timeout = 5,
        })
        return nil
    end
    
    return (result and result.total) and result.total or 0
end

---Fetch feeds count
---@param loading_info InfoMessage Loading message to update
---@return number|nil Feeds count or nil on error
function BrowserLauncher:fetchFeedsCount(loading_info)
    -- Update loading message for next operation
    UIManager:close(loading_info)
    loading_info = InfoMessage:new{
        text = _("Loading feeds data..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get feeds count with error handling
    local feeds_success, feeds_result
    local feeds_call_success = pcall(function()
        feeds_success, feeds_result = self.api.feeds:getFeeds()
    end)
    
    -- Close the loading message before returning
    UIManager:close(loading_info)
    
    if feeds_call_success and feeds_success and feeds_result then
        return #feeds_result
    else
        return 0  -- Continue with 0 feeds instead of failing
    end
end

---Fetch categories count
---@param loading_info InfoMessage Loading message to update
---@return number|nil Categories count or nil on error
function BrowserLauncher:fetchCategoriesCount(loading_info)
    -- Update loading message for next operation
    UIManager:close(loading_info)
    loading_info = InfoMessage:new{
        text = _("Loading categories data..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get categories count with error handling
    local categories_success, categories_result
    local categories_call_success = pcall(function()
        categories_success, categories_result = self.api.categories:getCategories()
    end)
    
    -- Close the loading message before returning
    UIManager:close(loading_info)
    
    if categories_call_success and categories_success and categories_result then
        return #categories_result
    else
        return 0  -- Continue with 0 categories instead of failing
    end
end

---Create and show the browser with fetched data
---@param unread_count number Number of unread entries
---@param feeds_count number Number of feeds
---@param categories_count number Number of categories
---@return nil
function BrowserLauncher:createAndShowBrowser(unread_count, feeds_count, categories_count)
    -- Create browser with proper error handling
    local browser_success = pcall(function()
        -- Use the new consolidated browser
        local MinifluxBrowser = require("browser/browser")
        self.miniflux_browser = MinifluxBrowser:new{
            title = _("Miniflux"),
            settings = self.settings,
            api = self.api,
            download_dir = self.download_dir,
            unread_count = unread_count,
            feeds_count = feeds_count,
            categories_count = categories_count,
            close_callback = function()
                UIManager:close(self.miniflux_browser)
                self.miniflux_browser = nil
            end,
        }
        
        UIManager:show(self.miniflux_browser)
    end)
    
    if not browser_success then
        UIManager:show(InfoMessage:new{
            text = _("Failed to create browser interface"),
            timeout = 5,
        })
    end
end

return BrowserLauncher 