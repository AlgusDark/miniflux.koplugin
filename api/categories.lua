--[[--
Categories Module

This module handles all category-related operations including category listing,
category entries retrieval, and category management.

@module koplugin.miniflux.api.categories
--]] --

---@class Categories
---@field api MinifluxAPI Reference to the main API client
local Categories = {}

---Create a new categories module instance
---@param api MinifluxAPI The main API client instance
---@return Categories
function Categories:new(api)
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

    if options.starred then
        params.starred = "true"
    end

    if options.published_before then
        params.published_before = options.published_before
    end

    if options.published_after then
        params.published_after = options.published_after
    end

    return params
end

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function Categories:getAll(include_counts)
    local query_params = {}
    if include_counts then
        query_params.counts = "true"
    end
    return self.api:get("/categories", { query = query_params })
end

-- =============================================================================
-- CATEGORY ENTRIES OPERATIONS
-- =============================================================================

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getEntries(category_id, options)
    local query_params = buildQueryParams(options)
    local endpoint = "/categories/" .. tostring(category_id) .. "/entries"
    return self.api:get(endpoint, { query = query_params })
end

---Get unread entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getUnreadEntries(category_id, options)
    options = options or {}
    options.status = { "unread" }
    return self:getEntries(category_id, options)
end

---Get read entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getReadEntries(category_id, options)
    options = options or {}
    options.status = { "read" }
    return self:getEntries(category_id, options)
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:markAsRead(category_id)
    local endpoint = "/categories/" .. tostring(category_id) .. "/mark-all-as-read"
    return self.api:put(endpoint)
end

-- =============================================================================
-- CATEGORY MANAGEMENT OPERATIONS
-- =============================================================================

---Create a new category
---@param title string The category title
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:create(title)
    local body = {
        title = title
    }
    return self.api:post("/categories", { body = body })
end

---Update a category
---@param category_id number The category ID
---@param title string The new category title
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:update(category_id, title)
    local body = {
        title = title
    }
    local endpoint = "/categories/" .. tostring(category_id)
    return self.api:put(endpoint, { body = body })
end

---Delete a category
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:delete(category_id)
    local endpoint = "/categories/" .. tostring(category_id)
    return self.api:delete(endpoint)
end

return Categories
