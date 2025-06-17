--[[--
Categories Module

This module handles all category-related operations including category listing,
category entries retrieval, and category management.

@module koplugin.miniflux.api.categories
--]]--

local Utils = require("api/utils")

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
-- CATEGORY OPERATIONS
-- =============================================================================

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function Categories:getCategories(include_counts)
    local endpoint = "/categories"
    if include_counts then
        endpoint = endpoint .. "?counts=true"
    end
    return Utils.get(self.api, endpoint)
end

---Get a specific category by ID
---@param category_id number The category ID
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:getCategory(category_id)
    return Utils.getById(self.api, "/categories", category_id)
end

---Get feeds in a specific category
---@param category_id number The category ID
---@return boolean success, MinifluxFeed[]|string result_or_error
function Categories:getFeeds(category_id)
    return Utils.get(self.api, "/categories/" .. tostring(category_id) .. "/feeds")
end

-- =============================================================================
-- CATEGORY ENTRIES OPERATIONS
-- =============================================================================

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getEntries(category_id, options)
    return Utils.getResourceEntries(self.api, "categories", category_id, options)
end

---Get unread entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getUnreadEntries(category_id, options)
    return Utils.getResourceEntriesByStatus(self.api, "categories", category_id, {"unread"}, options)
end

---Get read entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getReadEntries(category_id, options)
    return Utils.getResourceEntriesByStatus(self.api, "categories", category_id, {"read"}, options)
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:markAsRead(category_id)
    return Utils.markResourceAsRead(self.api, "categories", category_id)
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
    return Utils.post(self.api, "/categories", body)
end

---Update a category
---@param category_id number The category ID
---@param title string The new category title
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:update(category_id, title)
    local body = {
        title = title
    }
    return Utils.put(self.api, "/categories/" .. tostring(category_id), body)
end

---Delete a category
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:delete(category_id)
    return Utils.delete(self.api, "/categories/" .. tostring(category_id))
end

-- =============================================================================
-- BACKWARD COMPATIBILITY METHODS
-- These methods provide compatibility with the old API structure
-- =============================================================================

---Get all categories (compatibility alias)
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function Categories:get(include_counts)
    return self:getCategories(include_counts)
end

---Get category entries (compatibility alias)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getCategoryEntries(category_id, options)
    return self:getEntries(category_id, options)
end

---Get unread category entries (compatibility alias)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getCategoryUnreadEntries(category_id, options)
    return self:getUnreadEntries(category_id, options)
end

---Get read category entries (compatibility alias)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function Categories:getCategoryReadEntries(category_id, options)
    return self:getReadEntries(category_id, options)
end

---Mark category as read (compatibility alias)
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:markCategoryAsRead(category_id)
    return self:markAsRead(category_id)
end

---Get category feeds (compatibility alias)
---@param category_id number The category ID
---@return boolean success, MinifluxFeed[]|string result_or_error
function Categories:getCategoryFeeds(category_id)
    return self:getFeeds(category_id)
end

---Create category (compatibility alias)
---@param title string The category title
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:createCategory(title)
    return self:create(title)
end

---Update category (compatibility alias)
---@param category_id number The category ID
---@param title string The new category title
---@return boolean success, MinifluxCategory|string result_or_error
function Categories:updateCategory(category_id, title)
    return self:update(category_id, title)
end

---Delete category (compatibility alias)
---@param category_id number The category ID
---@return boolean success, any result_or_error
function Categories:deleteCategory(category_id)
    return self:delete(category_id)
end

return Categories 