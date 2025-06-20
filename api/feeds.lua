--[[--
Feeds Module

This module handles all feed-related operations including feed listing,
feed entries retrieval, and feed statistics management.

@module koplugin.miniflux.api.feeds
--]] --

local apiUtils = require("api/utils")

---@class MinifluxFeed
---@field id number Feed ID
---@field title string Feed title
---@field category_id? number Category ID this feed belongs to

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
-- OPERATIONS
-- =============================================================================

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function Feeds:getAll()
    return self.api:get("/feeds")
end

---@class FeedCounters
---@field reads table<string, number> Read counts per feed ID
---@field unreads table<string, number> Unread counts per feed ID

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function Feeds:getCounters()
    return self.api:get("/feeds/counters")
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getEntries(feed_id, options)
    local query_params = apiUtils.buildQueryParams(options)
    local endpoint = "/feeds/" .. tostring(feed_id) .. "/entries"
    return self.api:get(endpoint, { query = query_params })
end

return Feeds
