--[[--
Feeds Module

This module handles all feed-related operations including feed listing,
feed entries retrieval, and feed statistics management.

@module koplugin.miniflux.api.feeds
--]] --

---@class Feeds
---@field api MinifluxAPI Reference to the main API client
local Feeds = {}

---Create a new feeds module instance
---@param api MinifluxAPI The main API client instance
---@return Feeds
function Feeds:new(api)
    local o = {
        api = api
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

---Convert ApiOptions to query parameters
---@param options? ApiOptions Query options for filtering and sorting
---@return table Query parameters table
local function buildQueryParams(options)
    if not options then
        return {}
    end

    local params = {}

    if options.limit then
        params.limit = options.limit
    end

    if options.order then
        params.order = options.order
    end

    if options.direction then
        params.direction = options.direction
    end

    if options.status then
        params.status = options.status
    end

    if options.category_id then
        params.category_id = options.category_id
    end

    if options.feed_id then
        params.feed_id = options.feed_id
    end

    if options.published_before then
        params.published_before = options.published_before
    end

    if options.published_after then
        params.published_after = options.published_after
    end

    return params
end

-- =============================================================================
-- FEED OPERATIONS
-- =============================================================================

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function Feeds:getFeeds()
    return self.api:get("/feeds")
end

---Get a specific feed by ID
---@param feed_id number The feed ID
---@return boolean success, MinifluxFeed|string result_or_error
function Feeds:getFeed(feed_id)
    return self.api:get("/feeds/" .. tostring(feed_id))
end

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function Feeds:getCounters()
    return self.api:get("/feeds/counters")
end

---Refresh a specific feed (trigger update)
---@param feed_id number The feed ID to refresh
---@return boolean success, any result_or_error
function Feeds:refresh(feed_id)
    return self.api:put("/feeds/" .. tostring(feed_id) .. "/refresh")
end

---Get feed icon for a specific feed
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function Feeds:getIcon(feed_id)
    return self.api:get("/feeds/" .. tostring(feed_id) .. "/icon")
end

-- =============================================================================
-- FEED ENTRIES OPERATIONS
-- =============================================================================

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getEntries(feed_id, options)
    local query_params = buildQueryParams(options)
    local endpoint = "/feeds/" .. tostring(feed_id) .. "/entries"
    return self.api:get(endpoint, { query = query_params })
end

---Get unread entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getUnreadEntries(feed_id, options)
    options = options or {}
    options.status = { "unread" }
    return self:getEntries(feed_id, options)
end

---Get read entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getReadEntries(feed_id, options)
    options = options or {}
    options.status = { "read" }
    return self:getEntries(feed_id, options)
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function Feeds:markAsRead(feed_id)
    local endpoint = "/feeds/" .. tostring(feed_id) .. "/mark-all-as-read"
    return self.api:put(endpoint)
end

return Feeds
