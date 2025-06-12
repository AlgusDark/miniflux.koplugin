--[[--
Server Settings Module

This module handles server connection settings like server address and API token.
It follows the single responsibility principle by focusing only on server configuration.

@module koplugin.miniflux.settings.server_settings
--]]--

local BaseSettings = require("settings/base_settings")
local Enums = require("settings/enums")

---@class ServerSettings : BaseSettings
---@field settings LuaSettings The injected settings storage instance
local ServerSettings = {}
setmetatable(ServerSettings, {__index = BaseSettings})

---Create a new server settings instance
---@param o? table Optional initialization table
---@return ServerSettings
function ServerSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Get server address setting
---@return string The server address
function ServerSettings:getServerAddress()
    return self:get("server_address", Enums.DEFAULTS.server_address)
end

---Set server address with validation
---@param address string The server address
---@return boolean True if successfully set
function ServerSettings:setServerAddress(address)
    -- Basic validation: should not be empty and should be a string
    local function isValidAddress(addr)
        return type(addr) == "string" and addr ~= ""
    end
    
    return self:setWithValidation(
        "server_address", 
        address, 
        isValidAddress, 
        Enums.DEFAULTS.server_address
    )
end

---Get API token setting
---@return string The API token
function ServerSettings:getApiToken()
    return self:get("api_token", Enums.DEFAULTS.api_token)
end

---Set API token with validation
---@param token string The API token
---@return boolean True if successfully set
function ServerSettings:setApiToken(token)
    -- Basic validation: should not be empty and should be a string
    local function isValidToken(tkn)
        return type(tkn) == "string" and tkn ~= ""
    end
    
    return self:setWithValidation(
        "api_token", 
        token, 
        isValidToken, 
        Enums.DEFAULTS.api_token
    )
end

---Check if server settings are configured
---@return boolean True if both server address and API token are set
function ServerSettings:isConfigured()
    local server = self:getServerAddress()
    local token = self:getApiToken()
    return server ~= "" and token ~= ""
end

---Get all server settings as a table
---@return table<string, string> Map of server settings
function ServerSettings:getAllServerSettings()
    return {
        server_address = self:getServerAddress(),
        api_token = self:getApiToken()
    }
end

---Set all server settings at once
---@param settings table<string, string> Map of server settings
---@return boolean True if all settings were set successfully
function ServerSettings:setAllServerSettings(settings)
    local success = true
    
    if settings.server_address then
        success = success and self:setServerAddress(settings.server_address)
    end
    
    if settings.api_token then
        success = success and self:setApiToken(settings.api_token)
    end
    
    return success
end

---Validate server URL format
---@param url string URL to validate
---@return boolean True if URL format is valid
function ServerSettings:isValidServerUrl(url)
    if type(url) ~= "string" or url == "" then
        return false
    end
    
    -- Basic URL validation: should start with http:// or https://
    return url:match("^https?://") ~= nil
end

---Normalize server URL (ensure it doesn't end with slash)
---@param url string URL to normalize
---@return string Normalized URL
function ServerSettings:normalizeServerUrl(url)
    if type(url) ~= "string" then
        return ""
    end
    
    -- Remove trailing slash if present
    if url:sub(-1) == "/" then
        return url:sub(1, -2)
    end
    
    return url
end

---Set server address with normalization
---@param address string The server address
---@return boolean True if successfully set
function ServerSettings:setNormalizedServerAddress(address)
    if not self:isValidServerUrl(address) then
        self.logger.warn("Invalid server URL format:", address)
        return false
    end
    
    local normalized = self:normalizeServerUrl(address)
    return self:setServerAddress(normalized)
end

return ServerSettings 