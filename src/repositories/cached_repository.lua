local CacheStore = require('utils/cache_store')
local Error = require('utils/error')

-- **Cached Repository** - Base class for repositories with caching capabilities
--
-- This generic base class provides caching functionality that can be used by any
-- RSS provider repository. It handles cache key generation, TTL management, and
-- fallback to API calls when cache misses occur.
--
-- Example usage:
--   local cache_key = repo:generateCacheKey("getAll", {limit = 100})
--   return repo:getCached(cache_key, {
--       api_call = function() return api:getFeeds() end,
--       ttl = 300 -- 5 minutes
--   })
---@class CachedRepository
---@field cache_store CacheStore Cache store instance
---@field settings table Settings instance (must have api_cache_enabled and api_cache_ttl)
---@field cache_prefix string Prefix for cache keys to avoid collisions
local CachedRepository = {}

---@class CachedRepositoryConfig
---@field settings table Settings instance with cache configuration
---@field cache_prefix string Prefix for cache keys (e.g., "miniflux_feeds')

---Create a new CachedRepository instance
---@param config CachedRepositoryConfig Configuration options
---@return CachedRepository
function CachedRepository:new(config)
    local instance = {
        settings = config.settings,
        cache_prefix = config.cache_prefix,
        cache_store = CacheStore:new({
            default_ttl = config.settings.api_cache_ttl,
            db_name = 'miniflux_cache.sqlite',
        }),
    }

    setmetatable(instance, self)
    self.__index = self

    return instance
end

---Generate cache key with prefix and parameters
---@param method_name string Method name (e.g., "getAll", "getByFeed')
---@param params? table Optional parameters to include in key
---@return string cache_key
function CachedRepository:generateCacheKey(method_name, params)
    local key_parts = { self.cache_prefix, method_name }

    if params then
        -- Sort params for consistent keys
        local sorted_params = {}
        for k, v in pairs(params) do
            table.insert(sorted_params, k .. '=' .. tostring(v))
        end
        table.sort(sorted_params)

        for i, param in ipairs(sorted_params) do
            table.insert(key_parts, param)
        end
    end

    return table.concat(key_parts, '_')
end

---@class CachedRepositoryGetOptions
---@field api_call function Function that makes the API call
---@field ttl? number Custom TTL for this call (uses default if not provided)

---Get data with caching support
---@param cache_key string Cache key
---@param opts CachedRepositoryGetOptions Options table with api_call and ttl
---@return any|nil result, Error|nil error
function CachedRepository:getCached(cache_key, opts)
    if not cache_key or type(cache_key) ~= 'string' or cache_key == '' then
        return nil, Error.new('Invalid cache key')
    end

    if not opts or type(opts) ~= 'table' or not opts.api_call then
        return nil, Error.new('Invalid options - api_call required')
    end

    -- Check if caching is enabled
    if not self.settings.api_cache_enabled then
        return opts.api_call()
    end

    local ttl = opts.ttl or self.settings.api_cache_ttl

    -- Try cache first
    local cached_data, is_valid = self.cache_store:get(cache_key, { ttl = ttl })
    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - call API

    local result, error = opts.api_call()

    -- Cache the result (even if it's an error, to avoid repeated failed calls)
    local cache_data = {
        result = result,
        error = error,
        timestamp = os.time(),
    }

    self.cache_store:set(cache_key, {
        data = cache_data,
        ttl = ttl,
    })

    return result, error
end

---Invalidate cache for specific key
---@param cache_key string Cache key to invalidate
---@return boolean success
function CachedRepository:invalidate(cache_key)
    if not self.settings.api_cache_enabled then
        return true -- Nothing to invalidate
    end

    return self.cache_store:remove(cache_key)
end

---Invalidate all cache entries for this repository
---@return boolean success
function CachedRepository:invalidateAll()
    if not self.settings.api_cache_enabled then
        return true -- Nothing to invalidate, but that's success
    end

    -- For now, clear everything (could be optimized to only clear prefixed keys)
    self.cache_store:clear()
    return true
end

---Get cache statistics for this repository
---@return {count: number, size: number}
function CachedRepository:getCacheStats()
    if not self.settings.api_cache_enabled then
        return { count = 0, size = 0 }
    end

    local stats = self.cache_store:getStats()
    return {
        count = stats.count,
        size = stats.size,
    }
end

return CachedRepository
