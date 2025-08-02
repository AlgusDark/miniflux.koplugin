local CollectionsQueue = require('features/sync/utils/collections_queue')
local Notification = require('shared/widgets/notification')
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
    -- Try API call through domain
    local _result, api_err = miniflux.feeds:markFeedAsRead(feed_id, {
        dialogs = {
            loading = { text = _('Marking feed as read...') },
        },
    })

    if api_err then
        -- API failed - use queue fallback for offline mode
        local queue = CollectionsQueue:new('feed')
        queue:enqueue(feed_id, 'mark_all_read')

        Notification:info(_('Feed marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local queue = CollectionsQueue:new('feed')
        queue:remove(feed_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        Notification:success(_('Feed marked as read'))
        return true
    end
end

---Mark category as read with offline fallback
---@param category_id number|string Category ID
---@param miniflux Miniflux Main plugin instance with domains
---@return boolean success
function BrowserMarkAsReadService.markCategoryAsRead(category_id, miniflux)
    -- Try API call through domain
    local _result, api_err = miniflux.categories:markCategoryAsRead(category_id, {
        dialogs = {
            loading = { text = _('Marking category as read...') },
        },
    })

    if api_err then
        -- API failed - use queue fallback for offline mode
        local queue = CollectionsQueue:new('category')
        queue:enqueue(category_id, 'mark_all_read')

        Notification:info(_('Category marked as read (will sync when online)'))
        return true -- Still successful from user perspective
    else
        -- API success - remove from queue since server is source of truth
        local queue = CollectionsQueue:new('category')
        queue:remove(category_id)

        -- Invalidate all caches IMMEDIATELY so counts update
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        Notification:success(_('Category marked as read'))
        return true
    end
end

return BrowserMarkAsReadService
