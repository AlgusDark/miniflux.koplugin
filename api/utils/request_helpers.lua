--[[--
Request Helpers Utility for Miniflux API

This utility module provides common HTTP request patterns and helpers
to eliminate duplication across API modules.

@module koplugin.miniflux.api.utils.request_helpers
--]]--

local QueryBuilder = require("api/utils/query_builder")

local RequestHelpers = {}

---Make a simple GET request
---@param client BaseClient HTTP client instance
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function RequestHelpers.get(client, endpoint)
    return client:makeRequest("GET", endpoint)
end

---Make a simple PUT request
---@param client BaseClient HTTP client instance
---@param endpoint string API endpoint path
---@param body? table Request body
---@return boolean success, any result_or_error
function RequestHelpers.put(client, endpoint, body)
    return client:makeRequest("PUT", endpoint, body)
end

---Make a simple POST request
---@param client BaseClient HTTP client instance
---@param endpoint string API endpoint path
---@param body? table Request body
---@return boolean success, any result_or_error
function RequestHelpers.post(client, endpoint, body)
    return client:makeRequest("POST", endpoint, body)
end

---Make a simple DELETE request
---@param client BaseClient HTTP client instance
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function RequestHelpers.delete(client, endpoint)
    return client:makeRequest("DELETE", endpoint)
end

---Get entries with query options
---@param client BaseClient HTTP client instance
---@param base_endpoint string Base endpoint path
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function RequestHelpers.getEntriesWithOptions(client, base_endpoint, options)
    local query_string = QueryBuilder.buildFromOptions(options)
    local endpoint = base_endpoint .. query_string
    return client:makeRequest("GET", endpoint)
end

---Get resource by ID
---@param client BaseClient HTTP client instance
---@param base_endpoint string Base endpoint path (e.g., "/entries", "/feeds")
---@param resource_id number Resource ID
---@return boolean success, any result_or_error
function RequestHelpers.getById(client, base_endpoint, resource_id)
    local endpoint = base_endpoint .. "/" .. tostring(resource_id)
    return client:makeRequest("GET", endpoint)
end

---Mark entries with status
---@param client BaseClient HTTP client instance
---@param entry_ids number|number[] Entry ID or array of entry IDs
---@param status EntryStatus New status for entries
---@return boolean success, any result_or_error
function RequestHelpers.markEntries(client, entry_ids, status)
    local ids_array = type(entry_ids) == "table" and entry_ids or {entry_ids}
    local body = {
        entry_ids = ids_array,
        status = status,
    }
    return client:makeRequest("PUT", "/entries", body)
end

---Get entries for a resource (feed or category) with options
---@param client BaseClient HTTP client instance
---@param resource_type string Resource type ("feeds" or "categories")
---@param resource_id number Resource ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function RequestHelpers.getResourceEntries(client, resource_type, resource_id, options)
    local base_endpoint = "/" .. resource_type .. "/" .. tostring(resource_id) .. "/entries"
    return RequestHelpers.getEntriesWithOptions(client, base_endpoint, options)
end

---Create convenience methods that combine status filtering
---@param client BaseClient HTTP client instance
---@param resource_type string Resource type ("feeds" or "categories") 
---@param resource_id number Resource ID
---@param status EntryStatus[] Status filter
---@param options? ApiOptions Additional query options
---@return boolean success, EntriesResponse|string result_or_error
function RequestHelpers.getResourceEntriesByStatus(client, resource_type, resource_id, status, options)
    options = options or {}
    options.status = status
    return RequestHelpers.getResourceEntries(client, resource_type, resource_id, options)
end

---Mark all entries in a resource as read
---@param client BaseClient HTTP client instance
---@param resource_type string Resource type ("feeds" or "categories")
---@param resource_id number Resource ID
---@return boolean success, any result_or_error
function RequestHelpers.markResourceAsRead(client, resource_type, resource_id)
    local endpoint = "/" .. resource_type .. "/" .. tostring(resource_id) .. "/mark-all-as-read"
    return client:makeRequest("PUT", endpoint)
end

return RequestHelpers 