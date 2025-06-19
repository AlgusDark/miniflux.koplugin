--[[--
Entries Module

This module handles all entry-related operations. It receives a reference to the
main API client and uses its HTTP methods for communication.

@module koplugin.miniflux.api.entries
--]] --

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

---Build navigation query parameters
---@param entry_id number The reference entry ID
---@param direction string Either "before" or "after"
---@param options? ApiOptions Additional query options
---@return table Query parameters table
local function buildNavigationParams(entry_id, direction, options)
    local params = {}

    -- Add navigation parameter
    if direction == "before" then
        params.before_entry_id = entry_id
    elseif direction == "after" then
        params.after_entry_id = entry_id
    end

    -- We only want 1 entry (the immediate previous/next)
    params.limit = 1

    -- Add other filter options if provided
    if options then
        if options.status then
            params.status = options.status
        end

        if options.order then
            params.order = options.order
        end

        if options.direction then
            params.direction = options.direction
        end

        if options.category_id then
            params.category_id = options.category_id
        end

        if options.feed_id then
            params.feed_id = options.feed_id
        end
    end

    return params
end

-- =============================================================================
-- ENTRY CRUD OPERATIONS
-- =============================================================================

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getEntries(options)
    local query_params = buildQueryParams(options)
    return self.api:get("/entries", { query = query_params })
end

---Get a single entry by ID
---@param entry_id number The entry ID
---@return boolean success, MinifluxEntry|string result_or_error
function Entries:getEntry(entry_id)
    return self.api:get("/entries/" .. tostring(entry_id))
end

---Get unread entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getUnreadEntries(options)
    options = options or {}
    options.status = { "unread" }
    return self:getEntries(options)
end

---Get read entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getReadEntries(options)
    options = options or {}
    options.status = { "read" }
    return self:getEntries(options)
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

---Mark multiple entries as read
---@param entry_ids number[] Array of entry IDs to mark as read
---@return boolean success, any result_or_error
function Entries:markMultipleAsRead(entry_ids)
    return markEntries(self.api, entry_ids, "read")
end

---Mark multiple entries as unread
---@param entry_ids number[] Array of entry IDs to mark as unread
---@return boolean success, any result_or_error
function Entries:markMultipleAsUnread(entry_ids)
    return markEntries(self.api, entry_ids, "unread")
end

---Toggle bookmark status of an entry
---@param entry_id number The entry ID to toggle bookmark
---@return boolean success, any result_or_error
function Entries:toggleBookmark(entry_id)
    return self.api:put("/entries/" .. tostring(entry_id) .. "/bookmark")
end

-- =============================================================================
-- ENTRY NAVIGATION
-- =============================================================================

---Get the entry before a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getPrevious(entry_id, options)
    local query_params = buildNavigationParams(entry_id, "before", options)
    return self.api:get("/entries", { query = query_params })
end

---Get the entry after a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getNext(entry_id, options)
    local query_params = buildNavigationParams(entry_id, "after", options)
    return self.api:get("/entries", { query = query_params })
end

return Entries
