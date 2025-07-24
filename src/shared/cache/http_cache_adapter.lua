local CacheStore = require('shared/utils/cache_store')

---HTTP API response cache adapter with TTL support
---@class HTTPCacheAdapter
---@field cache CacheStore Cache store instance
---@field config {api_cache_ttl: number, db_name: string} Configuration for TTL and database
local HTTPCacheAdapter = {}
HTTPCacheAdapter.__index = HTTPCacheAdapter

---Create a new HTTP cache adapter
---@param config {api_cache_ttl: number, db_name?: string} Configuration containing cache TTL and optional db name
---@return HTTPCacheAdapter
function HTTPCacheAdapter:new(config)
    local instance = setmetatable({}, self)
    instance.config = {
        api_cache_ttl = config.api_cache_ttl,
        db_name = config.db_name or 'cache.sqlite',
    }
    instance.cache = CacheStore:new({
        default_ttl = instance.config.api_cache_ttl,
        db_name = instance.config.db_name,
    })
    return instance
end

---Generic cache-or-fetch helper for HTTP API responses
---@param cache_key string Cache key to use
---@param fetcher_or_opts function|{ttl: number, fetcher: function} Either fetcher function or options with ttl and fetcher
---@return any|nil result, Error|nil error
function HTTPCacheAdapter:fetchWithCache(cache_key, fetcher_or_opts)
    local fetcher, ttl

    if type(fetcher_or_opts) == 'function' then
        fetcher = fetcher_or_opts
        ttl = self.config.api_cache_ttl
    else
        fetcher = fetcher_or_opts.fetcher
        ttl = fetcher_or_opts.ttl or self.config.api_cache_ttl
    end

    local cached_data, is_valid = self.cache:get(cache_key, { ttl = ttl })

    if is_valid and cached_data then
        return cached_data.result, cached_data.error
    end

    -- Cache miss - fetch from API
    local result, err = fetcher()

    -- Cache result (even errors to avoid repeated failures)
    self.cache:set(cache_key, {
        data = { result = result, error = err },
        ttl = ttl,
    })

    return result, err
end

---Clear all cached data
---@return boolean success
function HTTPCacheAdapter:clear()
    self.cache:clear()
    return true
end

---Remove specific cache key
---@param cache_key string Cache key to remove
---@return boolean success
function HTTPCacheAdapter:remove(cache_key)
    return self.cache:remove(cache_key)
end

return HTTPCacheAdapter
