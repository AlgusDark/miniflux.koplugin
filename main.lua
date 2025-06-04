--[[--
This plugin provides integration with Miniflux RSS reader.

@module koplugin.miniflux
--]]--

local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import our modules
local MinifluxAPI = require("api")
local MinifluxSettings = require("settings")
local MinifluxUI = require("miniflux_ui")
local MinifluxDebug = require("lib/debug")

local Miniflux = WidgetContainer:extend{
    name = "miniflux",
    download_dir_name = "miniflux",
    download_dir = nil,
}

function Miniflux:onDispatcherRegisterActions()
    Dispatcher:registerAction("miniflux_read_entries", {
        category = "none",
        event = "ReadMinifluxEntries",
        title = _("Read Miniflux entries"),
        general = true,
    })
end

function Miniflux:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    
    -- Initialize download directory
    self:initializeDownloadDirectory()
    
    -- Initialize modules
    self.settings = MinifluxSettings
    self.api = MinifluxAPI:new()
    self.miniflux_ui = MinifluxUI:new()
    self.debug = MinifluxDebug:new()
    
    -- Initialize debug logging
    self.debug:init(self.settings, self.path)
    
    -- Initialize UI with settings, API, debug, and download_dir
    self.miniflux_ui:init(self.settings, self.api, self.debug, self.download_dir)
    
    -- Initialize API with current settings if available
    if self.settings:isConfigured() then
        self.api:init(self.settings:getServerAddress(), self.settings:getApiToken())
    end
    
    if self.debug then
        self.debug:info("Miniflux plugin initialized successfully")
        self.debug:info("Download directory: " .. self.download_dir)
    end
end

function Miniflux:initializeDownloadDirectory()
    -- Set up download directory similar to newsdownloader
    self.download_dir = ("%s/%s/"):format(
        DataStorage:getFullDataDir(),
        self.download_dir_name)
    
    -- Create the directory if it doesn't exist
    if not lfs.attributes(self.download_dir, "mode") then
        logger.dbg("Miniflux: Creating download directory:", self.download_dir)
        lfs.mkdir(self.download_dir)
    end
end

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
                                category_id = _("Category ID")
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
                            local direction_name = self.settings:getDirection() == "asc" and _("Ascending") or _("Descending")
                            return T(_("Sort direction - %1"), direction_name)
                        end,
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self.miniflux_ui:getDirectionSubMenu()
                        end,
                    },
                    {
                        text_func = function()
                            return self.settings:getIncludeImages() and _("Include images - ON") or _("Include images - OFF")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local new_value = self.settings:toggleIncludeImages()
                            local message = new_value and _("Images will be downloaded with entries") or _("Images will be skipped when downloading entries")
                            UIManager:show(InfoMessage:new{
                                text = message,
                                timeout = 2,
                            })
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
                    {
                        text = _("Debug"),
                        separator = true,
                        sub_item_table = {
                            {
                                text_func = function()
                                    return self.settings:getDebugLogging() and _("Debug logging - ON") or _("Debug logging - OFF")
                                end,
                                keep_menu_open = true,
                                sub_item_table_func = function()
                                    return self:getDebugSubMenu()
                                end,
                            },
                            {
                                text = _("View debug log"),
                                keep_menu_open = true,
                                callback = function()
                                    self.miniflux_ui:showDebugLog()
                                end,
                            },
                            {
                                text = _("Clear debug log"),
                                keep_menu_open = true,
                                callback = function()
                                    self.debug:clearLog()
                                    UIManager:show(InfoMessage:new{
                                        text = _("Debug log cleared"),
                                        timeout = 2,
                                    })
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

function Miniflux:onReadMinifluxEntries()
    self.miniflux_ui:showMainScreen()
end

function Miniflux:getDebugSubMenu()
    local current_debug = self.settings:getDebugLogging()
    
    return {
        {
            text = _("Enable") .. (current_debug and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self.settings:setDebugLogging(true)
                self.settings:save()
                if self.debug then self.debug:info("Debug logging enabled via menu") end
                UIManager:show(InfoMessage:new{
                    text = _("Debug logging enabled"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
        {
            text = _("Disable") .. (not current_debug and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                if self.debug then self.debug:info("Debug logging disabled via menu") end
                self.settings:setDebugLogging(false)
                self.settings:save()
                UIManager:show(InfoMessage:new{
                    text = _("Debug logging disabled"),
                    timeout = 2,
                    dismiss_callback = function()
                        touchmenu_instance:backToUpperMenu()
                    end,
                })
            end,
        },
    }
end

return Miniflux 