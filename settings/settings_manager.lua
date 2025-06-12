--[[--
Settings Manager

This is the main settings coordinator that manages all settings modules using
dependency injection. It provides a unified interface while delegating to
specialized modules for different setting categories.

@module koplugin.miniflux.settings.settings_manager
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

-- Import setting modules
local Enums = require("settings/enums")
local ServerSettings = require("settings/server_settings")
local SortingSettings = require("settings/sorting_settings")
local DisplaySettings = require("settings/display_settings")

---@class SettingsManager
---@field settings_file string Path to the settings file
---@field settings LuaSettings The settings storage instance
---@field server ServerSettings Server settings module
---@field sorting SortingSettings Sorting settings module
---@field display DisplaySettings Display settings module
local SettingsManager = {}

---Initialize the settings manager and all sub-modules
---@return nil
function SettingsManager:init()
    -- Initialize settings storage
    self.settings_file = DataStorage:getSettingsDir() .. "/miniflux.lua"
    self.settings = LuaSettings:open(self.settings_file)
    
    -- Load defaults for any missing settings
    self:loadDefaults()
    
    -- Initialize sub-modules with dependency injection
    self.server = ServerSettings:new()
    self.server:init(self.settings, logger)
    
    self.sorting = SortingSettings:new()
    self.sorting:init(self.settings, logger)
    
    self.display = DisplaySettings:new()
    self.display:init(self.settings, logger)
    
    logger.info("Settings manager initialized with all modules")
end

---Load default values for missing settings
---@return nil
function SettingsManager:loadDefaults()
    -- Set defaults only if values don't exist
    for key, default_value in pairs(Enums.DEFAULTS) do
        if self.settings:readSetting(key) == nil then
            self.settings:saveSetting(key, default_value)
            logger.info("Setting default for", key, ":", default_value)
        end
    end
    
    self:save()
end

---Save all settings to disk
---@return nil
function SettingsManager:save()
    self.settings:flush()
    logger.info("Settings saved to:", self.settings_file)
end

-- =============================================================================
-- SERVER SETTINGS - Delegate to ServerSettings module
-- =============================================================================

---Get server address setting
---@return string The server address
function SettingsManager:getServerAddress()
    return self.server:getServerAddress()
end

---Set server address
---@param address string The server address
---@return nil
function SettingsManager:setServerAddress(address)
    self.server:setServerAddress(address)
end

---Get API token setting
---@return string The API token
function SettingsManager:getApiToken()
    return self.server:getApiToken()
end

---Set API token
---@param token string The API token
---@return nil
function SettingsManager:setApiToken(token)
    self.server:setApiToken(token)
end

---Check if server settings are configured
---@return boolean True if server address and API token are set
function SettingsManager:isConfigured()
    return self.server:isConfigured()
end

-- =============================================================================
-- SORTING SETTINGS - Delegate to SortingSettings module
-- =============================================================================

---Get entries limit setting
---@return number The entries limit
function SettingsManager:getLimit()
    return self.sorting:getLimit()
end

---Set entries limit
---@param limit number The entries limit
---@return nil
function SettingsManager:setLimit(limit)
    self.sorting:setLimit(limit)
end

---Get sort order setting
---@return string The sort order
function SettingsManager:getOrder()
    return self.sorting:getOrder()
end

---Set sort order
---@param order string The sort order
---@return nil
function SettingsManager:setOrder(order)
    self.sorting:setOrder(order)
end

---Get sort direction setting
---@return string The sort direction
function SettingsManager:getDirection()
    return self.sorting:getDirection()
end

---Set sort direction
---@param direction string The sort direction
---@return nil
function SettingsManager:setDirection(direction)
    self.sorting:setDirection(direction)
end

-- =============================================================================
-- DISPLAY SETTINGS - Delegate to DisplaySettings module
-- =============================================================================

---Get hide read entries setting
---@return boolean Whether to hide read entries
function SettingsManager:getHideReadEntries()
    return self.display:getHideReadEntries()
end

---Set hide read entries setting
---@param hide boolean Whether to hide read entries
---@return nil
function SettingsManager:setHideReadEntries(hide)
    self.display:setHideReadEntries(hide)
end

---Toggle hide read entries setting
---@return boolean The new value after toggle
function SettingsManager:toggleHideReadEntries()
    return self.display:toggleHideReadEntries()
end

---Get auto mark read setting
---@return boolean Whether to auto mark entries as read
function SettingsManager:getAutoMarkRead()
    return self.display:getAutoMarkRead()
end

---Set auto mark read setting
---@param auto_mark boolean Whether to auto mark entries as read
---@return nil
function SettingsManager:setAutoMarkRead(auto_mark)
    self.display:setAutoMarkRead(auto_mark)
end

---Get include images setting
---@return boolean Whether to include images when downloading
function SettingsManager:getIncludeImages()
    return self.display:getIncludeImages()
end

---Set include images setting
---@param include boolean Whether to include images when downloading
---@return nil
function SettingsManager:setIncludeImages(include)
    self.display:setIncludeImages(include)
end

---Toggle include images setting
---@return boolean The new value after toggle
function SettingsManager:toggleIncludeImages()
    return self.display:toggleIncludeImages()
end

-- =============================================================================
-- ADVANCED OPERATIONS
-- =============================================================================

---Export all settings as a table
---@return table<string, any> Complete settings table
function SettingsManager:export()
    return {
        server_address = self:getServerAddress(),
        api_token = self:getApiToken(),
        limit = self:getLimit(),
        order = self:getOrder(),
        direction = self:getDirection(),
        hide_read_entries = self:getHideReadEntries(),
        auto_mark_read = self:getAutoMarkRead(),
        include_images = self:getIncludeImages()
    }
end

---Reset all settings to defaults
---@return nil
function SettingsManager:reset()
    logger.info("Resetting all Miniflux settings to defaults")
    self.settings:clear()
    self:loadDefaults()
    
    -- Reinitialize all modules with fresh settings
    self.server:init(self.settings, logger)
    self.sorting:init(self.settings, logger)
    self.display:init(self.settings, logger)
end

---Get settings for a specific module
---@param module_name string Module name (server, sorting, display)
---@return table<string, any>|nil Settings for the module or nil if module not found
function SettingsManager:getModuleSettings(module_name)
    if module_name == "server" then
        return self.server:getAllServerSettings()
    elseif module_name == "sorting" then
        return self.sorting:getAllSortingSettings()
    elseif module_name == "display" then
        return self.display:getAllDisplaySettings()
    else
        logger.warn("Unknown module name:", module_name)
        return nil
    end
end

---Set settings for a specific module
---@param module_name string Module name (server, sorting, display)
---@param settings table<string, any> Settings to apply
---@return boolean True if successfully applied
function SettingsManager:setModuleSettings(module_name, settings)
    if module_name == "server" then
        return self.server:setAllServerSettings(settings)
    elseif module_name == "sorting" then
        return self.sorting:setAllSortingSettings(settings)
    elseif module_name == "display" then
        return self.display:setAllDisplaySettings(settings)
    else
        logger.warn("Unknown module name:", module_name)
        return false
    end
end

return SettingsManager