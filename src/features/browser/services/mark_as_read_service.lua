local CollectionsQueue = require('features/sync/utils/collections_queue')
local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local MinifluxEvent = require('shared/event')
local _ = require('gettext')

---Browser Mark As Read Service - Handles mark as read operations for browser views
---This service orchestrates mark as read operations with offline fallback for browser UI
---@class BrowserMarkAsReadService
local BrowserMarkAsReadService = {}

---Mark feed as read with offline fallback
---@param feed_id number|string Feed ID
---@param miniflux Miniflux Main plugin instance with domains
---@return boolean success
function BrowserMarkAsReadService.markFeedAsRead(feed_id, miniflux)
    -- Show loading message with forceRePaint before API call
    local loading_widget = InfoMessage:new({
        text = _('Marking feed as read...'),
    })
    UIManager:show(loading_widget)
    UIManager:forceRePaint()

    -- Try API call through domain
    local _result, api_err = miniflux.feeds:markFeedAsRead(feed_id, {})

    -- Close loading message
    UIManager:close(loading_widget)

    if api_err then
        -- API failed - use queue fallback for offline mode
        local queue = CollectionsQueue:new('feed')
        queue:enqueue(feed_id, 'mark_all_read')

        UIManager:show(InfoMessage:new({
            text = _('Feed marked as read (will sync when online)'),
        }))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local queue = CollectionsQueue:new('feed')
        queue:remove(feed_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        UIManager:show(InfoMessage:new({
            text = _('Feed marked as read'),
            timeout = 2,
        }))
        return true
    end
end

---Mark category as read with offline fallback
---@param category_id number|string Category ID
---@param miniflux Miniflux Main plugin instance with domains
---@return boolean success
function BrowserMarkAsReadService.markCategoryAsRead(category_id, miniflux)
    -- Show loading message with forceRePaint before API call
    local loading_widget = InfoMessage:new({
        text = _('Marking category as read...'),
    })
    UIManager:show(loading_widget)
    UIManager:forceRePaint()

    -- Try API call through domain
    local _result, api_err = miniflux.categories:markCategoryAsRead(category_id, {})

    -- Close loading message
    UIManager:close(loading_widget)

    if api_err then
        -- API failed - use queue fallback for offline mode
        local queue = CollectionsQueue:new('category')
        queue:enqueue(category_id, 'mark_all_read')

        UIManager:show(InfoMessage:new({
            text = _('Category marked as read (will sync when online)'),
        }))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local queue = CollectionsQueue:new('category')
        queue:remove(category_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        UIManager:show(InfoMessage:new({
            text = _('Category marked as read'),
            timeout = 2,
        }))
        return true
    end
end

return BrowserMarkAsReadService
