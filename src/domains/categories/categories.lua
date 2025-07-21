local EventListener = require('ui/widget/eventlistener')
local CacheAdapter = require('shared/cache_adapter')
local logger = require('logger')

---Categories domain - handles all category-related operations
---@class Categories : EventListener
---@field miniflux Miniflux Parent plugin reference
---@field cache CacheAdapter Cache adapter for categories data
local Categories = EventListener:extend({})

---Initialize categories domain
function Categories:init()
    local miniflux = self.miniflux
    self.cache = CacheAdapter:new(miniflux.settings)
    logger.dbg('[Miniflux:Categories] Initialized')
end

---Get all categories with counts (cached)
---@param config? table Optional configuration with dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function Categories:getCategories(config)
    return self.cache:fetchWithCache('categories', {
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
---@param category_id number Category ID
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
---@param category_id number The category ID
---@return boolean success
function Categories:markAsRead(category_id)
    local _ = require('gettext')
    local Notification = require('utils/notification')

    -- Validate category ID
    if not category_id or type(category_id) ~= 'number' or category_id <= 0 then
        Notification:error(_('Invalid category ID'))
        return false
    end

    -- Call API with loading dialog
    local _result, err = self.miniflux.api:markCategoryAsRead(category_id, {
        dialogs = {
            loading = { text = _('Marking category as read...') },
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        local CollectionsQueue = require('utils/collections_queue')
        local queue = CollectionsQueue:new('category')
        queue:enqueue(category_id, 'mark_all_read')

        Notification:info(_('Category marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local CollectionsQueue = require('utils/collections_queue')
        local queue = CollectionsQueue:new('category')
        queue:remove(category_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        local MinifluxEvent = require('utils/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        Notification:success(_('Category marked as read'))
        return true
    end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

---@private
function Categories:shouldInvalidateCache(key)
    local invalidating_keys = {
        [self.miniflux.settings.Key.ORDER] = true,
        [self.miniflux.settings.Key.DIRECTION] = true,
        [self.miniflux.settings.Key.LIMIT] = true,
        [self.miniflux.settings.Key.HIDE_READ_ENTRIES] = true,
    }
    return invalidating_keys[key] == true
end

function Categories:onMinifluxSettingsChanged(payload)
    local key = payload.key

    if self:shouldInvalidateCache(key) then
        logger.info('[Miniflux:Categories] Invalidating cache due to setting change:', key)
        self.cache:clear()
    end
end

function Categories:onMinifluxCacheInvalidate()
    logger.info('[Miniflux:Categories] Cache invalidation event received')
    self.cache:clear()
end

return Categories
