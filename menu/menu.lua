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

---@class Menu
local Menu = {}

---Build the main menu structure for the Miniflux plugin
---@param plugin Miniflux The main plugin instance
---@return table menu_structure KOReader submenu structure
function Menu.build(plugin)
    return {
        text = _("Miniflux"),
        sub_item_table = {
            -- === BROWSER OPTIONS ===
            {
                text = _("Read entries"),
                help_text = _("Browse RSS entries"),
                callback = function()
                    local browser = plugin:createBrowser()
                    browser:open()
                end,
            },

            -- === SETTINGS SUBMENU ===
            {
                text = _("Settings"),
                separator = true,
                sub_item_table = {
                    -- === CONNECTION SETTINGS ===
                    ServerConfig.getMenuItem(plugin.settings),
                    TestConnection.getMenuItem(plugin.miniflux_api),

                    -- === DISPLAY SETTINGS ===
                    Entries.getMenuItem(plugin.settings),
                    SortOrder.getMenuItem(plugin.settings),
                    SortDirection.getMenuItem(plugin.settings),
                    IncludeImages.getMenuItem(plugin.settings),
                    MarkAsReadOnOpen.getMenuItem(plugin.settings),
                    CopyCss.getMenuItem(plugin),
                }
            },
        }
    }
end

return Menu
