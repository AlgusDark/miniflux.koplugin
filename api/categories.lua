--[[--
Categories Module

This module handles all category-related operations including category listing,
category entries retrieval, and category management.

@module koplugin.miniflux.api.categories
--]] --

local apiUtils = require("api/utils")

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
-- OPERATIONS
-- =============================================================================

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

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getEntries(category_id, options)
    local query_params = apiUtils.buildQueryParams(options)
    local endpoint = "/categories/" .. tostring(category_id) .. "/entries"
    return self.api:get(endpoint, { query = query_params })
end

return Categories
