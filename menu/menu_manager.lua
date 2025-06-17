--[[--
Menu Manager Module

This module handles the construction and management of Miniflux menu items
for the KOReader main menu, following the single responsibility principle.

@module koplugin.miniflux.menu.menu_manager
--]]--

local InfoMessage = require("ui/widget/infomessage")
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
            plugin_instance.settings_dialogs:showServerSettings()
        end,
    }
end

---Build the entries limit menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildEntriesLimitItem(plugin_instance)
    return {
        text_func = function()
            return T(_("Entries limit - %1"), plugin_instance.settings.getLimit())
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            plugin_instance.settings_dialogs:showLimitSettings(function()
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
            local current_order = plugin_instance.settings.getOrder()
            local order_name = order_names[current_order] or _("Published date")
            return T(_("Sort order - %1"), order_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return plugin_instance.settings_dialogs:getOrderSubMenu()
        end,
    }
end

---Build the sort direction menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildSortDirectionItem(plugin_instance)
    return {
        text_func = function()
            local direction_name = plugin_instance.settings.getDirection() == "asc" 
                and _("Ascending") or _("Descending")
            return T(_("Sort direction - %1"), direction_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return plugin_instance.settings_dialogs:getDirectionSubMenu()
        end,
    }
end

---Build the include images menu item
---@param plugin_instance table The main plugin instance
---@return table Menu item structure
function MenuManager:buildIncludeImagesItem(plugin_instance)
    return {
        text_func = function()
            return plugin_instance.settings.getIncludeImages() 
                and _("Include images - ON") or _("Include images - OFF")
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return plugin_instance.settings_dialogs:getIncludeImagesSubMenu()
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
            plugin_instance.settings_dialogs:testConnection()
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

return MenuManager 