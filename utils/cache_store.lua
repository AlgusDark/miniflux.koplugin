local DataStorage = require("datastorage")
local CacheSQLite = require("cachesqlite")

-- **Generic Cache Store** - Provider-agnostic caching layer using KOReader's CacheSQLite
--
-- This module provides a generic key-value cache with TTL support that can be used
-- by any RSS provider. Uses SQLite with compression and LRU eviction.
--
-- PERFORMANCE INSIGHTS FOR E-INK DEVICES:
-- ✓ Small metadata (feeds, categories, counts) - cache reliably in SQLite
-- ✗ Large entry arrays (1.5-3MB) - causes CacheSQLite type conversion errors
-- ✗ Entry arrays change frequently - provide less caching benefit than metadata
-- ✓ Current 33KB database size shows optimal usage with small objects only
--
-- RECOMMENDATION: Only cache small, stable metadata objects. Let entry arrays
-- be fetched fresh from API to avoid memory pressure on e-ink devices.
--
-- Example usage:
--   local cache = CacheStore:new()
--   cache:set("feeds_list", {data = feeds, ttl = 300})
--   local data, valid = cache:get("feeds_list", {ttl = 300})
--   if valid then
--       -- Use cached data
--   end
---@class CacheStore
---@field cache CacheSQLite SQLite cache instance
---@field default_ttl number Default TTL in seconds
local CacheStore = {}

---@class CacheConfig
---@field cache_size? number Cache size in bytes (defaults to 10MB)
---@field default_ttl? number Default TTL in seconds (defaults to 300)
---@field db_name? string Database name (defaults to "content_cache.sqlite")

---Create a new CacheStore instance
---@param config? CacheConfig Configuration options
---@return CacheStore
function CacheStore:new(config)
    config = config or {}

    local db_path = DataStorage:getDataDir() .. "/cache/" .. (config.db_name or "content_cache.sqlite")
    local cache_size = config.cache_size or (10 * 1024 * 1024) -- 10MB default

    local cache_instance = CacheSQLite:new {
        slots = 500,       -- LRU slot count (newsdownloader pattern)
        size = cache_size, -- Total cache size in bytes
        db_path = db_path  -- SQLite database file path
    }

    local instance = {
        cache = cache_instance,
        default_ttl = config.default_ttl or 300 -- 5 minutes default
    }

    setmetatable(instance, self)
    self.__index = self



    return instance
end

---Create cache entry with TTL metadata
---@param data any Data to cache (should be small metadata, not large arrays)
---@param ttl number TTL in seconds
---@return table cache_entry
function CacheStore:createCacheEntry(data, ttl)
    return {
        data = data,
        created_at = os.time(), -- Use os.time() for consistent seconds-based timestamps
        ttl = ttl
    }
end

---Check if cache entry is expired
---@param cache_entry table Cache entry with metadata
---@return boolean expired
function CacheStore:isExpired(cache_entry)
    if not cache_entry or not cache_entry.created_at or not cache_entry.ttl then
        return true -- Invalid entry is considered expired
    end

    local now = os.time() -- Use os.time() for seconds since epoch
    local age = now - cache_entry.created_at

    return age >= cache_entry.ttl
end

---@class CacheSetOptions
---@field data any Data to cache
---@field ttl? number TTL in seconds (uses default if not provided)

---Store data in cache with TTL
---@param key string Cache key
---@param opts CacheSetOptions Options table with data and ttl
---@return boolean success
function CacheStore:set(key, opts)
    if not key or type(key) ~= "string" or key == "" then
        return false
    end

    if not opts or type(opts) ~= "table" then
        return false
    end

    local data = opts.data
    local ttl = opts.ttl or self.default_ttl

    local cache_entry = self:createCacheEntry(data, ttl)

    local success, err = self.cache:insert(key, cache_entry)

    if success and err then
        return true
    else
        -- CacheSQLite can fail with large objects due to type conversion errors
        -- This is expected behavior for large entry arrays - cache only small metadata

        return false -- Not a fatal error - just means no caching for this data
    end
end

---@class CacheGetOptions
---@field ttl? number TTL in seconds (uses default if not provided)

---Retrieve data from cache with TTL check
---@param key string Cache key
---@param opts? CacheGetOptions Options table with ttl
---@return any|nil data, boolean valid
function CacheStore:get(key, opts)
    opts = opts or {}
    local ttl = opts.ttl or self.default_ttl

    -- Get entry from cache and update access time for LRU
    local cache_entry = self.cache:check(key)

    if not cache_entry then
        return nil, false -- Cache miss
    end

    -- Check if entry is expired
    if self:isExpired(cache_entry) then
        self.cache:remove(key) -- Remove expired entry
        return nil, false
    end


    return cache_entry.data, true
end

---Remove cache entry
---@param key string Cache key
---@return boolean success
function CacheStore:remove(key)
    self.cache:remove(key)

    return true
end

---Clear all cache entries (useful for settings changes)
function CacheStore:clear()
    self.cache:clear()
end

---Get cache statistics from SQLite
---@return {size: number, count: number}
function CacheStore:getStats()
    -- CacheSQLite tracks current_size automatically
    local stats = {
        size = self.cache.current_size or 0,
        count = 0 -- CacheSQLite doesn't expose count directly
    }


    return stats
end

return CacheStore
