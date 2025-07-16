local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local UIManager = require('ui/uimanager')
local Notification = require('utils/notification')
local _ = require('gettext')
local logger = require('logger')

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
    local CollectionsQueue = require('utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    -- Count entry status queue
    local status_queue = self.entry_service:loadQueue()
    local status_count = 0
    for _ in pairs(status_queue) do
        status_count = status_count + 1
    end

    -- Count feed and category queues
    local feed_count = feed_queue:count()
    local category_count = category_queue:count()

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

    logger.info(
        '[Miniflux:QueueService] Processing queues:',
        status_count,
        'entries,',
        feed_count,
        'feeds,',
        category_count,
        'categories'
    )

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
        local processed, failed = self:processQueue('feed')
        total_processed = total_processed + processed
        total_failed = total_failed + failed
    end

    -- 3. Process category queue
    if opts.category_count > 0 then
        local processed, failed = self:processQueue('category')
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

---Process a queue (feed or category)
---@param queue_type string Type of queue ('feed' or 'category')
---@return number processed, number failed
function QueueService:processQueue(queue_type)
    local CollectionsQueue = require('utils/collections_queue')
    local queue_instance = CollectionsQueue:new(queue_type)
    local queue_data = queue_instance:load()
    local processed_count = 0
    local failed_count = 0

    for collection_id, opts in pairs(queue_data) do
        if opts and opts.operation == 'mark_all_read' and collection_id then
            local _, err
            if queue_type == 'feed' then
                _, err = self.miniflux_api:markFeedAsRead(collection_id)
            elseif queue_type == 'category' then
                _, err = self.miniflux_api:markCategoryAsRead(collection_id)
            end

            if not err then
                -- Success - remove from queue
                queue_instance:remove(collection_id)
                processed_count = processed_count + 1
            else
                logger.err(
                    '[Miniflux:QueueService] Failed to mark',
                    queue_type,
                    collection_id,
                    'as read:',
                    err.message or 'unknown error'
                )
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
    local CollectionsQueue = require('utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    local status_success = self.entry_service:clearStatusQueue()
    local feed_success = feed_queue:clear()
    local category_success = category_queue:clear()

    if status_success and feed_success and category_success then
        logger.info('[Miniflux:QueueService] All sync queues cleared')
        Notification:success(_('All sync queues cleared'))
        return true
    else
        -- Provide specific error details for debugging
        local failed_queues = {}
        if not status_success then
            table.insert(failed_queues, 'status')
        end
        if not feed_success then
            table.insert(failed_queues, 'feed')
        end
        if not category_success then
            table.insert(failed_queues, 'category')
        end

        local error_msg = _('Failed to clear queues: ') .. table.concat(failed_queues, ', ')
        logger.err(
            '[Miniflux:QueueService] Failed to clear queues:',
            table.concat(failed_queues, ', ')
        )
        Notification:error(error_msg)
        return false
    end
end

return QueueService
