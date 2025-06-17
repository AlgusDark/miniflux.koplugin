--[[--
Miniflux Settings Module

Object-oriented settings management that provides a clean API for configuration persistence.
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
-- SETTINGS CLASS
-- =============================================================================

---@class MinifluxSettings
---@field settings_file string Path to settings file
---@field settings_instance LuaSettings LuaSettings instance
---@field initialized boolean Whether settings have been initialized
---@field cache table In-memory cache of settings values
local MinifluxSettings = {}

---Create a new settings instance
---@param o? table Optional initialization table
---@return MinifluxSettings
function MinifluxSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    -- Initialize instance variables
    o.settings_file = nil
    o.settings_instance = nil
    o.initialized = false
    o.cache = {}  -- In-memory cache for settings
    
    -- Auto-initialize (safe due to guard in init() method)
    o:init()
    
    return o
end

---Initialize settings (loads or creates settings file)
---@return MinifluxSettings self for method chaining
function MinifluxSettings:init()
    if not self.initialized then
        self.settings_file = DataStorage:getSettingsDir() .. "/miniflux.lua"
        self.settings_instance = LuaSettings:open(self.settings_file)
        
        -- Load all settings into cache
        self:loadSettingsIntoCache()
        
        -- Set defaults for any missing values
        local needs_flush = false
        for key, default_value in pairs(DEFAULTS) do
            if self.cache[key] == nil then
                self.cache[key] = default_value
                self.settings_instance:saveSetting(key, default_value)
                needs_flush = true
            end
        end
        
        if needs_flush then
            self.settings_instance:flush()
        end
        
        self.initialized = true
        logger.info("Miniflux settings initialized with cache:", self.settings_file)
    end
    
    return self
end

---Load all settings from disk into memory cache
---@return nil
function MinifluxSettings:loadSettingsIntoCache()
    self.cache = {}
    for key, _ in pairs(DEFAULTS) do
        local value = self.settings_instance:readSetting(key)
        if value ~= nil then
            self.cache[key] = value
        end
    end
    local count = 0
    for _ in pairs(self.cache) do count = count + 1 end
    logger.dbg("Loaded", count, "settings into cache")
end

---Get a setting value from cache with default fallback
---@param key string Setting key
---@param default any Default value
---@return any Setting value or default
function MinifluxSettings:get(key, default)
    local value = self.cache[key]
    if value ~= nil then
        return value
    else
        return default
    end
end

---Set a setting value in cache and persist to disk
---@param key string Setting key
---@param value any Setting value
---@return nil
function MinifluxSettings:set(key, value)
    self.cache[key] = value
    self.settings_instance:saveSetting(key, value)
end

---Save all cached settings to disk (explicit flush)
---@return nil
function MinifluxSettings:save()
    if self.settings_instance then
        self.settings_instance:flush()
    end
end



---Validate if value is in allowed list
---@param value any Value to check
---@param allowed_values table List of allowed values
---@return boolean True if valid
function MinifluxSettings:isValidValue(value, allowed_values)
    for _, allowed in ipairs(allowed_values) do
        if value == allowed then
            return true
        end
    end
    return false
end

-- =============================================================================
-- SERVER SETTINGS
-- =============================================================================

function MinifluxSettings:getServerAddress()
    return self:get("server_address", DEFAULTS.server_address)
end

function MinifluxSettings:setServerAddress(address)
    if type(address) == "string" then
        self:set("server_address", address)
    else
        logger.warn("Invalid server address type:", type(address))
    end
end

function MinifluxSettings:getApiToken()
    return self:get("api_token", DEFAULTS.api_token)
end

function MinifluxSettings:setApiToken(token)
    if type(token) == "string" then
        self:set("api_token", token)
    else
        logger.warn("Invalid API token type:", type(token))
    end
end

function MinifluxSettings:isConfigured()
    return self:getServerAddress() ~= "" and self:getApiToken() ~= ""
end

-- =============================================================================
-- SORTING SETTINGS
-- =============================================================================

function MinifluxSettings:getLimit()
    return self:get("limit", DEFAULTS.limit)
end

function MinifluxSettings:setLimit(limit)
    -- Convert string to number if needed
    if type(limit) == "string" then
        limit = tonumber(limit)
    end
    
    if type(limit) == "number" and limit > 0 and limit <= 1000 then
        self:set("limit", limit)
    else
        logger.warn("Invalid limit value:", limit, "- using default:", DEFAULTS.limit)
        self:set("limit", DEFAULTS.limit)
    end
end

function MinifluxSettings:getOrder()
    return self:get("order", DEFAULTS.order)
end

function MinifluxSettings:setOrder(order)
    if self:isValidValue(order, VALID_SORT_ORDERS) then
        self:set("order", order)
    else
        logger.warn("Invalid sort order:", order, "- using default:", DEFAULTS.order)
        self:set("order", DEFAULTS.order)
    end
end

function MinifluxSettings:getDirection()
    return self:get("direction", DEFAULTS.direction)
end

function MinifluxSettings:setDirection(direction)
    if self:isValidValue(direction, VALID_SORT_DIRECTIONS) then
        self:set("direction", direction)
    else
        logger.warn("Invalid sort direction:", direction, "- using default:", DEFAULTS.direction)
        self:set("direction", DEFAULTS.direction)
    end
end

-- =============================================================================
-- DISPLAY SETTINGS
-- =============================================================================

function MinifluxSettings:getHideReadEntries()
    return self:get("hide_read_entries", DEFAULTS.hide_read_entries)
end

function MinifluxSettings:setHideReadEntries(hide)
    if type(hide) == "boolean" then
        self:set("hide_read_entries", hide)
    else
        logger.warn("Invalid hide_read_entries type:", type(hide))
    end
end

function MinifluxSettings:toggleHideReadEntries()
    local current = self:getHideReadEntries()
    local new_value = not current
    self:setHideReadEntries(new_value)
    return new_value
end

function MinifluxSettings:getIncludeImages()
    return self:get("include_images", DEFAULTS.include_images)
end

function MinifluxSettings:setIncludeImages(include)
    if type(include) == "boolean" then
        self:set("include_images", include)
    else
        logger.warn("Invalid include_images type:", type(include))
    end
end

function MinifluxSettings:toggleIncludeImages()
    local current = self:getIncludeImages()
    local new_value = not current
    self:setIncludeImages(new_value)
    return new_value
end

-- Export only the class - no functional API or constants needed
local Settings = {}
Settings.MinifluxSettings = MinifluxSettings

return Settings 