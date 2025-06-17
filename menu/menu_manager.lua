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

---@class MenuManager
local MenuManager = {}

---Create a new menu manager
---@return MenuManager
function MenuManager:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- MENU BUILDING METHODS
-- =============================================================================

---Build the main Miniflux menu structure
---@param plugin_instance table The main plugin instance with initialized modules
---@return table Menu structure for KOReader main menu
function MenuManager:buildMainMenu(plugin_instance)
    return {
        text = _("Miniflux"),
        sub_item_table = {
            self:buildReadEntriesItem(plugin_instance),
            self:buildSettingsMenu(plugin_instance),
        },
    }
end

---Build the "Read entries" menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildReadEntriesItem(plugin_instance)
    return {
        text = _("Read entries"),
        callback = function()
            plugin_instance.browser_launcher:showMainScreen()
        end,
    }
end

---Build the settings submenu
---@param plugin_instance table The main plugin instance
---@return table Settings menu structure
function MenuManager:buildSettingsMenu(plugin_instance)
    return {
        text = _("Settings"),
        separator = true,
        sub_item_table = {
            self:buildServerAddressItem(plugin_instance),
            self:buildEntriesLimitItem(plugin_instance),
            self:buildSortOrderItem(plugin_instance),
            self:buildSortDirectionItem(plugin_instance),
            self:buildIncludeImagesItem(plugin_instance),
            self:buildTestConnectionItem(plugin_instance),
        },
    }
end

---Build the server address menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildServerAddressItem(plugin_instance)
    return {
        text = _("Server address"),
        keep_menu_open = true,
        callback = function()
            self:showServerSettings(plugin_instance)
        end,
    }
end

---Build the entries limit menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildEntriesLimitItem(plugin_instance)
    return {
        text_func = function()
            return T(_("Entries limit - %1"), plugin_instance.settings:getLimit())
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:showLimitSettings(plugin_instance, function()
                touchmenu_instance:updateItems()
            end)
        end,
    }
end

---Build the sort order menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildSortOrderItem(plugin_instance)
    return {
        text_func = function()
            local order_names = self:getSortOrderNames()
            local current_order = plugin_instance.settings:getOrder()
            local order_name = order_names[current_order] or _("Published date")
            return T(_("Sort order - %1"), order_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return self:getOrderSubMenu(plugin_instance)
        end,
    }
end

---Build the sort direction menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildSortDirectionItem(plugin_instance)
    return {
        text_func = function()
            local direction_name = plugin_instance.settings:getDirection() == "asc" 
                and _("Ascending") or _("Descending")
            return T(_("Sort direction - %1"), direction_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return self:getDirectionSubMenu(plugin_instance)
        end,
    }
end

---Build the include images menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildIncludeImagesItem(plugin_instance)
    return {
        text_func = function()
            return plugin_instance.settings:getIncludeImages() 
                and _("Include images - ON") or _("Include images - OFF")
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return self:getIncludeImagesSubMenu(plugin_instance)
        end,
    }
end

---Build the test connection menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildTestConnectionItem(plugin_instance)
    return {
        text = _("Test connection"),
        keep_menu_open = true,
        callback = function()
            self:testConnection(plugin_instance)
        end,
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
---@param plugin_instance table The main plugin instance
---@return nil
function MenuManager:addToMainMenu(menu_items, plugin_instance)
    menu_items.miniflux = self:buildMainMenu(plugin_instance)
end

-- =============================================================================
-- SETTINGS DIALOG METHODS (moved from settings_dialogs.lua)
-- =============================================================================

---Show server settings dialog
---@param plugin_instance table The main plugin instance
---@return nil
function MenuManager:showServerSettings(plugin_instance)
    local server_address = plugin_instance.settings:getServerAddress()
    local api_token = plugin_instance.settings:getApiToken()
    
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
                            plugin_instance.settings:setServerAddress(fields[1])
                        end
                        if fields[2] and fields[2] ~= "" then
                            plugin_instance.settings:setApiToken(fields[2])
                        end
                        plugin_instance.settings:save()
                        
                        -- Reinitialize API with new settings (with error handling)
                        local api_success = pcall(function()
                            plugin_instance.api:init(plugin_instance.settings:getServerAddress(), plugin_instance.settings:getApiToken())
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
---@param plugin_instance table The main plugin instance
---@param refresh_callback? function Optional callback to refresh the menu after saving
---@return nil
function MenuManager:showLimitSettings(plugin_instance, refresh_callback)
    local current_limit = tostring(plugin_instance.settings:getLimit())
    
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
                            plugin_instance.settings:setLimit(new_limit)
                            plugin_instance.settings:save()
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
---@param plugin_instance table The main plugin instance
---@return nil
function MenuManager:testConnection(plugin_instance)
    if not plugin_instance.settings:isConfigured() then
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
    plugin_instance.api:init(plugin_instance.settings:getServerAddress(), plugin_instance.settings:getApiToken())
    
    local success, result = plugin_instance.api:testConnection()
    
    -- Close the "testing" message
    UIManager:close(connection_info)
    
    -- Show the result
    UIManager:show(InfoMessage:new{
        text = result,
        timeout = success and 3 or 5,
    })
end

---Get sort order submenu items
---@param plugin_instance table The main plugin instance
---@return table[] Sort order menu items
function MenuManager:getOrderSubMenu(plugin_instance)
    local current_order = plugin_instance.settings:getOrder()
    
    return {
        {
            text = _("ID") .. (current_order == "id" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                plugin_instance.settings:setOrder("id")
                plugin_instance.settings:save()
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
                plugin_instance.settings:setOrder("status")
                plugin_instance.settings:save()
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
                plugin_instance.settings:setOrder("published_at")
                plugin_instance.settings:save()
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
                plugin_instance.settings:setOrder("category_title")
                plugin_instance.settings:save()
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
                plugin_instance.settings:setOrder("category_id")
                plugin_instance.settings:save()
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
---@param plugin_instance table The main plugin instance
---@return table[] Sort direction menu items
function MenuManager:getDirectionSubMenu(plugin_instance)
    local current_direction = plugin_instance.settings:getDirection()
    
    return {
        {
            text = _("Ascending") .. (current_direction == "asc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                plugin_instance.settings:setDirection("asc")
                plugin_instance.settings:save()
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
                plugin_instance.settings:setDirection("desc")
                plugin_instance.settings:save()
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
---@param plugin_instance table The main plugin instance
---@return table[] Include images menu items
function MenuManager:getIncludeImagesSubMenu(plugin_instance)
    local current_include_images = plugin_instance.settings:getIncludeImages()
    
    return {
        {
            text = _("ON") .. (current_include_images and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                plugin_instance.settings:setIncludeImages(true)
                plugin_instance.settings:save()
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
                plugin_instance.settings:setIncludeImages(false)
                plugin_instance.settings:save()
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