--[[--
Feeds Module

This module handles all feed-related operations including feed listing,
feed entries retrieval, and feed statistics management.

@module koplugin.miniflux.api.feeds
--]]--

local Utils = require("api/utils")

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
-- FEED OPERATIONS
-- =============================================================================

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function Feeds:getFeeds()
    return Utils.get(self.api, "/feeds")
end

---Get a specific feed by ID
---@param feed_id number The feed ID
---@return boolean success, MinifluxFeed|string result_or_error
function Feeds:getFeed(feed_id)
    return Utils.getById(self.api, "/feeds", feed_id)
end

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function Feeds:getCounters()
    return Utils.get(self.api, "/feeds/counters")
end

---Refresh a specific feed (trigger update)
---@param feed_id number The feed ID to refresh
---@return boolean success, any result_or_error
function Feeds:refresh(feed_id)
    return Utils.put(self.api, "/feeds/" .. tostring(feed_id) .. "/refresh")
end

---Get feed icon for a specific feed
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function Feeds:getIcon(feed_id)
    return Utils.get(self.api, "/feeds/" .. tostring(feed_id) .. "/icon")
end

-- =============================================================================
-- FEED ENTRIES OPERATIONS
-- =============================================================================

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getEntries(feed_id, options)
    return Utils.getResourceEntries(self.api, "feeds", feed_id, options)
end

---Get unread entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getUnreadEntries(feed_id, options)
    return Utils.getResourceEntriesByStatus(self.api, "feeds", feed_id, {"unread"}, options)
end

---Get read entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Feeds:getReadEntries(feed_id, options)
    return Utils.getResourceEntriesByStatus(self.api, "feeds", feed_id, {"read"}, options)
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function Feeds:markAsRead(feed_id)
    return Utils.markResourceAsRead(self.api, "feeds", feed_id)
end



return Feeds 