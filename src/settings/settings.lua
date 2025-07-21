local DataStorage = require('datastorage')
local LuaSettings = require('luasettings')

-- Default values
local DEFAULTS = {
    server_address = '',
    api_token = '',
    limit = 100,
    order = 'published_at',
    direction = 'desc',
    hide_read_entries = true,
    include_images = true,
    mark_as_read_on_open = true,

    -- API Cache settings
    api_cache_ttl = 300, -- 5 minutes in seconds (default for feeds, counts)
    api_cache_ttl_counters = 60, -- 1 minute for counters (more volatile)
    api_cache_ttl_categories = 120, -- 2 minutes for categories (intermediate)

    -- Proxy Image Downloader settings
    proxy_image_downloader_enabled = false,
    proxy_image_downloader_url = '',
    proxy_image_downloader_token = '',

    -- Auto-Update settings
    auto_update_enabled = true,
    auto_update_check_frequency = 'weekly', -- 'daily', 'weekly', 'monthly', 'manual'
    auto_update_include_beta = false,
    auto_update_last_check = 0, -- timestamp of last check
}

-- **Miniflux Settings** - Settings management with idiomatic property access
-- using metamethods. Uses LuaSettings for storage with proper initialization
-- and state management.
---@class MinifluxSettings
---@field settings LuaSettings LuaSettings instance
---@field server_address string Server address
---@field api_token string API token
---@field limit number Entries limit (1-1000)
---@field order "id"|"status"|"published_at"|"category_title"|"category_id" Sort order
---@field direction "asc"|"desc" Sort direction
---@field hide_read_entries boolean Whether to hide read entries
---@field include_images boolean Whether to include images
---@field mark_as_read_on_open boolean Whether to automatically mark entries as read when opened
---@field api_cache_ttl number API cache TTL in seconds
---@field api_cache_ttl_counters number API cache TTL for counters in seconds
---@field api_cache_ttl_categories number API cache TTL for categories in seconds
---@field proxy_image_downloader_enabled boolean Whether proxy image downloader is enabled
---@field proxy_image_downloader_url string Proxy URL for image downloads
---@field proxy_image_downloader_token string Proxy API token for authentication
---@field auto_update_enabled boolean Whether automatic update checking is enabled
---@field auto_update_check_frequency "daily"|"weekly"|"monthly"|"manual" How often to check for updates
---@field auto_update_include_beta boolean Whether to include beta releases in update checks
---@field auto_update_last_check number Timestamp of last update check
local MinifluxSettings = {}

---@enum MinifluxSettingsKeys
---| "server_address"
---| "api_token"
---| "limit"
---| "order"
---| "direction"
---| "hide_read_entries"
---| "include_images"
---| "mark_as_read_on_open"
MinifluxSettings.Key = {
    SERVER_ADDRESS = 'server_address',
    API_TOKEN = 'api_token',
    LIMIT = 'limit',
    ORDER = 'order',
    DIRECTION = 'direction',
    HIDE_READ_ENTRIES = 'hide_read_entries',
    INCLUDE_IMAGES = 'include_images',
    MARK_AS_READ_ON_OPEN = 'mark_as_read_on_open',
}

---Create a new MinifluxSettings instance
---@return MinifluxSettings
function MinifluxSettings:new()
    local instance = {
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. '/miniflux.lua'),
    }

    setmetatable(instance, self)
    return instance
end

---Handle property reading with automatic defaults
---@param key string Property name
---@return any Property value or default
function MinifluxSettings:__index(key)
    -- Handle method calls first
    if rawget(MinifluxSettings, key) then
        return rawget(MinifluxSettings, key)
    end

    -- Handle setting access
    local default = DEFAULTS[key]
    if default ~= nil then
        return self.settings:readSetting(key, default)
    end

    -- Fallback to nil for unknown keys
    return nil
end

---Handle property writing with auto-save
---@param key MinifluxSettingsKeys Property name
---@param value any Property value
function MinifluxSettings:__newindex(key, value)
    -- Handle settings
    if DEFAULTS[key] ~= nil then
        local old_value = self.settings:readSetting(key, DEFAULTS[key])
        self.settings:saveSetting(key, value)

        -- Broadcast settings change event
        local MinifluxEvent = require('utils/event')
        MinifluxEvent:broadcastMinifluxSettingsChange({
            key = key,
            old_value = old_value,
            new_value = value,
        })
    else
        -- For unknown keys, set them directly on the object
        rawset(self, key, value)
    end
end

---Explicitly save settings to disk
---@return nil
function MinifluxSettings:save()
    self.settings:flush()
end

return MinifluxSettings
