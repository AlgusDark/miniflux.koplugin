--[[--
Main Menu Structure for Miniflux Plugin

Simple menu builder that coordinates with individual settings components.
Replaces the over-engineered MenuManager with clean, modular approach.

@module miniflux.menu.menu
--]]

local _ = require("gettext")

-- Import settings components
local ServerConfig = require("menu/settings/server_config")
local Entries = require("menu/settings/entries")
local SortOrder = require("menu/settings/sort_order")
local SortDirection = require("menu/settings/sort_direction")
local IncludeImages = require("menu/settings/include_images")
local MarkAsReadOnOpen = require("menu/settings/mark_as_read_on_open")
local CopyCss = require("menu/settings/copy_css")
local TestConnection = require("menu/settings/test_connection")

local Menu = {}

---Build the main Miniflux menu structure
---@param plugin Miniflux Plugin instance with settings, api, and browser creation
---@return table Menu structure for KOReader main menu
function Menu.build(plugin)
    return {
        text = _("Miniflux"),
        sub_item_table = {
            {
                text = _("Read entries"),
                callback = function()
                    local browser = plugin:createBrowser()
                    browser:open()
                end,
            },
            {
                text = _("Settings"),
                separator = true,
                sub_item_table = {
                    ServerConfig.getMenuItem(plugin.settings),
                    Entries.getMenuItem(plugin.settings),
                    SortOrder.getMenuItem(plugin.settings),
                    SortDirection.getMenuItem(plugin.settings),
                    IncludeImages.getMenuItem(plugin.settings),
                    MarkAsReadOnOpen.getMenuItem(plugin.settings),
                    CopyCss.getMenuItem(plugin),
                    TestConnection.getMenuItem(plugin.miniflux_api),
                }
            },
        },
    }
end

return Menu
