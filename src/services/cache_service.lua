local CacheStore = require('utils/cache_store')

-- **Cache Service** - Replaces repository pattern with simple caching
--
-- This service eliminates the 4-layer repository abstraction and provides
-- direct API calls with simple caching. Maintains all current functionality:
-- - Browser navigation performance (cached counts)
-- - Cache invalidation patterns (count updates)
-- - E-ink device optimizations (entry arrays NOT cached)
-- - All existing TTL values and behavior
---@class CacheService
---@field miniflux_api MinifluxAPI Direct API access
---@field settings MinifluxSettings Settings for TTL and cache control
---@field cache CacheStore Shared cache store for all data types
local CacheService = {}

---@class CacheServiceDeps
---@field miniflux_api MinifluxAPI
---@field settings MinifluxSettings

---Create new cache service instance
---@param deps CacheServiceDeps Dependencies
---@return CacheService
function CacheService:new(deps)
    local instance = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
        cache = CacheStore:new({
            default_ttl = deps.settings.api_cache_ttl,
            db_name = 'miniflux_cache.sqlite',
        }),
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- FEED OPERATIONS (replaces FeedRepository)
-- =============================================================================

---Get all feeds (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function CacheService:getFeeds(config)
    if not self.settings.api_cache_enabled then
        return self.miniflux_api:getFeeds(config)
    end

    local cache_key = 'feeds'
    local cached_data, is_valid = self.cache:get(cache_key, { ttl = 300 })

    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - fetch from API
    local feeds, err = self.miniflux_api:getFeeds(config)

    -- Cache result (even errors to avoid repeated failures)
    self.cache:set(cache_key, {
        data = { result = feeds, error = err },
        ttl = 300,
    })

    return feeds, err
end

---Get feeds with counters (cached separately with shorter TTL)
---@param config? table Optional configuration with dialogs
---@return {feeds: MinifluxFeed[], counters: MinifluxFeedCounters}|nil result, Error|nil error
function CacheService:getFeedsWithCounters(config)
    if not self.settings.api_cache_enabled then
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

    local cache_key = 'feeds_with_counters'
    local cached_data, is_valid = self.cache:get(cache_key, { ttl = 60 })

    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - build result
    local feeds, err = self:getFeeds(config)
    if err then
        return nil, err
    end

    local counters, counters_err = self.miniflux_api:getFeedCounters()
    if counters_err then
        counters = { reads = {}, unreads = {} }
    end

    local result = { feeds = feeds, counters = counters }

    self.cache:set(cache_key, {
        data = { result = result, error = nil },
        ttl = 60, -- Shorter TTL for counters
    })

    return result, nil
end

---Get feed count (uses cached feeds)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function CacheService:getFeedCount(config)
    local feeds, err = self:getFeeds(config)
    if err then
        return nil, err
    end
    return #feeds, nil
end

-- =============================================================================
-- CATEGORY OPERATIONS (replaces CategoryRepository)
-- =============================================================================

---Get all categories with counts (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function CacheService:getCategories(config)
    if not self.settings.api_cache_enabled then
        return self.miniflux_api:getCategories(true, config) -- include counts
    end

    local cache_key = 'categories'
    local cached_data, is_valid = self.cache:get(cache_key, { ttl = 120 })

    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - fetch from API
    local categories, err = self.miniflux_api:getCategories(true, config)

    self.cache:set(cache_key, {
        data = { result = categories, error = err },
        ttl = 120, -- 2 minutes TTL for categories
    })

    return categories, err
end

---Get category count (uses cached categories)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function CacheService:getCategoryCount(config)
    local categories, err = self:getCategories(config)
    if err then
        return nil, err
    end
    return #categories, nil
end

-- =============================================================================
-- ENTRY OPERATIONS (replaces EntryRepository)
-- =============================================================================

---Get unread entries (NOT cached - preserves current behavior)
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function CacheService:getUnreadEntries(config)
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
function CacheService:getEntriesByFeed(feed_id, config)
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
function CacheService:getEntriesByCategory(category_id, config)
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

---Get unread count (cached - critical for main menu performance)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function CacheService:getUnreadCount(config)
    if not self.settings.api_cache_enabled then
        local options = { limit = 1, status = { 'unread' } }
        local result, err = self.miniflux_api:getEntries(options, config)
        if err then
            return nil, err
        end
        ---@cast result -nil
        return result.total or 0, nil
    end

    -- Use URL-based cache key for consistency (preserves current behavior)
    local options = {
        order = self.settings.order,
        direction = self.settings.direction,
        limit = 1,
        status = { 'unread' },
    }
    local cache_key = self.miniflux_api:buildEntriesUrl(options) .. '_count'

    local cached_data, is_valid = self.cache:get(cache_key, { ttl = 300 })
    if is_valid then
        return cached_data, nil
    end

    -- Cache miss - fetch count
    local result, err = self.miniflux_api:getEntries(options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    local count = result.total or 0
    self.cache:set(cache_key, { data = count, ttl = 300 })

    return count, nil
end

-- =============================================================================
-- CACHE MANAGEMENT (preserves all invalidation patterns)
-- =============================================================================

---Invalidate all cached data
---Critical for count updates after status changes
---@return boolean success
function CacheService:invalidateAll()
    if not self.settings.api_cache_enabled then
        return true
    end

    self.cache:clear()
    return true
end

---Invalidate specific cache key
---@param cache_key string Cache key to invalidate
---@return boolean success
function CacheService:invalidate(cache_key)
    if not self.settings.api_cache_enabled then
        return true
    end

    return self.cache:remove(cache_key)
end

---Get cache statistics
---@return {count: number, size: number}
function CacheService:getCacheStats()
    if not self.settings.api_cache_enabled then
        return { count = 0, size = 0 }
    end

    return self.cache:getStats()
end

return CacheService
