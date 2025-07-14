local _ = require('gettext')
local Notification = require('utils/notification')

-- **Category Service** - Handles category workflows and orchestration.
--
-- Coordinates between the Category repository and infrastructure services
-- to provide high-level category operations including notifications and
-- cache management.
---@class CategoryService
---@field settings MinifluxSettings Settings instance
---@field category_repository CategoryRepository Category repository instance
---@field feed_repository FeedRepository Feed repository for cross-invalidation
local CategoryService = {}

---@class CategoryServiceDeps
---@field category_repository CategoryRepository
---@field feed_repository FeedRepository
---@field settings MinifluxSettings

---Create a new CategoryService instance
---@param deps CategoryServiceDeps Dependencies containing repositories and settings
---@return CategoryService
function CategoryService:new(deps)
    local instance = {
        settings = deps.settings,
        category_repository = deps.category_repository,
        feed_repository = deps.feed_repository,
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
    local _result, err = self.category_repository:markAsRead(category_id, {
        dialogs = {
            loading = { text = progress_message },
            -- Note: No success/error dialogs - we handle both cases gracefully
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        local CategoryQueue = require('utils/category_queue')
        CategoryQueue.enqueue(category_id, 'mark_all_read')

        -- Show offline message instead of error
        Notification:info(_('Category marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local CategoryQueue = require('utils/category_queue')
        CategoryQueue.remove(category_id)

        -- Invalidate both category and feed caches IMMEDIATELY so counts update
        self.category_repository:invalidateCache()
        self.feed_repository:invalidateCache()

        -- Show simple success notification (no dialog)
        Notification:success(success_message)
        return true
    end
end

return CategoryService
