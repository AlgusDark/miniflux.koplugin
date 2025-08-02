local EventListener = require('ui/widget/eventlistener')
local logger = require('logger')

---Feeds domain - handles all feed-related operations
---@class Feeds : EventListener
---@field miniflux Miniflux Parent plugin reference
---@field http_cache HTTPCacheAdapter HTTP cache adapter for feeds data
local Feeds = EventListener:extend({})

---Initialize feeds domain
function Feeds:init()
    logger.dbg('[Miniflux:Feeds] Initialized')
end

---Get all feeds (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function Feeds:getFeeds(config)
    return self.http_cache:fetchWithCache('feeds', function()
        return self.miniflux.api:getFeeds(config)
    end)
end

---Get feeds with counters (cached separately with shorter TTL)
---@param config? table Optional configuration with dialogs
---@return {feeds: MinifluxFeed[], counters: MinifluxFeedCounters}|nil result, Error|nil error
function Feeds:getFeedsWithCounters(config)
    return self.http_cache:fetchWithCache('feeds_with_counters', {
        ttl = self.miniflux.settings.api_cache_ttl_counters,
        fetcher = function()
            local feeds, err = self:getFeeds(config)
            if err then
                return nil, err
            end

            local counters, counters_err = self.miniflux.api:getFeedCounters()
            if counters_err then
                counters = { reads = {}, unreads = {} }
            end

            return { feeds = feeds, counters = counters }, nil
        end,
    })
end

---Get feed count (uses cached feeds)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function Feeds:getFeedCount(config)
    local feeds, err = self:getFeeds(config)
    if err then
        return nil, err
    end
    return #feeds, nil
end

---Get entries by feed
---@param feed_id number|string Feed ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function Feeds:getEntriesByFeed(feed_id, config)
    local options = {
        feed_id = feed_id,
        order = self.miniflux.settings.order,
        direction = self.miniflux.settings.direction,
        limit = self.miniflux.settings.limit,
        status = self.miniflux.settings.hide_read_entries and { 'unread' } or { 'unread', 'read' },
    }

    local result, err = self.miniflux.api:getFeedEntries(feed_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Mark all entries in a feed as read
---@param feed_id number|string The feed ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function Feeds:markFeedAsRead(feed_id, config)
    -- Simple validation - accept string or number
    if not feed_id then
        local Error = require('shared/error')
        local _ = require('gettext')
        return nil, Error.new(_('Feed ID is required'))
    end

    return self.miniflux.api:markFeedAsRead(feed_id, config)
end

return Feeds
