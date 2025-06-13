--[[--
Entries API Module

This module handles all entry-related operations including CRUD operations,
reading status management, bookmarking, and navigation between entries.

@module koplugin.miniflux.api.entries_api
--]]--

---@class MinifluxFeed
---@field id number Feed ID
---@field title string Feed title

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field content? string Entry content (HTML)
---@field summary? string Entry summary/excerpt
---@field url? string Entry URL
---@field published_at? string Publication timestamp
---@field status string Entry status: "read", "unread", "removed"
---@field starred boolean Whether entry is bookmarked/starred
---@field feed? MinifluxFeed Feed information

local QueryBuilder = require("api/utils/query_builder")
local RequestHelpers = require("api/utils/request_helpers")
local _ = require("gettext")

---@class EntriesAPI
---@field client BaseClient Reference to the base HTTP client
local EntriesAPI = {}

---Create a new entries API instance
---@param o? table Optional initialization table
---@return EntriesAPI
function EntriesAPI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the entries API with base client
---@param client BaseClient The base HTTP client instance
---@return EntriesAPI self for method chaining
function EntriesAPI:init(client)
    self.client = client
    return self
end

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getEntries(options)
    return RequestHelpers.getEntriesWithOptions(self.client, "/entries", options)
end

---Get a single entry by ID
---@param entry_id number The entry ID
---@return boolean success, MinifluxEntry|string result_or_error
function EntriesAPI:getEntry(entry_id)
    return RequestHelpers.getById(self.client, "/entries", entry_id)
end

---Mark an entry as read
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function EntriesAPI:markEntryAsRead(entry_id)
    return RequestHelpers.markEntries(self.client, entry_id, "read")
end

---Mark an entry as unread
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function EntriesAPI:markEntryAsUnread(entry_id)
    return RequestHelpers.markEntries(self.client, entry_id, "unread")
end

---Mark multiple entries as read
---@param entry_ids number[] Array of entry IDs to mark as read
---@return boolean success, any result_or_error
function EntriesAPI:markEntriesAsRead(entry_ids)
    return RequestHelpers.markEntries(self.client, entry_ids, "read")
end

---Mark multiple entries as unread
---@param entry_ids number[] Array of entry IDs to mark as unread
---@return boolean success, any result_or_error
function EntriesAPI:markEntriesAsUnread(entry_ids)
    return RequestHelpers.markEntries(self.client, entry_ids, "unread")
end

---Toggle bookmark status of an entry
---@param entry_id number The entry ID to toggle bookmark
---@return boolean success, any result_or_error
function EntriesAPI:toggleBookmark(entry_id)
    return RequestHelpers.put(self.client, "/entries/" .. tostring(entry_id) .. "/bookmark")
end

---Get the entry before a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getPreviousEntry(entry_id, options)
    local query_string = QueryBuilder.buildNavigationQuery(entry_id, "before", options)
    local endpoint = "/entries" .. query_string
    return self.client:makeRequest("GET", endpoint)
end

---Get the entry after a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getNextEntry(entry_id, options)
    local query_string = QueryBuilder.buildNavigationQuery(entry_id, "after", options)
    local endpoint = "/entries" .. query_string
    return self.client:makeRequest("GET", endpoint)
end

---Get only unread entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getUnreadEntries(options)
    options = options or {}
    options.status = {"unread"}
    return self:getEntries(options)
end

---Get only read entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getReadEntries(options)
    options = options or {}
    options.status = {"read"}
    return self:getEntries(options)
end

---Get starred/bookmarked entries
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function EntriesAPI:getStarredEntries(options)
    local query_string = QueryBuilder.buildStarredQuery(options)
    local endpoint = "/entries" .. query_string
    return self.client:makeRequest("GET", endpoint)
end

return EntriesAPI 