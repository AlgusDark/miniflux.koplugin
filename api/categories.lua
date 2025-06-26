--[[--
Categories Module

This module handles all category-related operations including category listing,
category entries retrieval, and category management.

@module koplugin.miniflux.api.categories
--]]



---@class MinifluxCategory
---@field id number Category ID
---@field title string Category title
---@field total_unread? number Total unread entries in category

---@class Categories
---@field api MinifluxAPI Reference to the main API client
local Categories = {}

---Create a new categories module instance
---@param api MinifluxAPI The main API client instance
---@return Categories
function Categories:new(api)
    local o = {
        api = api,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- =============================================================================
-- OPERATIONS
-- =============================================================================

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@param config? APIClientConfig Configuration with optional query, dialogs
---@return boolean success, MinifluxCategory[]|string result_or_error
function Categories:getAll(include_counts, config)
    config = config or {}
    local query_params = {}
    if include_counts then
        query_params.counts = "true"
    end

    -- Build request configuration
    local request_config = {
        query = query_params,
        dialogs = config.dialogs
    }

    return self.api:get("/categories", request_config)
end

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@param config? APIClientConfig Configuration including optional dialogs
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getEntries(category_id, options, config)
    config = config or {}
    local endpoint = "/categories/" .. tostring(category_id) .. "/entries"

    -- Build request configuration
    local request_config = {
        query = options,
        dialogs = config.dialogs
    }

    return self.api:get(endpoint, request_config)
end

return Categories
