--[[--
Base Settings Class

This module provides the base class for all settings modules with dependency injection
and common functionality.

@module koplugin.miniflux.settings.base_settings
--]]--

local logger = require("logger")

---@class BaseSettings
---@field settings LuaSettings The injected settings storage instance
---@field logger any Logger instance for debugging
local BaseSettings = {}

---Create a new base settings instance
---@param o? table Optional initialization table
---@return BaseSettings
function BaseSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the base settings with dependency injection
---@param settings LuaSettings The settings storage instance
---@param logger? any Optional logger instance
---@return nil
function BaseSettings:init(settings, logger)
    self.settings = settings
    self.logger = logger or require("logger")
end

---Get a setting value with fallback to default
---@param key string The setting key
---@param default any Default value if setting doesn't exist
---@return any The setting value or default
function BaseSettings:get(key, default)
    if not self.settings then
        self.logger.warn("Settings not initialized for key:", key)
        return default
    end
    
    local value = self.settings:readSetting(key)
    if value == nil then
        return default
    end
    return value
end

---Set a setting value
---@param key string The setting key
---@param value any The value to set
---@return boolean True if successfully set
function BaseSettings:set(key, value)
    if not self.settings then
        self.logger.warn("Settings not initialized, cannot set key:", key)
        return false
    end
    
    self.settings:saveSetting(key, value)
    return true
end

---Toggle a boolean setting
---@param key string The setting key
---@param default? boolean Default value if setting doesn't exist
---@return boolean The new value after toggle
function BaseSettings:toggle(key, default)
    default = default or false
    local current_value = self:get(key, default)
    local new_value = not current_value
    self:set(key, new_value)
    return new_value
end

---Validate and set a setting with validation function
---@param key string The setting key
---@param value any The value to set
---@param validator function Function that returns true if value is valid
---@param default any Default value to use if validation fails
---@return boolean True if successfully set
function BaseSettings:setWithValidation(key, value, validator, default)
    if validator(value) then
        return self:set(key, value)
    else
        self.logger.warn("Invalid value for setting", key, ":", value, "- using default:", default)
        return self:set(key, default)
    end
end

---Get multiple settings at once
---@param keys string[] Array of setting keys
---@param defaults table<string, any> Default values for each key
---@return table<string, any> Map of key to value
function BaseSettings:getMultiple(keys, defaults)
    local result = {}
    defaults = defaults or {}
    
    for _, key in ipairs(keys) do
        result[key] = self:get(key, defaults[key])
    end
    
    return result
end

---Set multiple settings at once
---@param values table<string, any> Map of key to value
---@return boolean True if all settings were set successfully
function BaseSettings:setMultiple(values)
    local success = true
    
    for key, value in pairs(values) do
        if not self:set(key, value) then
            success = false
        end
    end
    
    return success
end

---Check if a setting exists
---@param key string The setting key
---@return boolean True if setting exists
function BaseSettings:exists(key)
    if not self.settings then
        return false
    end
    
    return self.settings:readSetting(key) ~= nil
end

return BaseSettings 