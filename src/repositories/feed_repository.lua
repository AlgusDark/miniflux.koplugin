local CachedRepository = require('src/repositories/cached_repository')

---@class MinifluxFeedsWithCountersResult
---@field feeds MinifluxFeed[] Array of feeds
---@field counters MinifluxFeedCounters Feed counters with reads/unreads maps

-- **Feed Repository** - Data Access Layer
--
-- Handles all feed-related data access and API interactions with caching support.
-- Provides a clean interface for feed data without UI concerns.
---@class FeedRepository
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field settings MinifluxSettings Settings instance
---@field cache CachedRepository Cache instance for feed operations
local FeedRepository = {}

---Create a new FeedRepository instance
---@param deps {miniflux_api: MinifluxAPI, settings: MinifluxSettings} Dependencies table
---@return FeedRepository
function FeedRepository:new(deps)
    local obj = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
        cache = CachedRepository:new({
            settings = deps.settings,
            cache_prefix = 'miniflux_feeds',
        }),
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get all feeds with caching support
---@param config? table Configuration with optional dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function FeedRepository:getAll(config)
    local cache_key = self.cache:generateCacheKey('getAll')

    return self.cache:getCached(cache_key, {
        api_call = function()
            local feeds, err = self.miniflux_api:getFeeds(config)
            if err then
                return nil, err
            end
            ---@cast feeds -nil

            return feeds, nil
        end,
    })
end

---Get feeds with their read/unread counters (cached separately)
---@param config? table Configuration with optional dialogs
---@return MinifluxFeedsWithCountersResult|nil result, Error|nil error
function FeedRepository:getAllWithCounters(config)
    local cache_key = self.cache:generateCacheKey('getAllWithCounters')

    return self.cache:getCached(cache_key, {
        api_call = function()
            -- Get feeds first
            local feeds, err = self:getAll(config)
            if err then
                return nil, err
            end

            -- Get counters (optional - continue without if it fails)
            local counters, counters_err = self.miniflux_api:getFeedCounters()
            if counters_err then
                counters = { reads = {}, unreads = {} } -- Empty counters on failure
            end

            return {
                feeds = feeds,
                counters = counters,
            },
                nil
        end,
        ttl = 60, -- Shorter TTL for counters (1 minute)
    })
end

---Get feeds count for initialization (uses cached feeds)
---@param config? table Configuration with optional dialogs
---@return number|nil result, Error|nil error
function FeedRepository:getCount(config)
    local feeds, err = self:getAll(config)
    if err then
        return nil, err
    end

    return #feeds, nil
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function FeedRepository:markAsRead(feed_id, config)
    return self.miniflux_api:markFeedAsRead(feed_id, config)
end

---Invalidate all feed cache (useful when feeds are added/removed)
---@return boolean success
function FeedRepository:invalidateCache()
    self.cache:invalidateAll()
    return true
end

return FeedRepository
