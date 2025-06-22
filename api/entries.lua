--[[--
Entries Module

This module handles all entry-related operations. It receives a reference to the
main API client and uses its HTTP methods for communication.

@module koplugin.miniflux.api.entries
--]]

local apiUtils = require("api/utils")

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field content? string Entry content (HTML)
---@field summary? string Entry summary/excerpt
---@field url? string Entry URL
---@field published_at? string Publication timestamp
---@field status string Entry status: "read", "unread", "removed"
---@field feed? MinifluxFeed Feed information

---@class Entries
---@field api MinifluxAPI Reference to the main API client
local Entries = {}

---Create a new entries module instance
---@param api MinifluxAPI The main API client instance
---@return Entries
function Entries:new(api)
    local o = {
        api = api,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- =============================================================================
-- ENTRY OPERATIONS
-- =============================================================================

---@class EntriesResponse
---@field entries MinifluxEntry[] Array of entries
---@field total? number Total number of entries available

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getEntries(options)
    local query_params = apiUtils.buildQueryParams(options)
    return self.api:get("/entries", { query = query_params })
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

---Mark entries with status
---@param entry_ids number|number[] Entry ID or array of entry IDs
---@param status EntryStatus New status for entries
---@return boolean success, any result_or_error
local function markEntries(api, entry_ids, status)
    local ids_array = type(entry_ids) == "table" and entry_ids or { entry_ids }
    local body = {
        entry_ids = ids_array,
        status = status,
    }
    return api:put("/entries", { body = body })
end

---Mark an entry as read
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function Entries:markAsRead(entry_id)
    return markEntries(self.api, entry_id, "read")
end

---Mark an entry as unread
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function Entries:markAsUnread(entry_id)
    return markEntries(self.api, entry_id, "unread")
end

return Entries
