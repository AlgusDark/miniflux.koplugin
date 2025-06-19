--[[--
Consolidated Utils Module

This utility module combines query building and request helpers into a single
module to eliminate duplication and simplify the API structure.

@module koplugin.miniflux.api.utils
--]] --

local Utils = {}

-- =============================================================================
-- QUERY BUILDER FUNCTIONS
-- =============================================================================

---Build query parameters from options
---@param options? ApiOptions Query options for filtering and sorting
---@return string[] Array of query parameter strings
function Utils.buildParams(options)
    if not options then
        return {}
    end

    local params = {}

    if options.limit then
        table.insert(params, "limit=" .. tostring(options.limit))
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    if options.status then
        -- Handle status array
        local status_array = options.status ---@type EntryStatus[]
        for _, status in ipairs(status_array) do
            table.insert(params, "status=" .. status)
        end
    end

    -- Add category filter if provided
    if options.category_id then
        table.insert(params, "category_id=" .. tostring(options.category_id))
    end

    -- Add feed filter if provided
    if options.feed_id then
        table.insert(params, "feed_id=" .. tostring(options.feed_id))
    end

    -- Add starred filter if provided
    if options.starred then
        table.insert(params, "starred=true")
    end

    -- Add published_before filter if provided
    if options.published_before then
        table.insert(params, "published_before=" .. tostring(options.published_before))
    end

    -- Add published_after filter if provided
    if options.published_after then
        table.insert(params, "published_after=" .. tostring(options.published_after))
    end

    return params
end

---Build query string from parameters
---@param params string[] Array of query parameter strings
---@return string Query string (with leading ? if non-empty)
function Utils.buildQueryString(params)
    if #params > 0 then
        return "?" .. table.concat(params, "&")
    end
    return ""
end

---Build complete query string from options
---@param options? ApiOptions Query options for filtering and sorting
---@return string Query string (with leading ? if non-empty)
function Utils.buildFromOptions(options)
    local params = Utils.buildParams(options)
    return Utils.buildQueryString(params)
end

---Build navigation query parameters (for previous/next entry)
---@param entry_id number The reference entry ID
---@param direction string Either "before" or "after"
---@param options? ApiOptions Additional query options
---@return string Query string (with leading ? if non-empty)
function Utils.buildNavigationQuery(entry_id, direction, options)
    local params = {}

    -- Add navigation parameter
    if direction == "before" then
        table.insert(params, "before_entry_id=" .. tostring(entry_id))
    elseif direction == "after" then
        table.insert(params, "after_entry_id=" .. tostring(entry_id))
    end

    -- We only want 1 entry (the immediate previous/next)
    table.insert(params, "limit=1")

    -- Add other filter options if provided
    if options then
        if options.status then
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        end

        if options.order then
            table.insert(params, "order=" .. options.order)
        end

        if options.direction then
            table.insert(params, "direction=" .. options.direction)
        end

        -- Add category filter if provided
        if options.category_id then
            table.insert(params, "category_id=" .. tostring(options.category_id))
        end

        -- Add feed filter if provided
        if options.feed_id then
            table.insert(params, "feed_id=" .. tostring(options.feed_id))
        end

        -- Add starred filter if provided
        if options.starred then
            table.insert(params, "starred=true")
        end
    end

    return Utils.buildQueryString(params)
end

-- =============================================================================
-- REQUEST HELPER FUNCTIONS
-- =============================================================================

---Make a simple GET request
---@param api MinifluxAPI API client instance
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function Utils.get(api, endpoint)
    return api:makeRequest("GET", endpoint)
end

---Make a simple PUT request
---@param api MinifluxAPI API client instance
---@param endpoint string API endpoint path
---@param body? table Request body
---@return boolean success, any result_or_error
function Utils.put(api, endpoint, body)
    return api:makeRequest("PUT", endpoint, body)
end

---Make a simple POST request
---@param api MinifluxAPI API client instance
---@param endpoint string API endpoint path
---@param body? table Request body
---@return boolean success, any result_or_error
function Utils.post(api, endpoint, body)
    return api:makeRequest("POST", endpoint, body)
end

---Make a simple DELETE request
---@param api MinifluxAPI API client instance
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function Utils.delete(api, endpoint)
    return api:makeRequest("DELETE", endpoint)
end

---Get entries with query options
---@param api MinifluxAPI API client instance
---@param base_endpoint string Base endpoint path
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Utils.getEntriesWithOptions(api, base_endpoint, options)
    local query_string = Utils.buildFromOptions(options)
    local endpoint = base_endpoint .. query_string
    return api:makeRequest("GET", endpoint)
end

---Get resource by ID
---@param api MinifluxAPI API client instance
---@param base_endpoint string Base endpoint path (e.g., "/entries", "/feeds")
---@param resource_id number Resource ID
---@return boolean success, any result_or_error
function Utils.getById(api, base_endpoint, resource_id)
    local endpoint = base_endpoint .. "/" .. tostring(resource_id)
    return api:makeRequest("GET", endpoint)
end

---Mark entries with status
---@param api MinifluxAPI API client instance
---@param entry_ids number|number[] Entry ID or array of entry IDs
---@param status EntryStatus New status for entries
---@return boolean success, any result_or_error
function Utils.markEntries(api, entry_ids, status)
    local ids_array = type(entry_ids) == "table" and entry_ids or { entry_ids }
    local body = {
        entry_ids = ids_array,
        status = status,
    }
    return api:makeRequest("PUT", "/entries", body)
end

---Get entries for a resource (feed or category) with options
---@param api MinifluxAPI API client instance
---@param resource_type string Resource type ("feeds" or "categories")
---@param resource_id number Resource ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Utils.getResourceEntries(api, resource_type, resource_id, options)
    local base_endpoint = "/" .. resource_type .. "/" .. tostring(resource_id) .. "/entries"
    return Utils.getEntriesWithOptions(api, base_endpoint, options)
end

---Get resource entries by status (convenience method)
---@param api MinifluxAPI API client instance
---@param resource_type string Resource type ("feeds" or "categories")
---@param resource_id number Resource ID
---@param status EntryStatus[] Status filter
---@param options? ApiOptions Additional query options
---@return boolean success, EntriesResponse|string result_or_error
function Utils.getResourceEntriesByStatus(api, resource_type, resource_id, status, options)
    options = options or {}
    options.status = status
    return Utils.getResourceEntries(api, resource_type, resource_id, options)
end

---Mark all entries in a resource as read
---@param api MinifluxAPI API client instance
---@param resource_type string Resource type ("feeds" or "categories")
---@param resource_id number Resource ID
---@return boolean success, any result_or_error
function Utils.markResourceAsRead(api, resource_type, resource_id)
    local endpoint = "/" .. resource_type .. "/" .. tostring(resource_id) .. "/mark-all-as-read"
    return api:makeRequest("PUT", endpoint)
end

return Utils
