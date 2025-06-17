--[[--
Entries Module

This module handles all entry-related operations. It receives a reference to the
main API client and uses its makeRequest method for HTTP communication.

@module koplugin.miniflux.api.entries
--]]--

local Utils = require("api/utils")

---@class Entries
---@field api MinifluxAPI Reference to the main API client
local Entries = {}

---Create a new entries module instance
---@param api MinifluxAPI The main API client instance
---@return Entries
function Entries:new(api)
    local o = {
        api = api
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- =============================================================================
-- ENTRY CRUD OPERATIONS
-- =============================================================================

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getEntries(options)
    return Utils.getEntriesWithOptions(self.api, "/entries", options)
end

---Get a single entry by ID
---@param entry_id number The entry ID
---@return boolean success, MinifluxEntry|string result_or_error
function Entries:getEntry(entry_id)
    return Utils.getById(self.api, "/entries", entry_id)
end

---Get unread entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getUnreadEntries(options)
    options = options or {}
    options.status = {"unread"}
    return self:getEntries(options)
end

---Get read entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getReadEntries(options)
    options = options or {}
    options.status = {"read"}
    return self:getEntries(options)
end

---Get starred entries
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getStarredEntries(options)
    local query_string = Utils.buildStarredQuery(options)
    local endpoint = "/entries" .. query_string
    return self.api:makeRequest("GET", endpoint)
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

---Mark an entry as read
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function Entries:markAsRead(entry_id)
    return Utils.markEntries(self.api, entry_id, "read")
end

---Mark an entry as unread
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function Entries:markAsUnread(entry_id)
    return Utils.markEntries(self.api, entry_id, "unread")
end

---Mark multiple entries as read
---@param entry_ids number[] Array of entry IDs to mark as read
---@return boolean success, any result_or_error
function Entries:markMultipleAsRead(entry_ids)
    return Utils.markEntries(self.api, entry_ids, "read")
end

---Mark multiple entries as unread
---@param entry_ids number[] Array of entry IDs to mark as unread
---@return boolean success, any result_or_error
function Entries:markMultipleAsUnread(entry_ids)
    return Utils.markEntries(self.api, entry_ids, "unread")
end

---Toggle bookmark status of an entry
---@param entry_id number The entry ID to toggle bookmark
---@return boolean success, any result_or_error
function Entries:toggleBookmark(entry_id)
    return Utils.put(self.api, "/entries/" .. tostring(entry_id) .. "/bookmark")
end

-- =============================================================================
-- ENTRY NAVIGATION
-- =============================================================================

---Get the entry before a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getPrevious(entry_id, options)
    local query_string = Utils.buildNavigationQuery(entry_id, "before", options)
    local endpoint = "/entries" .. query_string
    return self.api:makeRequest("GET", endpoint)
end

---Get the entry after a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getNext(entry_id, options)
    local query_string = Utils.buildNavigationQuery(entry_id, "after", options)
    local endpoint = "/entries" .. query_string
    return self.api:makeRequest("GET", endpoint)
end

-- =============================================================================
-- BACKWARD COMPATIBILITY METHODS
-- These methods provide compatibility with the old API structure
-- =============================================================================

---Get entries (compatibility alias)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:get(options)
    return self:getEntries(options)
end

---Mark entry as read (compatibility alias)
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function Entries:markEntryAsRead(entry_id)
    return self:markAsRead(entry_id)
end

---Mark entry as unread (compatibility alias)
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function Entries:markEntryAsUnread(entry_id)
    return self:markAsUnread(entry_id)
end

---Mark multiple entries as read (compatibility alias)
---@param entry_ids number[] Array of entry IDs to mark as read
---@return boolean success, any result_or_error
function Entries:markEntriesAsRead(entry_ids)
    return self:markMultipleAsRead(entry_ids)
end

---Mark multiple entries as unread (compatibility alias)
---@param entry_ids number[] Array of entry IDs to mark as unread
---@return boolean success, any result_or_error
function Entries:markEntriesAsUnread(entry_ids)
    return self:markMultipleAsUnread(entry_ids)
end

---Get previous entry (compatibility alias)
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getPreviousEntry(entry_id, options)
    return self:getPrevious(entry_id, options)
end

---Get next entry (compatibility alias)
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getNextEntry(entry_id, options)
    return self:getNext(entry_id, options)
end

return Entries 