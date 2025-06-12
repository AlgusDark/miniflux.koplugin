--[[--
Categories API Module

This module handles all category-related operations including category listing,
category entries retrieval, and category management.

@module koplugin.miniflux.api.categories_api
--]]--

local RequestHelpers = require("api/utils/request_helpers")
local _ = require("gettext")

---@class CategoriesAPI
---@field client BaseClient Reference to the base HTTP client
local CategoriesAPI = {}

---Create a new categories API instance
---@param o? table Optional initialization table
---@return CategoriesAPI
function CategoriesAPI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the categories API with base client
---@param client BaseClient The base HTTP client instance
---@return CategoriesAPI self for method chaining
function CategoriesAPI:init(client)
    self.client = client
    return self
end

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function CategoriesAPI:getCategories(include_counts)
    local endpoint = "/categories"
    if include_counts then
        endpoint = endpoint .. "?counts=true"
    end
    return RequestHelpers.get(self.client, endpoint)
end

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function CategoriesAPI:getCategoryEntries(category_id, options)
    return RequestHelpers.getResourceEntries(self.client, "categories", category_id, options)
end

---Get a specific category by ID
---@param category_id number The category ID
---@return boolean success, MinifluxCategory|string result_or_error
function CategoriesAPI:getCategory(category_id)
    return RequestHelpers.getById(self.client, "/categories", category_id)
end

---Get unread entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function CategoriesAPI:getCategoryUnreadEntries(category_id, options)
    return RequestHelpers.getResourceEntriesByStatus(self.client, "categories", category_id, {"unread"}, options)
end

---Get read entries for a specific category (convenience method)
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function CategoriesAPI:getCategoryReadEntries(category_id, options)
    return RequestHelpers.getResourceEntriesByStatus(self.client, "categories", category_id, {"read"}, options)
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@return boolean success, any result_or_error
function CategoriesAPI:markCategoryAsRead(category_id)
    return RequestHelpers.markResourceAsRead(self.client, "categories", category_id)
end

---Get feeds in a specific category
---@param category_id number The category ID
---@return boolean success, MinifluxFeed[]|string result_or_error
function CategoriesAPI:getCategoryFeeds(category_id)
    return RequestHelpers.get(self.client, "/categories/" .. tostring(category_id) .. "/feeds")
end

---Create a new category
---@param title string The category title
---@return boolean success, MinifluxCategory|string result_or_error
function CategoriesAPI:createCategory(title)
    local body = {
        title = title
    }
    return RequestHelpers.post(self.client, "/categories", body)
end

---Update a category
---@param category_id number The category ID
---@param title string The new category title
---@return boolean success, MinifluxCategory|string result_or_error
function CategoriesAPI:updateCategory(category_id, title)
    local body = {
        title = title
    }
    return RequestHelpers.put(self.client, "/categories/" .. tostring(category_id), body)
end

---Delete a category
---@param category_id number The category ID
---@return boolean success, any result_or_error
function CategoriesAPI:deleteCategory(category_id)
    return RequestHelpers.delete(self.client, "/categories/" .. tostring(category_id))
end

return CategoriesAPI 