local EventListener = require('ui/widget/eventlistener')
local CacheAdapter = require('shared/cache/cache_adapter')
local logger = require('logger')

---Entries domain - handles all entry-related operations
---@class Entries : EventListener
---@field miniflux Miniflux Parent plugin reference
---@field cache CacheAdapter Cache adapter for entries data
local Entries = EventListener:extend({})

---Initialize entries domain
function Entries:init()
    local miniflux = self.miniflux
    self.cache = CacheAdapter:new(miniflux.settings)
    logger.dbg('[Miniflux:Entries] Initialized')
end

---Get unread entries (NOT cached - preserves current behavior)
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function Entries:getUnreadEntries(config)
    local options = {
        status = { 'unread' },
        order = self.miniflux.settings.order,
        direction = self.miniflux.settings.direction,
        limit = self.miniflux.settings.limit,
    }

    local result, err = self.miniflux.api:getEntries(options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get unread count (cached - critical for main menu performance)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function Entries:getUnreadCount(config)
    -- Use URL-based cache key for consistency
    local options = {
        order = self.miniflux.settings.order,
        direction = self.miniflux.settings.direction,
        limit = 1,
        status = { 'unread' },
    }
    local cache_key = self.miniflux.api:buildEntriesUrl(options) .. '_count'

    return self.cache:fetchWithCache(cache_key, function()
        local result, err = self.miniflux.api:getEntries(options, config)
        if err then
            return nil, err
        end
        ---@cast result -nil
        return result.total or 0, nil
    end)
end

---Update entry status for one or multiple entries
---@param entry_ids number|number[] Entry ID or array of entry IDs to update
---@param config? table Configuration with body containing status and dialogs
---@return table|nil result, Error|nil error
function Entries:updateEntries(entry_ids, config)
    return self.miniflux.api:updateEntries(entry_ids, config)
end

---Get entries with optional filtering
---@param options? ApiOptions Query options for filtering and sorting
---@param config? table Configuration including optional dialogs
---@return MinifluxEntriesResponse|nil result, Error|nil error
function Entries:getEntries(options, config)
    return self.miniflux.api:getEntries(options, config)
end

---Test connection to Miniflux server (useful for settings)
-- TODO: Move this to a dedicated system/health domain - this doesn't belong in entries
-- Other endpoints like /version, /readiness might also need a home outside domain boundaries
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function Entries:testConnection(config)
    return self.miniflux.api:getMe(config)
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

---@private
function Entries:shouldInvalidateCache(key)
    local invalidating_keys = {
        [self.miniflux.settings.Key.ORDER] = true,
        [self.miniflux.settings.Key.DIRECTION] = true,
        [self.miniflux.settings.Key.LIMIT] = true,
        [self.miniflux.settings.Key.HIDE_READ_ENTRIES] = true,
    }
    return invalidating_keys[key] == true
end

function Entries:onMinifluxSettingsChanged(payload)
    local key = payload.key

    if self:shouldInvalidateCache(key) then
        logger.info('[Miniflux:Entries] Invalidating cache due to setting change:', key)
        self.cache:clear()
    end
end

function Entries:onMinifluxCacheInvalidate()
    logger.info('[Miniflux:Entries] Cache invalidation event received')
    self.cache:clear()
end

return Entries
