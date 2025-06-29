--[[--
Entries Module

This module handles all entry-related operations. It receives a reference to the
main API client and uses its HTTP methods for communication.

@module koplugin.miniflux.api.entries
--]]



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
---@param config? APIClientConfig Configuration including optional dialogs
---@return boolean success, EntriesResponse|string result_or_error
function Entries:getEntries(options, config)
    config = config or {}

    -- Build request configuration
    local request_config = {
        query = options,
        dialogs = config.dialogs
    }

    return self.api:get("/entries", request_config)
end

-- =============================================================================
-- ENTRY MANAGEMENT
-- =============================================================================

---Update entry status for one or multiple entries
---@param entry_ids number|number[] Entry ID or array of entry IDs to update
---@param config? APIClientConfig Configuration with body containing status and dialogs
---@return boolean success, any result_or_error
function Entries:updateEntries(entry_ids, config)
    config = config or {}

    -- Convert single ID to array
    local ids_array = type(entry_ids) == "table" and entry_ids or { entry_ids }

    -- Start with entry_ids
    local request_body = { entry_ids = ids_array }

    -- Merge additional properties from config.body
    if config.body then
        for key, value in pairs(config.body) do
            request_body[key] = value
        end
    end

    return self.api:put("/entries", {
        body = request_body,
        dialogs = config.dialogs
    })
end

return Entries
