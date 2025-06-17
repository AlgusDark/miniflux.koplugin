--[[--
Settings UI Dialogs Module

This module handles all user interface elements related to settings configuration,
including dialogs for server settings, limits, connection testing, and menu generation.

@module koplugin.miniflux.settings.ui.settings_dialogs
--]]--

local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

---@class MenuSubItem
---@field text string|function Menu item text or text function
---@field text_func? function Function to generate dynamic text
---@field keep_menu_open? boolean Whether to keep menu open after selection
---@field callback? function Function to call when item is selected
---@field sub_item_table? table[] Sub-items for this menu item
---@field sub_item_table_func? function Function to generate sub-items

---@class SettingsDialogs
---@field settings table Settings module instance
---@field api MinifluxAPI API client instance
---@field settings_dialog MultiInputDialog|nil Current settings dialog
local SettingsDialogs = {}

---Create a new settings dialogs instance
---@param o? table Optional initialization table
---@return SettingsDialogs
function SettingsDialogs:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the settings dialogs with required dependencies
---@param settings table Settings module instance
---@param api MinifluxAPI API client instance
---@return SettingsDialogs self for method chaining
function SettingsDialogs:init(settings, api)
    self.settings = settings
    self.api = api
    return self
end

---Show server settings dialog
---@return nil
function SettingsDialogs:showServerSettings()
    local server_address = self.settings.getServerAddress()
    local api_token = self.settings.getApiToken()
    
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
                            self.settings.setServerAddress(fields[1])
                        end
                        if fields[2] and fields[2] ~= "" then
                            self.settings.setApiToken(fields[2])
                        end
                        self.settings.save()
                        
                        -- Reinitialize API with new settings
                        self.api:init(self.settings.getServerAddress(), self.settings.getApiToken())
                        
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

---Show entries limit settings dialog
---@param refresh_callback? function Optional callback to refresh the menu after saving
---@return nil
function SettingsDialogs:showLimitSettings(refresh_callback)
    local current_limit = tostring(self.settings.getLimit())
    
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
                            self.settings.setLimit(new_limit)
                            self.settings.save()
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
function SettingsDialogs:testConnection()
    if not self.settings.isConfigured() then
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
    self.api:init(self.settings.getServerAddress(), self.settings.getApiToken())
    
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
---@return MenuSubItem[] Sort order menu items
function SettingsDialogs:getOrderSubMenu()
    local current_order = self.settings.getOrder()
    
    return {
        {
            text = _("ID") .. (current_order == "id" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings.setOrder("id")
                self.settings.save()
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
                self.settings.setOrder("status")
                self.settings.save()
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
                self.settings.setOrder("published_at")
                self.settings.save()
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
                self.settings.setOrder("category_title")
                self.settings.save()
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
                self.settings.setOrder("category_id")
                self.settings.save()
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
---@return MenuSubItem[] Sort direction menu items
function SettingsDialogs:getDirectionSubMenu()
    local current_direction = self.settings.getDirection()
    
    return {
        {
            text = _("Ascending") .. (current_direction == "asc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings.setDirection("asc")
                self.settings.save()
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
                self.settings.setDirection("desc")
                self.settings.save()
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

return SettingsDialogs 