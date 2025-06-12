--[[--
This plugin provides integration with Miniflux RSS reader.

@module koplugin.miniflux
--]]
--

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import our modules
local MinifluxAPI = require("api/api_client")
local MinifluxSettingsManager = require("settings/settings_manager")
local MinifluxUI = require("miniflux_ui")

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field download_dir_name string Directory name for downloads
---@field download_dir string Full path to download directory
---@field settings SettingsManager Settings manager instance
---@field api MinifluxAPI API client instance
---@field miniflux_ui MinifluxUI UI manager instance
local Miniflux = WidgetContainer:extend({
    name = "miniflux",
    download_dir_name = "miniflux",
    download_dir = nil,
    is_doc_only = false,
})

---Register dispatcher actions for the plugin
---@return nil
function Miniflux:onDispatcherRegisterActions()
    Dispatcher:registerAction("miniflux_read_entries", {
        category = "none",
        event = "ReadMinifluxEntries",
        title = _("Read Miniflux entries"),
        general = true,
    })
end

---Initialize the plugin
---@return nil
function Miniflux:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    -- Initialize download directory
    self:initializeDownloadDirectory()

    -- Initialize modules
    self.settings = MinifluxSettingsManager
    self.settings:init()  -- Initialize the settings manager
    self.api = MinifluxAPI:new()
    self.miniflux_ui = MinifluxUI:new()

    -- Initialize UI with settings, API, and download_dir
    self.miniflux_ui:init(self.settings, self.api, self.download_dir)

    -- Initialize API with current settings if available
    if self.settings:isConfigured() then
        self.api:init(self.settings:getServerAddress(), self.settings:getApiToken())
    end
end

---Initialize the download directory for entries
---@return nil
function Miniflux:initializeDownloadDirectory()
    -- Set up download directory similar to newsdownloader
    self.download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), self.download_dir_name)

    -- Create the directory if it doesn't exist
    if not lfs.attributes(self.download_dir, "mode") then
        logger.dbg("Miniflux: Creating download directory:", self.download_dir)
        lfs.mkdir(self.download_dir)
    end
end

---Add Miniflux items to the main menu
---@param menu_items table The main menu items table
---@return nil
function Miniflux:addToMainMenu(menu_items)
    menu_items.miniflux = {
        text = _("Miniflux"),
        sub_item_table = {
            {
                text = _("Read entries"),
                callback = function()
                    self.miniflux_ui:showMainScreen()
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
                            self.miniflux_ui:showServerSettings()
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Entries limit - %1"), self.settings:getLimit())
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self.miniflux_ui:showLimitSettings()
                        end,
                    },
                    {
                        text_func = function()
                            local order_names = {
                                id = _("ID"),
                                status = _("Status"),
                                published_at = _("Published date"),
                                category_title = _("Category title"),
                                category_id = _("Category ID"),
                            }
                            local current_order = self.settings:getOrder()
                            local order_name = order_names[current_order] or _("Published date")
                            return T(_("Sort order - %1"), order_name)
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self.miniflux_ui:getOrderSubMenu()
                        end,
                    },
                    {
                        text_func = function()
                            local direction_name = self.settings:getDirection() == "asc" and _("Ascending")
                                or _("Descending")
                            return T(_("Sort direction - %1"), direction_name)
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self.miniflux_ui:getDirectionSubMenu()
                        end,
                    },
                    {
                        text_func = function()
                            return self.settings:getIncludeImages() and _("Include images - ON")
                                or _("Include images - OFF")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local new_value = self.settings:toggleIncludeImages()
                            local message = new_value and _("Images will be downloaded with entries")
                                or _("Images will be skipped when downloading entries")
                            UIManager:show(InfoMessage:new({
                                text = message,
                                timeout = 2,
                            }))
                            touchmenu_instance:updateItems()
                        end,
                    },
                    {
                        text = _("Test connection"),
                        keep_menu_open = true,
                        callback = function()
                            self.miniflux_ui:testConnection()
                        end,
                    },
                },
            },
        },
    }
end

---Handle the read entries dispatcher event
---@return nil
function Miniflux:onReadMinifluxEntries()
    self.miniflux_ui:showMainScreen()
end

return Miniflux
