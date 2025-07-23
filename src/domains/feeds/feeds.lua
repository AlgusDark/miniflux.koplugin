local EventListener = require('ui/widget/eventlistener')
local CacheAdapter = require('shared/cache/cache_adapter')
local logger = require('logger')

---Feeds domain - handles all feed-related operations
---@class Feeds : EventListener
---@field miniflux Miniflux Parent plugin reference
---@field cache CacheAdapter Cache adapter for feeds data
local Feeds = EventListener:extend({})

---Initialize feeds domain
function Feeds:init()
    local miniflux = self.miniflux
    self.cache = CacheAdapter:new(miniflux.settings)
    logger.dbg('[Miniflux:Feeds] Initialized')
end

---Get all feeds (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function Feeds:getFeeds(config)
    return self.cache:fetchWithCache('feeds', function()
        return self.miniflux.api:getFeeds(config)
    end)
end

---Get feeds with counters (cached separately with shorter TTL)
---@param config? table Optional configuration with dialogs
---@return {feeds: MinifluxFeed[], counters: MinifluxFeedCounters}|nil result, Error|nil error
function Feeds:getFeedsWithCounters(config)
    return self.cache:fetchWithCache('feeds_with_counters', {
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

---Get entries by feed (NOT cached - preserves current behavior)
---@param feed_id number Feed ID
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
---@param feed_id number The feed ID
---@return boolean success
function Feeds:markAsRead(feed_id)
    local _ = require('gettext')
    local Notification = require('shared/utils/notification')

    -- Validate feed ID
    if not feed_id or type(feed_id) ~= 'number' or feed_id <= 0 then
        Notification:error(_('Invalid feed ID'))
        return false
    end

    -- Call API with loading dialog
    local _result, err = self.miniflux.api:markFeedAsRead(feed_id, {
        dialogs = {
            loading = { text = _('Marking feed as read...') },
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        local CollectionsQueue = require('features/sync/utils/collections_queue')
        local queue = CollectionsQueue:new('feed')
        queue:enqueue(feed_id, 'mark_all_read')

        Notification:info(_('Feed marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local CollectionsQueue = require('features/sync/utils/collections_queue')
        local queue = CollectionsQueue:new('feed')
        queue:remove(feed_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        local MinifluxEvent = require('shared/utils/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        Notification:success(_('Feed marked as read'))
        return true
    end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

---@private
function Feeds:shouldInvalidateCache(key)
    local invalidating_keys = {
        [self.miniflux.settings.Key.ORDER] = true,
        [self.miniflux.settings.Key.DIRECTION] = true,
        [self.miniflux.settings.Key.LIMIT] = true,
        [self.miniflux.settings.Key.HIDE_READ_ENTRIES] = true,
    }
    return invalidating_keys[key] == true
end

function Feeds:onMinifluxSettingsChanged(payload)
    local key = payload.key

    if self:shouldInvalidateCache(key) then
        logger.info('[Miniflux:Feeds] Invalidating cache due to setting change:', key)
        self.cache:clear()
    end
end

function Feeds:onMinifluxCacheInvalidate()
    logger.info('[Miniflux:Feeds] Cache invalidation event received')
    self.cache:clear()
end

return Feeds
