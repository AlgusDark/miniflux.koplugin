--[[--
Feeds API Module

This module handles all feed-related operations including feed listing,
feed entries retrieval, and feed statistics management.

@module koplugin.miniflux.api.feeds_api
--]]--

local RequestHelpers = require("api/utils/request_helpers")
local _ = require("gettext")

---@class FeedsAPI
---@field client BaseClient Reference to the base HTTP client
local FeedsAPI = {}

---Create a new feeds API instance
---@param o? table Optional initialization table
---@return FeedsAPI
function FeedsAPI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the feeds API with base client
---@param client BaseClient The base HTTP client instance
---@return FeedsAPI self for method chaining
function FeedsAPI:init(client)
    self.client = client
    return self
end

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function FeedsAPI:getFeeds()
    return RequestHelpers.get(self.client, "/feeds")
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function FeedsAPI:getFeedEntries(feed_id, options)
    return RequestHelpers.getResourceEntries(self.client, "feeds", feed_id, options)
end

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function FeedsAPI:getFeedCounters()
    return RequestHelpers.get(self.client, "/feeds/counters")
end

---Get a specific feed by ID
---@param feed_id number The feed ID
---@return boolean success, MinifluxFeed|string result_or_error
function FeedsAPI:getFeed(feed_id)
    return RequestHelpers.getById(self.client, "/feeds", feed_id)
end

---Get unread entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function FeedsAPI:getFeedUnreadEntries(feed_id, options)
    return RequestHelpers.getResourceEntriesByStatus(self.client, "feeds", feed_id, {"unread"}, options)
end

---Get read entries for a specific feed (convenience method)
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function FeedsAPI:getFeedReadEntries(feed_id, options)
    return RequestHelpers.getResourceEntriesByStatus(self.client, "feeds", feed_id, {"read"}, options)
end

---Refresh a specific feed (trigger update)
---@param feed_id number The feed ID to refresh
---@return boolean success, any result_or_error
function FeedsAPI:refreshFeed(feed_id)
    return RequestHelpers.put(self.client, "/feeds/" .. tostring(feed_id) .. "/refresh")
end

---Get feed icon for a specific feed
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function FeedsAPI:getFeedIcon(feed_id)
    return RequestHelpers.get(self.client, "/feeds/" .. tostring(feed_id) .. "/icon")
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@return boolean success, any result_or_error
function FeedsAPI:markFeedAsRead(feed_id)
    return RequestHelpers.markResourceAsRead(self.client, "feeds", feed_id)
end

return FeedsAPI 