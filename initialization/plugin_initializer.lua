--[[--
Plugin Initializer Module

This module handles the initialization of all Miniflux plugin components,
following dependency injection patterns used throughout the codebase.

@module koplugin.miniflux.initialization.plugin_initializer
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- Import plugin modules
local MinifluxAPI = require("api/api_client")
local MinifluxSettings = require("settings/settings")
local SettingsDialogs = require("settings/ui/settings_dialogs")
local BrowserLauncher = require("browser/ui/browser_launcher")

---@class PluginInitializer
---@field download_dir_name string Directory name for downloads
local PluginInitializer = {}

---Create a new plugin initializer
---@return PluginInitializer
function PluginInitializer:new()
    local obj = {
        download_dir_name = "miniflux"
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Initialize all plugin components
---@param plugin_instance table The main plugin instance to initialize
---@return boolean True if initialization successful
function PluginInitializer:initializePlugin(plugin_instance)
    -- Initialize download directory
    local download_dir = self:initializeDownloadDirectory()
    if not download_dir then
        logger.err("Failed to initialize download directory")
        return false
    end
    plugin_instance.download_dir = download_dir

    -- Initialize settings (no OOP needed anymore)
    plugin_instance.settings = MinifluxSettings
    plugin_instance.settings.init()

    -- Initialize API client
    plugin_instance.api = MinifluxAPI:new()

    -- Initialize UI modules with dependency injection
    plugin_instance.settings_dialogs = SettingsDialogs:new()
    plugin_instance.settings_dialogs:init(plugin_instance.settings, plugin_instance.api)

    plugin_instance.browser_launcher = BrowserLauncher:new()
    plugin_instance.browser_launcher:init(plugin_instance.settings, plugin_instance.api, download_dir)

    -- Initialize API with current settings if available
    if plugin_instance.settings.isConfigured() then
        plugin_instance.api:init(
            plugin_instance.settings.getServerAddress(), 
            plugin_instance.settings.getApiToken()
        )
    end

    logger.info("Miniflux plugin initialization complete")
    return true
end

---Initialize the download directory for entries
---@return string|nil Download directory path or nil if failed
function PluginInitializer:initializeDownloadDirectory()
    local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), self.download_dir_name)

    -- Create the directory if it doesn't exist
    if not lfs.attributes(download_dir, "mode") then
        logger.dbg("Miniflux: Creating download directory:", download_dir)
        local success = lfs.mkdir(download_dir)
        if not success then
            logger.err("Failed to create download directory:", download_dir)
            return nil
        end
    end

    return download_dir
end

return PluginInitializer 