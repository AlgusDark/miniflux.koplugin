--[[--
Debug Settings Module

This module handles debug and logging configuration settings.
It follows the single responsibility principle by focusing only on debug options.

@module koplugin.miniflux.settings.debug_settings
--]]--

local BaseSettings = require("settings/base_settings")
local Enums = require("settings/enums")

---@class DebugSettings : BaseSettings
---@field settings LuaSettings The injected settings storage instance
local DebugSettings = {}
setmetatable(DebugSettings, {__index = BaseSettings})

---Create a new debug settings instance
---@param o? table Optional initialization table
---@return DebugSettings
function DebugSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Get debug logging setting
---@return boolean Whether debug logging is enabled
function DebugSettings:getDebugLogging()
    return self:get("debug_logging", Enums.DEFAULTS.debug_logging)
end

---Set debug logging setting
---@param debug boolean Whether to enable debug logging
---@return boolean True if successfully set
function DebugSettings:setDebugLogging(debug)
    local function isValidBoolean(val)
        return type(val) == "boolean"
    end
    
    return self:setWithValidation(
        "debug_logging", 
        debug, 
        isValidBoolean, 
        Enums.DEFAULTS.debug_logging
    )
end

---Toggle debug logging setting
---@return boolean The new value after toggle
function DebugSettings:toggleDebugLogging()
    return self:toggle("debug_logging", Enums.DEFAULTS.debug_logging)
end

---Enable debug logging
---@return boolean True if successfully enabled
function DebugSettings:enableDebugLogging()
    return self:setDebugLogging(true)
end

---Disable debug logging
---@return boolean True if successfully disabled
function DebugSettings:disableDebugLogging()
    return self:setDebugLogging(false)
end

---Check if debug logging is enabled
---@return boolean True if debug logging is enabled
function DebugSettings:isDebugEnabled()
    return self:getDebugLogging()
end

---Get all debug settings as a table
---@return table<string, boolean> Map of debug settings
function DebugSettings:getAllDebugSettings()
    return {
        debug_logging = self:getDebugLogging()
    }
end

---Set all debug settings at once
---@param settings table<string, boolean> Map of debug settings
---@return boolean True if all settings were set successfully
function DebugSettings:setAllDebugSettings(settings)
    local success = true
    
    if settings.debug_logging ~= nil then
        success = success and self:setDebugLogging(settings.debug_logging)
    end
    
    return success
end

---Reset debug settings to defaults
---@return boolean True if successfully reset
function DebugSettings:resetToDefaults()
    return self:setDebugLogging(Enums.DEFAULTS.debug_logging)
end

return DebugSettings 