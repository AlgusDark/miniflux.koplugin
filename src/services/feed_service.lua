local _ = require('gettext')
local Notification = require('src/utils/notification')

-- **Feed Service** - Handles feed workflows and orchestration.
--
-- Coordinates between the Feed repository and infrastructure services
-- to provide high-level feed operations including notifications and
-- cache management.
---@class FeedService
---@field settings MinifluxSettings Settings instance
---@field feed_repository FeedRepository Feed repository instance
---@field category_repository CategoryRepository Category repository for cross-invalidation
local FeedService = {}

---@class FeedServiceDeps
---@field feed_repository FeedRepository
---@field category_repository CategoryRepository
---@field settings MinifluxSettings

---Create a new FeedService instance
---@param deps FeedServiceDeps Dependencies containing repositories and settings
---@return FeedService
function FeedService:new(deps)
    local instance = {
        settings = deps.settings,
        feed_repository = deps.feed_repository,
        category_repository = deps.category_repository,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@return boolean success
function FeedService:markAsRead(feed_id)
    if not feed_id or type(feed_id) ~= 'number' or feed_id <= 0 then
        Notification:error(_('Invalid feed ID'))
        return false
    end

    -- Show progress notification
    local progress_message = _('Marking feed as read...')
    local success_message = _('Feed marked as read')
    local _error_message = _('Failed to mark feed as read')

    -- Call API with dialog management
    local _result, err = self.feed_repository:markAsRead(feed_id, {
        dialogs = {
            loading = { text = progress_message },
            -- Note: No success/error dialogs - we handle both cases gracefully
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        local FeedQueue = require('src/utils/feed_queue')
        FeedQueue.enqueue(feed_id, 'mark_all_read')

        -- Show offline message instead of error
        Notification:info(_('Feed marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local FeedQueue = require('src/utils/feed_queue')
        FeedQueue.remove(feed_id)

        -- Invalidate both feed and category caches IMMEDIATELY so counts update
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()

        -- Show simple success notification (no dialog)
        Notification:success(success_message)
        return true
    end
end

return FeedService
