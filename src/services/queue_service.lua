local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local UIManager = require('ui/uimanager')
local Notification = require('src/utils/notification')
local _ = require('gettext')

---@class QueueService
---@field entry_service EntryService Reference to entry service for entry queue operations
---@field miniflux_api MinifluxAPI Reference to API client for feed/category operations
local QueueService = {}

---Create a new QueueService instance
---@param config table Configuration with entry_service and miniflux_api
---@return QueueService
function QueueService:new(config)
    local instance = {
        entry_service = config.entry_service,
        miniflux_api = config.miniflux_api,
    }
    setmetatable(instance, { __index = self })
    return instance
end

---Get total count across all queue types
---@return number total_count, number status_count, number feed_count, number category_count
function QueueService:getTotalQueueCount()
    local FeedQueue = require('src/utils/feed_queue')
    local CategoryQueue = require('src/utils/category_queue')

    -- Count entry status queue
    local status_queue = self.entry_service:loadQueue()
    local status_count = 0
    for i in pairs(status_queue) do
        status_count = status_count + 1
    end

    -- Count feed and category queues
    local feed_count = FeedQueue.count()
    local category_count = CategoryQueue.count()

    local total_count = status_count + feed_count + category_count
    return total_count, status_count, feed_count, category_count
end

---Show sync dialog or process queues based on queue state
---@return boolean success
function QueueService:processAllQueues()
    local total_count, status_count, feed_count, category_count = self:getTotalQueueCount()

    if total_count == 0 then
        Notification:info(_('All changes are already synced'))
        return true -- Nothing to process
    end

    -- Always show confirmation dialog for user interaction
    return self:showSyncConfirmationDialog(total_count, {
        entries_status_count = status_count,
        feed_count = feed_count,
        category_count = category_count,
    })
end

---Actually process all queues (called after user confirms)
---@param opts {entries_status_count: number, feed_count: number, category_count: number}
---@return boolean success
function QueueService:executeQueueProcessing(opts)
    -- Process all queue types
    local total_processed = 0
    local total_failed = 0

    -- 1. Process entry status queue (delegate to EntryService)
    if opts.entries_status_count > 0 then
        local entry_success = self.entry_service:processStatusQueue(true, true) -- auto_confirm = true, silent = true
        if entry_success then
            total_processed = total_processed + opts.entries_status_count
        else
            total_failed = total_failed + opts.entries_status_count
        end
    end

    -- 2. Process feed queue
    if opts.feed_count > 0 then
        local processed, failed = self:processFeedQueue()
        total_processed = total_processed + processed
        total_failed = total_failed + failed
    end

    -- 3. Process category queue
    if opts.category_count > 0 then
        local processed, failed = self:processCategoryQueue()
        total_processed = total_processed + processed
        total_failed = total_failed + failed
    end

    -- Show unified completion notification for all operations
    self:showCompletionNotification(total_processed, total_failed)

    return true
end

---Show sync confirmation dialog
---@param total_count number Total items to sync
---@param opts table Queue counts {entries_status_count, feed_count, category_count}
---@return boolean success (dialog shown)
function QueueService:showSyncConfirmationDialog(total_count, opts)
    local message = total_count == 1 and _('Sync 1 pending change?')
        or string.format(_('Sync %d pending changes?'), total_count)

    local confirm_dialog
    confirm_dialog = ButtonDialogTitle:new({
        title = message,
        title_align = 'center',
        buttons = {
            {
                {
                    text = _('Later'),
                    callback = function()
                        UIManager:close(confirm_dialog)
                    end,
                },
                {
                    text = _('Sync Now'),
                    callback = function()
                        UIManager:close(confirm_dialog)
                        self:executeQueueProcessing(opts)
                    end,
                },
            },
            {
                {
                    text = _('Delete Queue'),
                    callback = function()
                        UIManager:close(confirm_dialog)
                        self:clearAllQueues()
                    end,
                },
            },
        },
    })
    UIManager:show(confirm_dialog)
    return true -- Dialog shown, processing will happen async
end

---Process the feed queue
---@return number processed, number failed
function QueueService:processFeedQueue()
    local FeedQueue = require('src/utils/feed_queue')
    local feed_queue = FeedQueue.load()
    local processed_count = 0
    local failed_count = 0

    for feed_id, opts in pairs(feed_queue) do
        if opts and opts.operation == 'mark_all_read' and feed_id then
            local _result, err = self.miniflux_api:markFeedAsRead(feed_id)
            if not err then
                -- Success - remove from queue
                FeedQueue.remove(feed_id)
                processed_count = processed_count + 1
            else
                failed_count = failed_count + 1
            end
        end
    end

    return processed_count, failed_count
end

---Process the category queue
---@return number processed, number failed
function QueueService:processCategoryQueue()
    local CategoryQueue = require('src/utils/category_queue')
    local category_queue = CategoryQueue.load()
    local processed_count = 0
    local failed_count = 0

    for category_id, opts in pairs(category_queue) do
        if opts and opts.operation == 'mark_all_read' and category_id then
            local _result, err = self.miniflux_api:markCategoryAsRead(category_id)
            if not err then
                -- Success - remove from queue
                CategoryQueue.remove(category_id)
                processed_count = processed_count + 1
            else
                failed_count = failed_count + 1
            end
        end
    end

    return processed_count, failed_count
end

---Show completion notification for bulk operations
---@param processed_count number Number of successful operations
---@param failed_count number Number of failed operations
function QueueService:showCompletionNotification(processed_count, failed_count)
    if processed_count > 0 then
        local message = processed_count == 1 and _('1 change synced')
            or string.format(_('%d changes synced'), processed_count)

        if failed_count > 0 then
            message = message .. string.format(_(', %d failed'), failed_count)
        end

        Notification:success(message)
    elseif failed_count > 0 then
        local message = failed_count == 1 and _('1 change failed to sync')
            or string.format(_('%d changes failed to sync'), failed_count)
        Notification:error(message)
    end
end

---Clear all queue types
---@return boolean success
function QueueService:clearAllQueues()
    local FeedQueue = require('src/utils/feed_queue')
    local CategoryQueue = require('src/utils/category_queue')

    local status_success = self.entry_service:clearStatusQueue()
    local feed_success = FeedQueue.clear()
    local category_success = CategoryQueue.clear()

    if status_success and feed_success and category_success then
        Notification:success(_('All sync queues cleared'))
        return true
    else
        Notification:error(_('Failed to clear some sync queues'))
        return false
    end
end

return QueueService
