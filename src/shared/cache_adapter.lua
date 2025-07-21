local CacheStore = require('utils/cache_store')

---Generic caching adapter for domain slices
---@class CacheAdapter
---@field cache CacheStore Cache store instance
---@field settings MinifluxSettings Settings for TTL configuration
local CacheAdapter = {}
CacheAdapter.__index = CacheAdapter

---Create a new cache adapter
---@param settings MinifluxSettings Settings containing cache configuration
---@return CacheAdapter
function CacheAdapter:new(settings)
    local instance = setmetatable({}, self)
    instance.settings = settings
    instance.cache = CacheStore:new({
        default_ttl = settings.api_cache_ttl,
        db_name = 'miniflux_cache.sqlite',
    })
    return instance
end

---Generic cache-or-fetch helper
---@param cache_key string Cache key to use
---@param fetcher_or_opts function|{ttl: number, fetcher: function} Either fetcher function or options with ttl and fetcher
---@return any|nil result, Error|nil error
function CacheAdapter:fetchWithCache(cache_key, fetcher_or_opts)
    local fetcher, ttl

    if type(fetcher_or_opts) == 'function' then
        fetcher = fetcher_or_opts
        ttl = self.settings.api_cache_ttl
    else
        fetcher = fetcher_or_opts.fetcher
        ttl = fetcher_or_opts.ttl or self.settings.api_cache_ttl
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
function CacheAdapter:clear()
    self.cache:clear()
    return true
end

---Remove specific cache key
---@param cache_key string Cache key to remove
---@return boolean success
function CacheAdapter:remove(cache_key)
    return self.cache:remove(cache_key)
end

return CacheAdapter
