local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

-- Default values
local DEFAULTS = {
    server_address = "",
    api_token = "",
    limit = 100,
    order = "published_at",
    direction = "desc",
    hide_read_entries = true,
    include_images = true,
    mark_as_read_on_open = true,
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
local MinifluxSettings = {}

---Create a new MinifluxSettings instance
---@return MinifluxSettings
function MinifluxSettings:new()
    local instance = {
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/miniflux.lua"),
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
---@param key string Property name
---@param value any Property value
function MinifluxSettings:__newindex(key, value)
    -- Handle settings
    if DEFAULTS[key] ~= nil then
        self.settings:saveSetting(key, value)
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
