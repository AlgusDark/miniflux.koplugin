--[[--
Category Repository - Data Access Layer

Handles all category-related data access and API interactions.
Provides a clean interface for category data without UI concerns.

@module miniflux.browser.repositories.category_repository
--]]

---@class CategoryRepository
---@field api MinifluxAPI API client instance
---@field settings MinifluxSettings Settings instance
local CategoryRepository = {}

---Create a new CategoryRepository instance
---@param api MinifluxAPI The API client instance
---@param settings MinifluxSettings The settings instance
---@return CategoryRepository
function CategoryRepository:new(api, settings)
    local obj = {
        api = api,
        settings = settings,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- CATEGORY DATA ACCESS
-- =============================================================================

---Get all categories with counts
---@param config? table Configuration with optional dialogs
---@return table[]|nil categories Array of categories or nil on error
---@return string|nil error Error message if failed
function CategoryRepository:getAll(config)
    local success, categories = self.api.categories:getAll(true, config) -- include counts
    if not success then
        return nil, categories
    end

    return categories, nil
end

---Get categories count for initialization
---@param config? table Configuration with optional dialogs
---@return number count Count of categories (0 if failed)
function CategoryRepository:getCount(config)
    local categories, error_msg = self:getAll(config)
    if not categories then
        return 0 -- Continue with 0 categories instead of failing
    end

    return #categories
end

return CategoryRepository
