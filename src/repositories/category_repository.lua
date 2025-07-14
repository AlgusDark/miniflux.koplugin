local CachedRepository = require('src/repositories/cached_repository')

-- **Category Repository** - Data Access Layer
--
-- Handles all category-related data access and API interactions with caching support.
-- Provides a clean interface for category data without UI concerns.
---@class CategoryRepository
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field settings MinifluxSettings Settings instance
---@field cache CachedRepository Cache instance for category operations
local CategoryRepository = {}

---Create a new CategoryRepository instance
---@param deps {miniflux_api: MinifluxAPI, settings: MinifluxSettings} Dependencies table
---@return CategoryRepository
function CategoryRepository:new(deps)
    local obj = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
        cache = CachedRepository:new({
            settings = deps.settings,
            cache_prefix = 'miniflux_categories',
        }),
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get all categories with counts (cached)
---@param config? table Configuration with optional dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function CategoryRepository:getAll(config)
    local cache_key = self.cache:generateCacheKey('getAll')

    return self.cache:getCached(cache_key, {
        api_call = function()
            local categories, err = self.miniflux_api:getCategories(true, config) -- include counts
            if err then
                return nil, err
            end
            ---@cast categories -nil

            return categories, nil
        end,
        ttl = 120, -- 2 minutes TTL for categories with counts
    })
end

---Get categories count for initialization (uses cached categories)
---@param config? table Configuration with optional dialogs
---@return number|nil result, Error|nil error
function CategoryRepository:getCount(config)
    local categories, err = self:getAll(config)
    if err then
        return nil, err
    end

    return #categories, nil
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function CategoryRepository:markAsRead(category_id, config)
    return self.miniflux_api:markCategoryAsRead(category_id, config)
end

---Invalidate all category cache (useful when categories are added/removed)
---@return boolean success
function CategoryRepository:invalidateCache()
    return self.cache:invalidateAll()
end

return CategoryRepository
