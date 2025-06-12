--[[--
Query Builder Utility for Miniflux API

This utility module handles the construction of query parameters and query strings
for API requests, eliminating duplication across API modules.

@module koplugin.miniflux.api.utils.query_builder
--]]--

local QueryBuilder = {}

---Build query parameters from options
---@param options? ApiOptions Query options for filtering and sorting
---@return string[] Array of query parameter strings
function QueryBuilder.buildParams(options)
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

    return params
end

---Build query string from parameters
---@param params string[] Array of query parameter strings
---@return string Query string (with leading ? if non-empty)
function QueryBuilder.buildQueryString(params)
    if #params > 0 then
        return "?" .. table.concat(params, "&")
    end
    return ""
end

---Build complete query string from options
---@param options? ApiOptions Query options for filtering and sorting
---@return string Query string (with leading ? if non-empty)
function QueryBuilder.buildFromOptions(options)
    local params = QueryBuilder.buildParams(options)
    return QueryBuilder.buildQueryString(params)
end

---Build navigation query parameters (for previous/next entry)
---@param entry_id number The reference entry ID
---@param direction string Either "before" or "after"
---@param options? ApiOptions Additional query options
---@return string Query string (with leading ? if non-empty)
function QueryBuilder.buildNavigationQuery(entry_id, direction, options)
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
    end
    
    return QueryBuilder.buildQueryString(params)
end

---Build starred entries query parameters
---@param options? ApiOptions Query options for filtering and sorting
---@return string Query string (with leading ? if non-empty)
function QueryBuilder.buildStarredQuery(options)
    local params = QueryBuilder.buildParams(options)
    -- Add starred filter
    table.insert(params, "starred=true")
    return QueryBuilder.buildQueryString(params)
end

return QueryBuilder 