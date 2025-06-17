--[[--
Miniflux Settings Module

Simplified settings management that directly accesses LuaSettings without OOP complexity.
Always gets/sets from the source of truth for maximum simplicity and reliability.

@module koplugin.miniflux.settings
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

-- Module-level variables
local settings_file
local settings_instance

-- Default values
local DEFAULTS = {
    server_address = "",
    api_token = "",
    limit = 100,
    order = "published_at",
    direction = "desc",
    hide_read_entries = true,
    auto_mark_read = false,
    include_images = true,
    entry_font_size = 14
}

-- Valid values for validation
local VALID_SORT_ORDERS = {
    "id", "status", "published_at", "category_title", "category_id"
}

local VALID_SORT_DIRECTIONS = {
    "asc", "desc"
}

---Initialize settings (loads or creates settings file)
---@return nil
local function init()
    if not settings_file then
        settings_file = DataStorage:getSettingsDir() .. "/miniflux.lua"
        settings_instance = LuaSettings:open(settings_file)
        
        -- Set defaults for any missing values
        for key, default_value in pairs(DEFAULTS) do
            if settings_instance:readSetting(key) == nil then
                settings_instance:saveSetting(key, default_value)
            end
        end
        
        settings_instance:flush()
        logger.info("Miniflux settings initialized:", settings_file)
    end
end

---Get a setting value with default fallback
---@param key string Setting key
---@param default any Default value
---@return any Setting value or default
local function get(key, default)
    init() -- Ensure initialized
    local value = settings_instance:readSetting(key)
    return value ~= nil and value or default
end

---Set a setting value
---@param key string Setting key
---@param value any Setting value
---@return nil
local function set(key, value)
    init() -- Ensure initialized
    settings_instance:saveSetting(key, value)
end

---Save settings to disk
---@return nil
local function save()
    if settings_instance then
        settings_instance:flush()
    end
end

---Validate if value is in allowed list
---@param value any Value to check
---@param allowed_values table List of allowed values
---@return boolean True if valid
local function isValidValue(value, allowed_values)
    for _, allowed in ipairs(allowed_values) do
        if value == allowed then
            return true
        end
    end
    return false
end

-- =============================================================================
-- PUBLIC API - Settings functions
-- =============================================================================

local Settings = {}

-- Server Settings
function Settings.getServerAddress()
    return get("server_address", DEFAULTS.server_address)
end

function Settings.setServerAddress(address)
    if type(address) == "string" then
        set("server_address", address)
    else
        logger.warn("Invalid server address type:", type(address))
    end
end

function Settings.getApiToken()
    return get("api_token", DEFAULTS.api_token)
end

function Settings.setApiToken(token)
    if type(token) == "string" then
        set("api_token", token)
    else
        logger.warn("Invalid API token type:", type(token))
    end
end

function Settings.isConfigured()
    return Settings.getServerAddress() ~= "" and Settings.getApiToken() ~= ""
end

-- Sorting Settings
function Settings.getLimit()
    return get("limit", DEFAULTS.limit)
end

function Settings.setLimit(limit)
    -- Convert string to number if needed
    if type(limit) == "string" then
        limit = tonumber(limit)
    end
    
    if type(limit) == "number" and limit > 0 and limit <= 1000 then
        set("limit", limit)
    else
        logger.warn("Invalid limit value:", limit, "- using default:", DEFAULTS.limit)
        set("limit", DEFAULTS.limit)
    end
end

function Settings.getOrder()
    return get("order", DEFAULTS.order)
end

function Settings.setOrder(order)
    if isValidValue(order, VALID_SORT_ORDERS) then
        set("order", order)
    else
        logger.warn("Invalid sort order:", order, "- using default:", DEFAULTS.order)
        set("order", DEFAULTS.order)
    end
end

function Settings.getDirection()
    return get("direction", DEFAULTS.direction)
end

function Settings.setDirection(direction)
    if isValidValue(direction, VALID_SORT_DIRECTIONS) then
        set("direction", direction)
    else
        logger.warn("Invalid sort direction:", direction, "- using default:", DEFAULTS.direction)
        set("direction", DEFAULTS.direction)
    end
end

-- Display Settings
function Settings.getHideReadEntries()
    return get("hide_read_entries", DEFAULTS.hide_read_entries)
end

function Settings.setHideReadEntries(hide)
    if type(hide) == "boolean" then
        set("hide_read_entries", hide)
    else
        logger.warn("Invalid hide_read_entries type:", type(hide))
    end
end

function Settings.toggleHideReadEntries()
    local current = Settings.getHideReadEntries()
    local new_value = not current
    Settings.setHideReadEntries(new_value)
    return new_value
end

function Settings.getAutoMarkRead()
    return get("auto_mark_read", DEFAULTS.auto_mark_read)
end

function Settings.setAutoMarkRead(auto_mark)
    if type(auto_mark) == "boolean" then
        set("auto_mark_read", auto_mark)
    else
        logger.warn("Invalid auto_mark_read type:", type(auto_mark))
    end
end

function Settings.getIncludeImages()
    return get("include_images", DEFAULTS.include_images)
end

function Settings.setIncludeImages(include)
    if type(include) == "boolean" then
        set("include_images", include)
    else
        logger.warn("Invalid include_images type:", type(include))
    end
end

function Settings.toggleIncludeImages()
    local current = Settings.getIncludeImages()
    local new_value = not current
    Settings.setIncludeImages(new_value)
    return new_value
end

function Settings.getEntryFontSize()
    return get("entry_font_size", DEFAULTS.entry_font_size)
end

function Settings.setEntryFontSize(size)
    -- Convert string to number if needed
    if type(size) == "string" then
        size = tonumber(size)
    end
    
    if type(size) == "number" and size >= 8 and size <= 32 then
        set("entry_font_size", size)
    else
        logger.warn("Invalid font size:", size, "- using default:", DEFAULTS.entry_font_size)
        set("entry_font_size", DEFAULTS.entry_font_size)
    end
end

-- Utility Functions
function Settings.save()
    save()
end

function Settings.init()
    init()
end

function Settings.export()
    return {
        server_address = Settings.getServerAddress(),
        api_token = Settings.getApiToken(),
        limit = Settings.getLimit(),
        order = Settings.getOrder(),
        direction = Settings.getDirection(),
        hide_read_entries = Settings.getHideReadEntries(),
        auto_mark_read = Settings.getAutoMarkRead(),
        include_images = Settings.getIncludeImages(),
        entry_font_size = Settings.getEntryFontSize()
    }
end

function Settings.reset()
    logger.info("Resetting all Miniflux settings to defaults")
    if settings_instance then
        settings_instance:clear()
    end
    
    -- Reset module state
    settings_file = nil
    settings_instance = nil
    
    -- Reinitialize with defaults
    init()
end

-- Constants for external use
Settings.VALID_SORT_ORDERS = VALID_SORT_ORDERS
Settings.VALID_SORT_DIRECTIONS = VALID_SORT_DIRECTIONS
Settings.DEFAULTS = DEFAULTS

return Settings 