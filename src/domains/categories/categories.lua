local EventListener = require('ui/widget/eventlistener')
local logger = require('logger')

---Categories domain - handles all category-related operations
---@class Categories : EventListener
---@field miniflux Miniflux Parent plugin reference
---@field http_cache HTTPCacheAdapter HTTP cache adapter for categories data
local Categories = EventListener:extend({})

---Initialize categories domain
function Categories:init()
    logger.dbg('[Miniflux:Categories] Initialized')
end

---Get all categories with counts (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function Categories:getCategories(config)
    return self.http_cache:fetchWithCache('categories', {
        ttl = self.miniflux.settings.api_cache_ttl_categories,
        fetcher = function()
            return self.miniflux.api:getCategories(true, config) -- include counts
        end,
    })
end

---Get category count (uses cached categories)
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function Categories:getCategoryCount(config)
    local categories, err = self:getCategories(config)
    if err then
        return nil, err
    end
    return #categories, nil
end

---Get entries by category (NOT cached - preserves current behavior)
---@param category_id number|string Category ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function Categories:getEntriesByCategory(category_id, config)
    local options = {
        category_id = category_id,
        order = self.miniflux.settings.order,
        direction = self.miniflux.settings.direction,
        limit = self.miniflux.settings.limit,
        status = self.miniflux.settings.hide_read_entries and { 'unread' } or { 'unread', 'read' },
    }

    local result, err = self.miniflux.api:getCategoryEntries(category_id, options, config)
    if err then
        return nil, err
    end
    ---@cast result -nil

    return result.entries or {}, nil
end

---Mark all entries in a category as read
---@param category_id number|string The category ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function Categories:markCategoryAsRead(category_id, config)
    -- Simple validation - accept string or number
    if not category_id then
        local Error = require('shared/error')
        local _ = require('gettext')
        return nil, Error.new(_('Category ID is required'))
    end

    return self.miniflux.api:markCategoryAsRead(category_id, config)
end

return Categories
