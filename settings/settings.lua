--[[--
Miniflux Settings Module

Singleton settings management that provides a clean API for configuration persistence.
Uses LuaSettings for storage with proper initialization and state management.

@module koplugin.miniflux.settings
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

-- Default values
local DEFAULTS = {
    server_address = "",
    api_token = "",
    limit = 100,
    order = "published_at",
    direction = "desc",
    hide_read_entries = true,
    include_images = true
}

-- Valid values for validation
local VALID_SORT_ORDERS = {
    "id", "status", "published_at", "category_title", "category_id"
}

local VALID_SORT_DIRECTIONS = {
    "asc", "desc"
}

-- =============================================================================
-- SINGLETON SETTINGS CLASS
-- =============================================================================

---@class MinifluxSettings
---@field settings LuaSettings LuaSettings instance
local MinifluxSettings = {}
MinifluxSettings.__index = MinifluxSettings

-- Singleton instance storage
local _instance = nil

---Create a new MinifluxSettings instance
---@return MinifluxSettings
local function new(o)
    local self = setmetatable({
        settings = nil
    }, MinifluxSettings)

    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/miniflux.lua")

    return self
end

---Get or create the singleton settings instance
---@return MinifluxSettings
function MinifluxSettings:getInstance()
    if not _instance then
        _instance = new()
    end
    
    return _instance
end

---Reads a setting, optionally initializing it to a default.
---@param key string Setting key
---@param default any Default value
---@return any Setting value or default
function MinifluxSettings:get(key, default)
    return self.settings:readSetting(key, default)
end

---Saves a setting.
---@param key string Setting key
---@param value any Setting value
---@return nil
function MinifluxSettings:set(key, value)
    self.settings:saveSetting(key, value)
end

---Writes settings to disk.
---@return nil
function MinifluxSettings:save()
    self.settings:flush()
end

-- =============================================================================
-- SERVER SETTINGS
-- =============================================================================

---Get the configured server address
---@return string Server address
function MinifluxSettings:getServerAddress()
    return self:get("server_address", DEFAULTS.server_address)
end

---Set the server address
---@param address string Server address URL
function MinifluxSettings:setServerAddress(address)
    self:set("server_address", address)
end

---Get the configured API token
---@return string API token
function MinifluxSettings:getApiToken()
    return self:get("api_token", DEFAULTS.api_token)
end

---Set the API token
---@param token string API authentication token
function MinifluxSettings:setApiToken(token)
    self:set("api_token", token)
end

---Get the configured entries limit
---@return number Maximum number of entries to fetch
function MinifluxSettings:getLimit()
    return self:get("limit", DEFAULTS.limit)
end

---Set the entries limit
---@param limit number|string Maximum number of entries to fetch (1-1000)
function MinifluxSettings:setLimit(limit)
    self:set("limit", limit)
end

---Get the configured sort order
---@return string Sort order field
function MinifluxSettings:getOrder()
    return self:get("order", DEFAULTS.order)
end

---Set the sort order
---@param order string Sort order field ("id", "status", "published_at", "category_title", "category_id")
function MinifluxSettings:setOrder(order)
    self:set("order", order)
end

---Get the configured sort direction
---@return string Sort direction ("asc" or "desc")
function MinifluxSettings:getDirection()
    return self:get("direction", DEFAULTS.direction)
end

---Set the sort direction
---@param direction string Sort direction ("asc" or "desc")
function MinifluxSettings:setDirection(direction)
    self:set("direction", direction)
end

---Get the hide read entries setting
---@return boolean True if read entries should be hidden
function MinifluxSettings:getHideReadEntries()
    return self:get("hide_read_entries", DEFAULTS.hide_read_entries)
end

---Toggle the hide read entries setting
---@return boolean New value after toggle
function MinifluxSettings:toggleHideReadEntries()
    return self.settings:toggle("hide_read_entries"):readSetting("hide_read_entries")
end

---Get the include images setting
---@return boolean True if images should be downloaded with entries
function MinifluxSettings:getIncludeImages()
    return self:get("include_images", DEFAULTS.include_images)
end

---Set the include images setting
---@param include boolean Whether to download images with entries
function MinifluxSettings:setIncludeImages(include)
    self:set("include_images", include)
end

return MinifluxSettings 