local _ = require('gettext')
local Notification = require('utils/notification')

-- **Category Service** - Handles category workflows and orchestration.
--
-- Coordinates between the Category repository and infrastructure services
-- to provide high-level category operations including notifications and
-- cache management.
---@class CategoryService
---@field settings MinifluxSettings Settings instance
---@field cache_service CacheService Cache service for data access and invalidation
---@field miniflux_api MinifluxAPI API client for category operations
local CategoryService = {}

---@class CategoryServiceDeps
---@field cache_service CacheService
---@field settings MinifluxSettings
---@field miniflux_api MinifluxAPI

---Create a new CategoryService instance
---@param deps CategoryServiceDeps Dependencies containing cache service and settings
---@return CategoryService
function CategoryService:new(deps)
    local instance = {
        settings = deps.settings,
        cache_service = deps.cache_service,
        miniflux_api = deps.miniflux_api,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@return boolean success
function CategoryService:markAsRead(category_id)
    if not category_id or type(category_id) ~= 'number' or category_id <= 0 then
        Notification:error(_('Invalid category ID'))
        return false
    end

    -- Show progress notification
    local progress_message = _('Marking category as read...')
    local success_message = _('Category marked as read')
    local _error_message = _('Failed to mark category as read')

    -- Call API with dialog management
    local _result, err = self.miniflux_api:markCategoryAsRead(category_id, {
        dialogs = {
            loading = { text = progress_message },
            -- Note: No success/error dialogs - we handle both cases gracefully
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        local CollectionsQueue = require('utils/collections_queue')
        local category_queue = CollectionsQueue:new('category')
        category_queue:enqueue(category_id, 'mark_all_read')

        -- Show offline message instead of error
        Notification:info(_('Category marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local CollectionsQueue = require('utils/collections_queue')
        local category_queue = CollectionsQueue:new('category')
        category_queue:remove(category_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        self.cache_service:invalidateAll()

        -- Show simple success notification (no dialog)
        Notification:success(success_message)
        return true
    end
end

return CategoryService
