local _ = require('gettext')
local Notification = require('utils/notification')

-- **Collection Service** - Handles feed and category workflows and orchestration.
--
-- Service layer for collection operations using proper repository pattern.
-- Provides business logic for feeds and categories, delegates data access to repository.
-- Handles UI notifications, error handling, and offline queue management.
---@class CollectionService
---@field settings MinifluxSettings Settings instance
---@field data_repository DataRepository Data access layer
---@field miniflux_api MinifluxAPI API client for direct operations (mark as read, etc.)
local CollectionService = {}

---@class CollectionServiceDeps
---@field settings MinifluxSettings
---@field data_repository DataRepository
---@field miniflux_api MinifluxAPI

---Create a new CollectionService instance
---@param deps CollectionServiceDeps Dependencies containing settings, repository, and API
---@return CollectionService
function CollectionService:new(deps)
    local instance = {
        settings = deps.settings,
        data_repository = deps.data_repository,
        miniflux_api = deps.miniflux_api,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- DATA ACCESS OPERATIONS (delegate to repository)
-- =============================================================================

---Get feeds with counters for feeds view
---@param config? table Optional configuration with dialogs
---@return {feeds: MinifluxFeed[], counters: MinifluxFeedCounters}|nil result, Error|nil error
function CollectionService:getFeedsWithCounters(config)
    return self.data_repository:getFeedsWithCounters(config)
end

---Get feeds count for navigation
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function CollectionService:getFeedCount(config)
    return self.data_repository:getFeedCount(config)
end

---Get categories for categories view
---@param config? table Optional configuration with dialogs
---@return MinifluxCategory[]|nil categories, Error|nil error
function CollectionService:getCategories(config)
    return self.data_repository:getCategories(config)
end

---Get categories count for navigation
---@param config? table Optional configuration
---@return number|nil count, Error|nil error
function CollectionService:getCategoryCount(config)
    return self.data_repository:getCategoryCount(config)
end

---Get all collections counts for main view in a single call
---@param config? table Optional configuration
---@return {unread_count: number, feeds_count: number, categories_count: number}|nil counts, Error|nil error
function CollectionService:getCollectionsCounts(config)
    return self.data_repository:getCollectionsCounts(config)
end

-- =============================================================================
-- BUSINESS OPERATIONS (workflows and orchestration)
-- =============================================================================

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
        MinifluxEvent:broadcastMinifluxInvalidateCache()

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
