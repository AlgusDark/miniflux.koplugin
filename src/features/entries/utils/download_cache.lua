local lfs = require('libs/libkoreader-lfs')
local logger = require('logger')

--- Download status cache to avoid repeated file system checks
--- This significantly improves performance when displaying entry lists
--- on e-ink devices where file system operations are expensive
---@class DownloadCache
local DownloadCache = {}

-- Cache storage with TTL
local cache = {}
local cache_ttl = 60 -- 60 seconds TTL

---Clear expired entries from cache
local function clearExpired()
    local now = os.time()
    for entry_id, data in pairs(cache) do
        if now > data.expires_at then
            cache[entry_id] = nil
        end
    end
end

---Check if an entry is downloaded with caching
---@param entry_id number Entry ID to check
---@param get_path_fn function Function that returns the HTML path for an entry ID
---@return boolean is_downloaded
function DownloadCache.isDownloaded(entry_id, get_path_fn)
    if not entry_id then
        return false
    end

    local now = os.time()

    -- Check cache first
    local cached = cache[entry_id]
    if cached and now <= cached.expires_at then
        logger.dbg('[Miniflux:DownloadCache] Cache hit for entry', entry_id)
        return cached.is_downloaded
    end

    -- Cache miss - check file system
    logger.dbg('[Miniflux:DownloadCache] Cache miss for entry', entry_id, '- checking filesystem')
    local html_file = get_path_fn(entry_id)
    local is_downloaded = lfs.attributes(html_file, 'mode') == 'file'

    -- Store in cache
    cache[entry_id] = {
        is_downloaded = is_downloaded,
        expires_at = now + cache_ttl,
    }

    -- Periodically clean expired entries (every 10 checks)
    if math.random(10) == 1 then
        clearExpired()
    end

    return is_downloaded
end

---Invalidate cache for a specific entry
---@param entry_id number Entry ID to invalidate
function DownloadCache.invalidate(entry_id)
    if entry_id then
        logger.dbg('[Miniflux:DownloadCache] Invalidating cache for entry', entry_id)
        cache[entry_id] = nil
    end
end

---Clear the entire cache
function DownloadCache.clear()
    logger.info('[Miniflux:DownloadCache] Clearing download cache')
    cache = {}
end

---Get cache statistics (for debugging)
---@return table stats Cache statistics
function DownloadCache.getStats()
    local count = 0
    local expired = 0
    local now = os.time()

    for _, data in pairs(cache) do
        count = count + 1
        if now > data.expires_at then
            expired = expired + 1
        end
    end

    return {
        total_entries = count,
        expired_entries = expired,
        ttl_seconds = cache_ttl,
    }
end

return DownloadCache
