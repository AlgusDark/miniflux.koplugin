local _ = require('gettext')
local Notification = require('utils/notification')

-- **Collection Service** - Handles feed and category workflows and orchestration.
--
-- Unified service that coordinates between collections (feeds/categories) and infrastructure services
-- to provide high-level collection operations including notifications and cache management.
--
-- Replaces the duplicate FeedService and CategoryService with a single parameterized implementation.
---@class CollectionService
---@field settings MinifluxSettings Settings instance
---@field miniflux_api MinifluxAPI API client for collection operations
local CollectionService = {}

---@class CollectionServiceDeps
---@field settings MinifluxSettings
---@field miniflux_api MinifluxAPI

---Create a new CollectionService instance
---@param deps CollectionServiceDeps Dependencies containing settings and API
---@return CollectionService
function CollectionService:new(deps)
    local instance = {
        settings = deps.settings,
        miniflux_api = deps.miniflux_api,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Mark all entries in a collection (feed or category) as read
---@param collection_type string Type of collection ('feed' or 'category')
---@param collection_id number The collection ID (feed_id or category_id)
---@return boolean success
function CollectionService:markAsRead(collection_type, collection_id)
    -- Validate collection type
    if collection_type ~= 'feed' and collection_type ~= 'category' then
        error('Invalid collection_type: must be "feed" or "category"')
    end

    -- Validate collection ID
    if not collection_id or type(collection_id) ~= 'number' or collection_id <= 0 then
        local error_msg = collection_type == 'feed' and _('Invalid feed ID')
            or _('Invalid category ID')
        Notification:error(error_msg)
        return false
    end

    -- Configure messages based on collection type
    local progress_message, success_message, _error_message
    if collection_type == 'feed' then
        progress_message = _('Marking feed as read...')
        success_message = _('Feed marked as read')
        _error_message = _('Failed to mark feed as read')
    else -- category
        progress_message = _('Marking category as read...')
        success_message = _('Category marked as read')
        _error_message = _('Failed to mark category as read')
    end

    -- Call appropriate API method
    local _result, err
    if collection_type == 'feed' then
        _result, err = self.miniflux_api:markFeedAsRead(collection_id, {
            dialogs = {
                loading = { text = progress_message },
                -- Note: No success/error dialogs - we handle both cases gracefully
            },
        })
    else -- category
        _result, err = self.miniflux_api:markCategoryAsRead(collection_id, {
            dialogs = {
                loading = { text = progress_message },
                -- Note: No success/error dialogs - we handle both cases gracefully
            },
        })
    end

    if err then
        -- API failed - use queue fallback for offline mode
        local CollectionsQueue = require('utils/collections_queue')
        local queue = CollectionsQueue:new(collection_type)
        queue:enqueue(collection_id, 'mark_all_read')

        -- Show offline message instead of error
        local offline_message = collection_type == 'feed'
                and _('Feed marked as read (will sync when online)')
            or _('Category marked as read (will sync when online)')
        Notification:info(offline_message)
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local CollectionsQueue = require('utils/collections_queue')
        local queue = CollectionsQueue:new(collection_type)
        queue:remove(collection_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        local MinifluxEvent = require('utils/event')
        MinifluxEvent.broadcastEvent('MinifluxCacheInvalidate', {})

        -- Show simple success notification (no dialog)
        Notification:success(success_message)
        return true
    end
end

---Mark all entries in a feed as read (convenience method)
---@param feed_id number The feed ID
---@return boolean success
function CollectionService:markFeedAsRead(feed_id)
    return self:markAsRead('feed', feed_id)
end

---Mark all entries in a category as read (convenience method)
---@param category_id number The category ID
---@return boolean success
function CollectionService:markCategoryAsRead(category_id)
    return self:markAsRead('category', category_id)
end

return CollectionService
