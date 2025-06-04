--[[--
Miniflux UI components module

@module koplugin.miniflux.ui
--]]--

local Widget = require("ui/widget/widget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Size = require("ui/size")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local _ = require("gettext")
local T = require("ffi/util").template

local MinifluxUI = {}

function MinifluxUI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MinifluxUI:init(settings, api, debug, download_dir)
    self.settings = settings
    self.api = api
    self.debug = debug
    self.download_dir = download_dir
    return self
end

function MinifluxUI:showServerSettings()
    local server_address = self.settings:getServerAddress()
    local api_token = self.settings:getApiToken()
    
    self.settings_dialog = MultiInputDialog:new{
        title = _("Miniflux server settings"),
        fields = {
            {
                text = server_address,
                input_type = "string",
                hint = _("Server address (e.g., https://miniflux.example.com)"),
            },
            {
                text = api_token,
                input_type = "string",
                hint = _("API Token"),
                text_type = "password",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.settings_dialog:getFields()
                        if fields[1] and fields[1] ~= "" then
                            self.settings:setServerAddress(fields[1])
                        end
                        if fields[2] and fields[2] ~= "" then
                            self.settings:setApiToken(fields[2])
                        end
                        self.settings:save()
                        
                        -- Reinitialize API with new settings
                        self.api:init(self.settings:getServerAddress(), self.settings:getApiToken())
                        
                        UIManager:close(self.settings_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Settings saved"),
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
end

function MinifluxUI:showLimitSettings()
    local current_limit = tostring(self.settings:getLimit())
    
    local limit_dialog
    limit_dialog = InputDialog:new{
        title = _("Entries limit"),
        input = current_limit,
        input_type = "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(limit_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_limit = tonumber(limit_dialog:getInputText())
                        if new_limit and new_limit > 0 then
                            self.settings:setLimit(new_limit)
                            self.settings:save()
                            UIManager:close(limit_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Entries limit saved"),
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a valid number greater than 0"),
                                timeout = 3,
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(limit_dialog)
end

function MinifluxUI:testConnection()
    if not self.settings:isConfigured() then
        UIManager:show(InfoMessage:new{
            text = _("Please configure server address and API token first"),
        })
        return
    end
    
    local connection_info = InfoMessage:new{
        text = _("Testing connection to Miniflux server..."),
    }
    UIManager:show(connection_info)
    UIManager:forceRePaint() -- Force immediate display before API call
    
    -- Reinitialize API with current settings
    self.api:init(self.settings:getServerAddress(), self.settings:getApiToken())
    
    local success, result = self.api:testConnection()
    
    -- Close the "testing" message
    UIManager:close(connection_info)
    
    -- Show the result
    UIManager:show(InfoMessage:new{
        text = result,
        timeout = success and 3 or 5,
    })
end

function MinifluxUI:showMainScreen()
    if self.debug then self.debug:info("showMainScreen called") end
    
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
        self.api:init(self.settings:getServerAddress(), self.settings:getApiToken())
    end)
    
    if not api_success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Failed to initialize API connection"),
            timeout = 5,
        })
        return
    end
    
    -- Use proper settings for API call instead of hardcoded values
    local BrowserUtils = require("browser/lib/browser_utils")
    local options = BrowserUtils.getApiOptions(self.settings)
    options.limit = 1  -- We only need one entry to get the total count
    options.status = {"unread"}  -- Only unread for count
    
    -- Wrap API calls in pcall to catch network errors
    local success, result
    local api_call_success = pcall(function()
        success, result = self.api:getEntries(options)
    end)
    
    if not api_call_success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Network error while fetching entries"),
            timeout = 5,
        })
        return
    end
    
    if not success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Failed to connect to Miniflux: ") .. tostring(result),
            timeout = 5,
        })
        return
    end
    
    local unread_count = (result and result.total) and result.total or 0
    if self.debug then self.debug:info("Fetched unread count: " .. unread_count) end
    
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
        feeds_success, feeds_result = self.api:getFeeds()
    end)
    
    local feeds_count = 0
    if feeds_call_success and feeds_success and feeds_result then
        feeds_count = #feeds_result
        if self.debug then self.debug:info("Fetched " .. feeds_count .. " feeds") end
    else
        if self.debug then 
            local error_msg = not feeds_call_success and "Network error" or tostring(feeds_result)
            self.debug:warn("Failed to fetch feeds: " .. error_msg) 
        end
    end
    
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
        categories_success, categories_result = self.api:getCategories()
    end)
    
    local categories_count = 0
    if categories_call_success and categories_success and categories_result then
        categories_count = #categories_result
        if self.debug then self.debug:info("Fetched " .. categories_count .. " categories") end
    else
        if self.debug then 
            local error_msg = not categories_call_success and "Network error" or tostring(categories_result)
            self.debug:warn("Failed to fetch categories: " .. error_msg) 
        end
    end
    
    -- Close loading message and prepare for browser creation
    UIManager:close(loading_info)
    
    -- Add a small delay to ensure UI operations are complete before creating browser
    UIManager:scheduleIn(0.1, function()
        -- Create browser with proper error handling
        local browser_success = pcall(function()
            -- Use the main browser with single instance pattern (like OPDS)
            local MainBrowser = require("browser/main_browser")
            self.miniflux_browser = MainBrowser:new{
                title = _("Miniflux"),
                settings = self.settings,
                api = self.api,
                debug = self.debug,
                download_dir = self.download_dir,
                unread_count = unread_count,
                feeds_count = feeds_count,
                categories_count = categories_count,
                close_callback = function()
                    if self.debug then self.debug:info("MinifluxBrowser close_callback called") end
                    UIManager:close(self.miniflux_browser)
                    self.miniflux_browser = nil
                end,
            }
            
            if self.debug then self.debug:info("MinifluxBrowser created and about to show") end
            UIManager:show(self.miniflux_browser)
        end)
        
        if not browser_success then
            if self.debug then self.debug:error("Failed to create or show MinifluxBrowser") end
            UIManager:show(InfoMessage:new{
                text = _("Failed to create browser interface"),
                timeout = 5,
            })
        end
    end)
end

function MinifluxUI:showDebugLog()
    if not self.debug then
        UIManager:show(InfoMessage:new{
            text = _("Debug system not initialized"),
            timeout = 3,
        })
        return
    end
    
    local content = self.debug:getLogContent()
    local TextViewer = require("ui/widget/textviewer")
    local text_viewer = TextViewer:new{
        title = _("Miniflux Debug Log"),
        text = content,
        text_face = Font:getFace("smallinfofont"),
        justified = false,
        buttons_table = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(text_viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(text_viewer)
end

function MinifluxUI:getOrderSubMenu()
    local current_order = self.settings:getOrder()
    
    return {
        {
            text = _("ID") .. (current_order == "id" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setOrder("id")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort order updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Status") .. (current_order == "status" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setOrder("status")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort order updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Published date") .. (current_order == "published_at" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setOrder("published_at")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort order updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Category title") .. (current_order == "category_title" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setOrder("category_title")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort order updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Category ID") .. (current_order == "category_id" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setOrder("category_id")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort order updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
    }
end

function MinifluxUI:getDirectionSubMenu()
    local current_direction = self.settings:getDirection()
    
    return {
        {
            text = _("Ascending") .. (current_direction == "asc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setDirection("asc")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort direction updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Descending") .. (current_direction == "desc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setDirection("desc")
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Sort direction updated"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
    }
end

return MinifluxUI 