local CacheStore = require('utils/cache_store')
local EventListener = require('ui/widget/eventlistener')
local logger = require('logger')
local MinifluxSettings = require('settings/settings')

-- **Data Repository** - Unified data access layer with caching
--
-- Repository that combines data access and caching responsibilities.
-- Maintains all current functionality:
---@class DataRepository : EventListener
---@field miniflux_api MinifluxAPI Direct API access
---@field settings MinifluxSettings Settings for TTL and cache control
---@field cache CacheStore Shared cache store for all data types
local DataRepository = EventListener:extend({})

function DataRepository:init()
    logger.dbg('[Miniflux:DataRepository] Calling init')
    self.cache = CacheStore:new({
        default_ttl = self.settings.api_cache_ttl,
        db_name = 'miniflux_cache.sqlite',
    })
end

---Generic cache-or-fetch helper
---@param cache_key string Cache key to use
---@param ttl number Cache TTL in seconds
---@param fetch_fn function Function that returns result, error
---@return any|nil result, Error|nil error
function DataRepository:fetchWithCache(cache_key, ttl, fetch_fn)
    local cached_data, is_valid = self.cache:get(cache_key, { ttl = ttl })

    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - fetch from API
    local result, err = fetch_fn()

    -- Cache result (even errors to avoid repeated failures)
    self.cache:set(cache_key, {
        data = { result = result, error = err },
        ttl = ttl,
    })

    return result, err
end

-- =============================================================================
-- FEED OPERATIONS
-- =============================================================================

---Get all feeds (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function DataRepository:getFeeds(config)
    return self:fetchWithCache('feeds', self.settings.api_cache_ttl, function()
        return self.miniflux_api:getFeeds(config)
    end)
end

---Get feeds with counters (cached separately with shorter TTL)
---@param config? table Optional configuration with dialogs
---@return {feeds: MinifluxFeed[], counters: MinifluxFeedCounters}|nil result, Error|nil error
function DataRepository:getFeedsWithCounters(config)
    return self:fetchWithCache(
        'feeds_with_counters',
        self.settings.api_cache_ttl_counters,
        function()
            local feeds, err = self:getFeeds(config)
            if err then
                return nil, err
            end

            local counters, counters_err = self.miniflux_api:getFeedCounters()
            if counters_err then
                counters = { reads = {}, unreads = {} }
            end

            return { feeds = feeds, counters = counters }, nil
        end
    )
end

---Get feed count (uses cached feeds)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function DataRepository:getFeedCount(config)
    local feeds, err = self:getFeeds(config)
    if err then
        return nil, err
    end
    return #feeds, nil
end

-- =============================================================================
-- CATEGORY OPERATIONS
-- =============================================================================

---Get all categories with counts (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function DataRepository:getCategories(config)
    return self:fetchWithCache('categories', self.settings.api_cache_ttl_categories, function()
        return self.miniflux_api:getCategories(true, config) -- include counts
    end)
end

---Get category count (uses cached categories)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function DataRepository:getCategoryCount(config)
    local categories, err = self:getCategories(config)
    if err then
        return nil, err
    end
    return #categories, nil
end

-- =============================================================================
-- ENTRY OPERATIONS
-- =============================================================================

---Get unread entries (NOT cached - preserves current behavior)
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function DataRepository:getUnreadEntries(config)
    local options = {
        status = { 'unread' },
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
    }

    local result, err = self.miniflux_api:getEntries(options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get entries by feed (NOT cached - preserves current behavior)
---@param feed_id number Feed ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function DataRepository:getEntriesByFeed(feed_id, config)
    local options = {
        feed_id = feed_id,
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
        status = self.settings.hide_read_entries and { 'unread' } or { 'unread', 'read' },
    }

    local result, err = self.miniflux_api:getFeedEntries(feed_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get entries by category (NOT cached - preserves current behavior)
---@param category_id number Category ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function DataRepository:getEntriesByCategory(category_id, config)
    local options = {
        category_id = category_id,
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
        status = self.settings.hide_read_entries and { 'unread' } or { 'unread', 'read' },
    }

    local result, err = self.miniflux_api:getCategoryEntries(category_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Get all collections counts for main view in a single call
---@param config? table Optional configuration
---@return {unread_count: number, feeds_count: number, categories_count: number}|nil counts, Error|nil error
function DataRepository:getCollectionsCounts(config)
    -- Get unread count
    local unread_count, unread_err = self:getUnreadCount(config)
    if unread_err then
        return nil, unread_err
    end
    ---@cast unread_count -nil

    -- Get feeds count
    local feeds_count, feeds_err = self:getFeedCount(config)
    if feeds_err then
        return nil, feeds_err
    end
    ---@cast feeds_count -nil

    -- Get categories count
    local categories_count, categories_err = self:getCategoryCount(config)
    if categories_err then
        return nil, categories_err
    end
    ---@cast categories_count -nil

    return {
        unread_count = unread_count,
        feeds_count = feeds_count,
        categories_count = categories_count,
    }
end

---Get unread count (cached - critical for main menu performance)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function DataRepository:getUnreadCount(config)
    -- Use URL-based cache key for consistency
    local options = {
        order = self.settings.order,
        direction = self.settings.direction,
        limit = 1,
        status = { 'unread' },
    }
    local cache_key = self.miniflux_api:buildEntriesUrl(options) .. '_count'

    return self:fetchWithCache(cache_key, self.settings.api_cache_ttl, function()
        local result, err = self.miniflux_api:getEntries(options, config)
        if err then
            return nil, err
        end
        ---@cast result -nil
        return result.total or 0, nil
    end)
end

-- =============================================================================
-- CACHE MANAGEMENT
-- =============================================================================

---Invalidate all cached data
---Critical for count updates after status changes
---@return boolean success
function DataRepository:invalidateAll()
    logger.info('[Miniflux:DataRepository] Invalidating all cache')

    self.cache:clear()
    return true
end

---Invalidate specific cache key
---@param cache_key string Cache key to invalidate
---@return boolean success
function DataRepository:invalidate(cache_key)
    logger.dbg('[Miniflux:DataRepository] Invalidating cache key:', cache_key)

    return self.cache:remove(cache_key)
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

local invalidating_keys = {
    [MinifluxSettings.Key.ORDER] = true,
    [MinifluxSettings.Key.DIRECTION] = true,
    [MinifluxSettings.Key.LIMIT] = true,
    [MinifluxSettings.Key.HIDE_READ_ENTRIES] = true,
}

function DataRepository:onMinifluxSettingsChanged(payload)
    local key = payload.key

    if invalidating_keys[key] then
        logger.info('[Miniflux:DataRepository] Invalidating cache due to setting change:', key)
        self:invalidateAll()
    end
end

function DataRepository:onMinifluxCacheInvalidate()
    logger.info('[Miniflux:DataRepository] Cache invalidation event received')
    self:invalidateAll()
end

return DataRepository
