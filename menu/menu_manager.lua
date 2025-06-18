--[[--
Menu Manager Module

This module handles the construction and management of Miniflux menu items
for the KOReader main menu, including all settings dialogs and UI interactions.

@module koplugin.miniflux.menu.menu_manager
--]]--

local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local MinifluxAPI = require("api/miniflux_api")

---@class MenuManager
---@field browser_launcher BrowserLauncher Browser launcher instance
---@field settings MinifluxSettings Settings instance
---@field api MinifluxAPI API client instance
local MenuManager = {}

---Create a new menu manager with proper dependency injection
---@param dependencies {browser_launcher: BrowserLauncher, settings: MinifluxSettings, api: MinifluxAPI}
---@return MenuManager
function MenuManager:new(dependencies)
    local obj = {
        browser_launcher = dependencies.browser_launcher,
        settings = dependencies.settings,
        api = dependencies.api
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- MENU BUILDING METHODS
-- =============================================================================

---Build the main Miniflux menu structure
---@return table Menu structure for KOReader main menu
function MenuManager:buildMainMenu()
    return {
        text = _("Miniflux"),
        sub_item_table = {
            {
                text = _("Read entries"),
                callback = function()
                    self.browser_launcher:showMainScreen()
                end,
            },
            {
                text = _("Settings"),
                separator = true,
                sub_item_table = {
                    {
                        text = _("Server address"),
                        keep_menu_open = true,
                        callback = function()
                            self:showServerSettings()
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Entries limit - %1"), self.settings:getLimit())
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:showLimitSettings(function()
                                touchmenu_instance:updateItems()
                            end)
                        end,
                    },
                    {
                        text_func = function()
                            local order_names = self:getSortOrderNames()
                            local current_order = self.settings:getOrder()
                            local order_name = order_names[current_order] or _("Published date")
                            return T(_("Sort order - %1"), order_name)
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self:getOrderSubMenu()
                        end,
                    },
                    {
                        text_func = function()
                            local direction_name = self.settings:getDirection() == "asc" 
                                and _("Ascending") or _("Descending")
                            return T(_("Sort direction - %1"), direction_name)
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self:getDirectionSubMenu()
                        end,
                    },
                    {
                        text_func = function()
                            return self.settings:getIncludeImages() 
                                and _("Include images - ON") or _("Include images - OFF")
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self:getIncludeImagesSubMenu()
                        end,
                    },
                    {
                        text = _("Test connection"),
                        keep_menu_open = true,
                        callback = function()
                            self:testConnection()
                        end,
                    },
                },
            },
        },
    }
end

---Get sort order display names mapping
---@return table<string, string> Mapping of order keys to display names
function MenuManager:getSortOrderNames()
    return {
        id = _("ID"),
        status = _("Status"),
        published_at = _("Published date"),
        category_title = _("Category title"),
        category_id = _("Category ID"),
    }
end

---Add Miniflux menu to KOReader main menu
---@param menu_items table The main menu items table
---@return nil
function MenuManager:addToMainMenu(menu_items)
    menu_items.miniflux = self:buildMainMenu()
end

-- =============================================================================
-- SETTINGS DIALOG METHODS
-- =============================================================================

---Show server settings dialog
---@return nil
function MenuManager:showServerSettings()
    local server_address = self.settings:getServerAddress()
    local api_token = self.settings:getApiToken()
    
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
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
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        if fields[1] and fields[1] ~= "" then
                            self.settings:setServerAddress(fields[1])
                        end
                        if fields[2] and fields[2] ~= "" then
                            self.settings:setApiToken(fields[2])
                        end
                        self.settings:save()
                        
                        -- Reinitialize API with new settings (with error handling)
                        local api_success = pcall(function()
                            self.api = MinifluxAPI:new({
                                server_address = self.settings:getServerAddress(),
                                api_token = self.settings:getApiToken()
                            })
                        end)
                        
                        UIManager:close(settings_dialog)
                        
                        if api_success then
                            UIManager:show(InfoMessage:new{
                                text = _("Settings saved"),
                                timeout = 2,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Settings saved (API initialization will be done when needed)"),
                                timeout = 3,
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(settings_dialog)
end

---Show entries limit settings dialog
---@param refresh_callback? function Optional callback to refresh the menu after saving
---@return nil
function MenuManager:showLimitSettings(refresh_callback)
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
                                timeout = 2,
                            })
                            -- Refresh the menu to show updated limit
                            if refresh_callback then
                                refresh_callback()
                            end
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

---Test connection to Miniflux server
---@return nil
function MenuManager:testConnection()
    if self.settings:getServerAddress() == "" or self.settings:getApiToken() == "" then
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
    self.api = MinifluxAPI:new({
        server_address = self.settings:getServerAddress(),
        api_token = self.settings:getApiToken()
    })
    
    local success, result = self.api:testConnection()
    
    -- Close the "testing" message
    UIManager:close(connection_info)
    
    -- Show the result
    UIManager:show(InfoMessage:new{
        text = result,
        timeout = success and 3 or 5,
    })
end

---Get sort order submenu items
---@return table[] Sort order menu items
function MenuManager:getOrderSubMenu()
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

---Get sort direction submenu items
---@return table[] Sort direction menu items
function MenuManager:getDirectionSubMenu()
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

---Get include images submenu items
---@return table[] Include images menu items
function MenuManager:getIncludeImagesSubMenu()
    local current_include_images = self.settings:getIncludeImages()
    
    return {
        {
            text = _("ON") .. (current_include_images and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setIncludeImages(true)
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Images will be downloaded with entries"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("OFF") .. (not current_include_images and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setIncludeImages(false)
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Images will be skipped when downloading entries"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
    }
end

return MenuManager 