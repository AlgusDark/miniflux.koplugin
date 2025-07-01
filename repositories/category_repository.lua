--[[--
Category Repository - Data Access Layer

Handles all category-related data access and API interactions.
Provides a clean interface for category data without UI concerns.

@module miniflux.browser.repositories.category_repository
--]]

local Error = require("utils/error")

---@class CategoryRepository
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field settings MinifluxSettings Settings instance
local CategoryRepository = {}

---Create a new CategoryRepository instance
---@param deps {miniflux_api: MinifluxAPI, settings: MinifluxSettings} Dependencies table
---@return CategoryRepository
function CategoryRepository:new(deps)
    local obj = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
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
---@return MinifluxCategory[]|nil result, Error|nil error
function CategoryRepository:getAll(config)
    local categories, err = self.miniflux_api:getCategories(true, config) -- include counts
    if err then
        return nil, err
    end
    ---@cast categories -nil

    return categories, nil
end

---Get categories count for initialization
---@param config? table Configuration with optional dialogs
---@return number count Count of categories (0 if failed)
function CategoryRepository:getCount(config)
    local categories, err = self:getAll(config)
    if err then
        return 0 -- Continue with 0 categories instead of failing
    end

    return #categories
end

return CategoryRepository
