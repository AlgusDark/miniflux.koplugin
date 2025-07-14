local CachedRepository = require('repositories/cached_repository')

-- **Entry Repository** - Data Access Layer
--
-- Handles all entry-related data access and API interactions.
-- Provides a clean interface for entry data without UI concerns.
--
-- CACHING STRATEGY FOR E-INK DEVICES:
-- ✓ Entry counts (small numbers) - cached with URL-based keys for fast UI updates
-- ✗ Entry arrays (1.5-3MB) - NOT cached due to CacheSQLite limitations:
--     - Large objects cause "attempt to perform arithmetic on local 'size'" errors
--     - Entry data changes frequently, reducing cache effectiveness
--     - Memory pressure on e-ink devices with limited RAM
--     - Fresh API calls ensure data consistency and reduce memory usage
---@class EntryRepository
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field settings MinifluxSettings Settings instance
---@field cache CachedRepository Cache instance for count operations only
local EntryRepository = {}

---Create a new EntryRepository instance
---@param deps {miniflux_api: MinifluxAPI, settings: MinifluxSettings} Dependencies table
---@return EntryRepository
function EntryRepository:new(deps)
    local obj = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
        -- Only used for caching entry counts, not entry arrays
        cache = CachedRepository:new({
            settings = deps.settings,
            cache_prefix = 'miniflux_entries',
        }),
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- API OPTIONS BUILDING
-- =============================================================================

---Build API options based on current settings
---@return table options API options for entry queries
function EntryRepository:getApiOptions()
    local options = {
        limit = self.settings.limit,
        order = self.settings.order,
        direction = self.settings.direction,
    }

    -- Server-side filtering based on settings
    local hide_read_entries = self.settings.hide_read_entries
    if hide_read_entries then
        options.status = { 'unread' }
    else
        options.status = { 'unread', 'read' }
    end

    return options
end

---Get unread entries (no caching - see class documentation for reasoning)
---@param config? table Configuration with optional dialogs
---@return MinifluxEntry[]|nil result, Error|nil error
function EntryRepository:getUnread(config)
    local options = {
        status = { 'unread' }, -- Always unread only for this view
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
    }

    -- Direct API call - entry arrays are not cached (see class documentation)
    local result, err = self.miniflux_api:getEntries(options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get entries for a specific feed (no caching - see class documentation for reasoning)
---@param feed_id number The feed ID
---@param config? table Configuration with optional dialogs
---@return MinifluxEntry[]|nil result, Error|nil error
function EntryRepository:getByFeed(feed_id, config)
    local options = self:getApiOptions()
    options.feed_id = feed_id

    -- Direct API call - entry arrays are not cached (see class documentation)
    local result, err = self.miniflux_api:getFeedEntries(feed_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get entries for a specific category (no caching - see class documentation for reasoning)
---@param category_id number The category ID
---@param config? table Configuration with optional dialogs
---@return MinifluxEntry[]|nil result, Error|nil error
function EntryRepository:getByCategory(category_id, config)
    local options = self:getApiOptions()
    options.category_id = category_id

    -- Direct API call - entry arrays are not cached (see class documentation)
    local result, err = self.miniflux_api:getCategoryEntries(category_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get unread count with URL-based caching (small numbers cache well)
---@param config? table Configuration with optional dialogs
---@return number|nil result, Error|nil error
function EntryRepository:getUnreadCount(config)
    local options = {
        order = self.settings.order,
        direction = self.settings.direction,
        limit = 1, -- We only need one entry to get the total count
        status = { 'unread' }, -- Only unread for count
    }

    -- Build cache key from full API URL for consistency
    local cache_key = self.miniflux_api:buildEntriesUrl(options) .. '_count'

    -- Check cache first (counts are small and cache reliably)
    local cached_response, is_valid = self.cache.cache_store:get(cache_key, { ttl = 300 })
    if is_valid then
        return cached_response, nil
    end

    -- Cache miss - make API call
    local result, err = self.miniflux_api:getEntries(options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    local count = (result and result.total) and result.total or 0

    -- Cache the count (small numbers cache reliably)
    self.cache.cache_store:set(cache_key, { data = count, ttl = 300 })

    return count, nil
end

return EntryRepository
