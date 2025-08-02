local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local UIManager = require('ui/uimanager')
local Notification = require('shared/widgets/notification')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

local EntryPaths = require('domains/utils/entry_paths')
local EntryMetadata = require('domains/utils/entry_metadata')
local QueueService = require('features/sync/services/queue_service')
local ReaderUI = require('apps/reader/readerui')

---@class SyncService
---@field entries Entries Reference to entries domain for entry status operations
---@field feeds Feeds Reference to feeds domain for feed operations
---@field categories Categories Reference to categories domain for category operations
local SyncService = {}

---Create a new SyncService instance
---@param config table Configuration with entries, feeds, and categories
---@return SyncService
function SyncService:new(config)
    local instance = {
        entries = config.entries,
        feeds = config.feeds,
        categories = config.categories,
    }
    setmetatable(instance, { __index = self })
    return instance
end

---Show confirmation dialog before clearing the entry status queue
---@param queue_size number Number of entries in queue
function SyncService:confirmClearEntryStatusQueue(queue_size)
    local ConfirmBox = require('ui/widget/confirmbox')

    local message = T(
        _(
            'Are you sure you want to delete the sync queue?\n\nYou still have %1 entries that need to sync with the server.\n\nThis action cannot be undone.'
        ),
        queue_size
    )

    local confirm_dialog = ConfirmBox:new({
        text = message,
        ok_text = _('Delete Queue'),
        ok_callback = function()
            local success = QueueService.clearEntryStatusQueue()
            if success then
                Notification:info(_('Sync queue cleared'))
            else
                Notification:error(_('Failed to clear sync queue'))
            end
        end,
        cancel_text = _('Cancel'),
    })

    UIManager:show(confirm_dialog)
end

---Try to update entry status via API (helper for queue processing)
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function SyncService:tryUpdateEntryStatus(entry_id, new_status)
    -- Use existing API with minimal dialogs
    local _result, err = self.entries:updateEntries(entry_id, {
        body = { status = new_status },
        -- No dialogs for background queue processing
    })

    if not err then
        -- Check if this entry is currently open in ReaderUI for DocSettings sync
        local doc_settings = nil
        if ReaderUI.instance and ReaderUI.instance.document then
            local current_file = ReaderUI.instance.document.file
            if EntryPaths.isMinifluxEntry(current_file) then
                local current_entry_id = EntryPaths.extractEntryIdFromPath(current_file)
                if current_entry_id == entry_id then
                    doc_settings = ReaderUI.instance.doc_settings
                end
            end
        end

        EntryMetadata.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Remove from queue since server is now source of truth
        QueueService.removeFromEntryStatusQueue(entry_id)
        return true
    end

    return false
end

---Try to update multiple entries status via batch API (optimized for queue processing)
---@param entry_ids table Array of entry IDs
---@param new_status string New status ("read" or "unread')
---@return boolean success
function SyncService:tryBatchUpdateEntries(entry_ids, new_status)
    if not entry_ids or #entry_ids == 0 then
        return true -- No entries to process
    end

    -- Use existing batch API without dialogs for background processing
    local _result, err = self.entries:updateEntries(entry_ids, {
        body = { status = new_status },
        -- No dialogs for background queue processing
    })

    if not err then
        -- Check ReaderUI once for efficiency (instead of checking for each entry)
        local current_entry_id = nil
        local doc_settings = nil

        if ReaderUI.instance and ReaderUI.instance.document then
            local current_file = ReaderUI.instance.document.file
            if EntryPaths.isMinifluxEntry(current_file) then
                current_entry_id = EntryPaths.extractEntryIdFromPath(current_file)
                doc_settings = ReaderUI.instance.doc_settings
            end
        end

        -- Update local metadata for all entries on success (Miniflux returns 204 for success)
        for _, entry_id in ipairs(entry_ids) do
            -- Pass doc_settings only if this entry is currently open
            local entry_doc_settings = (entry_id == current_entry_id) and doc_settings or nil
            EntryMetadata.updateEntryStatus(
                entry_id,
                { new_status = new_status, doc_settings = entry_doc_settings }
            )
        end
        return true
    end

    return false
end

---Process the entry status queue when network is available (with user confirmation)
---@param auto_confirm? boolean Skip confirmation dialog if true
---@param silent? boolean Skip notifications if true
---@return boolean success
function SyncService:processEntryStatusQueue(auto_confirm, silent)
    logger.info(
        '[Miniflux:SyncService] Processing status queue, auto_confirm:',
        auto_confirm,
        'silent:',
        silent
    )

    local queue = QueueService.loadEntryStatusQueue()
    local queue_size = 0
    for _ in pairs(queue) do
        queue_size = queue_size + 1
    end

    logger.dbg('[Miniflux:SyncService] Queue size:', queue_size)

    if queue_size == 0 then
        -- Show friendly message only when manually triggered (auto_confirm is nil)
        if auto_confirm == nil then
            Notification:info(_('All changes are already synced'))
        end
        return true -- Nothing to process
    end

    -- Ask user for confirmation unless auto_confirm is true
    if not auto_confirm then
        local sync_dialog
        sync_dialog = ButtonDialogTitle:new({
            title = T(_('Sync %1 pending status changes?'), queue_size),
            title_align = 'center',
            buttons = {
                {
                    {
                        text = _('Later'),
                        callback = function()
                            UIManager:close(sync_dialog)
                        end,
                    },
                    {
                        text = _('Sync Now'),
                        callback = function()
                            UIManager:close(sync_dialog)
                            -- Process queue after dialog closes
                            UIManager:nextTick(function()
                                self:processEntryStatusQueue(true) -- auto_confirm = true
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _('Delete Queue'),
                        callback = function()
                            UIManager:close(sync_dialog)
                            -- Show confirmation dialog for destructive operation
                            UIManager:nextTick(function()
                                self:confirmClearEntryStatusQueue(queue_size)
                            end)
                        end,
                    },
                },
            },
        })
        UIManager:show(sync_dialog)
        return true -- Dialog shown, actual processing happens if user confirms
    end

    -- User confirmed, process queue with optimized batch API calls (max 2 calls)

    -- Group entries by target status (O(n) operation)
    local read_entries = {}
    local unread_entries = {}

    for entry_id, opts in pairs(queue) do
        if opts.new_status == 'read' then
            table.insert(read_entries, entry_id)
        elseif opts.new_status == 'unread' then
            table.insert(unread_entries, entry_id)
        end
    end

    local processed_count = 0
    local failed_count = 0
    local read_success = false
    local unread_success = false

    -- Process read entries in single batch API call
    if #read_entries > 0 then
        read_success = self:tryBatchUpdateEntries(read_entries, 'read')
        if read_success then
            processed_count = processed_count + #read_entries
        else
            failed_count = failed_count + #read_entries
        end
    else
        read_success = true -- No read entries to process
    end

    -- Process unread entries in single batch API call
    if #unread_entries > 0 then
        unread_success = self:tryBatchUpdateEntries(unread_entries, 'unread')
        if unread_success then
            processed_count = processed_count + #unread_entries
        else
            failed_count = failed_count + #unread_entries
        end
    else
        unread_success = true -- No unread entries to process
    end

    -- Efficient queue cleanup: if both operations succeeded, clear entire queue
    if read_success and unread_success then
        -- Both batch operations succeeded (204 status) - clear entire queue
        queue = {}
    else
        -- Some operations failed - remove only successful entries (O(n) operation)
        if read_success then
            for _, entry_id in ipairs(read_entries) do
                queue[entry_id] = nil
            end
        end
        if unread_success then
            for _, entry_id in ipairs(unread_entries) do
                queue[entry_id] = nil
            end
        end
    end

    -- Save updated queue
    QueueService.saveEntryStatusQueue(queue)

    -- Show completion notification only if not silent
    if not silent then
        if processed_count > 0 then
            local message = processed_count .. ' entries synced'
            if failed_count > 0 then
                message = message .. ', ' .. failed_count .. ' failed'
            end
            Notification:success(message)
        elseif failed_count > 0 then
            Notification:error('Failed to sync ' .. failed_count .. ' entries')
        end
    end

    return true
end

---Show sync dialog or process queues based on queue state
---@return boolean success
function SyncService:processAllQueues()
    local total_count, status_count, feed_count, category_count = QueueService.getTotalQueueCount()

    if total_count == 0 then
        Notification:info(_('All changes are already synced'))
        return true -- Nothing to process
    end

    logger.info(
        '[Miniflux:SyncService] Processing queues:',
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
function SyncService:executeQueueProcessing(opts)
    -- Process all queue types
    local total_processed = 0
    local total_failed = 0

    -- 1. Process entry status queue
    if opts.entries_status_count > 0 then
        local entry_success = self:processEntryStatusQueue(true, true) -- auto_confirm = true, silent = true
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
function SyncService:showSyncConfirmationDialog(total_count, opts)
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
function SyncService:processQueue(queue_type)
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local queue_instance = CollectionsQueue:new(queue_type)
    local queue_data = queue_instance:load()
    local processed_count = 0
    local failed_count = 0

    for collection_id, opts in pairs(queue_data) do
        if opts and opts.operation == 'mark_all_read' and collection_id then
            local success = false
            if queue_type == 'feed' then
                local _result, err = self.feeds:markFeedAsRead(collection_id)
                success = not err
            elseif queue_type == 'category' then
                local _result, err = self.categories:markCategoryAsRead(collection_id)
                success = not err
            end
            local err = not success

            if not err then
                -- Success - remove from queue
                queue_instance:remove(collection_id)
                processed_count = processed_count + 1
            else
                logger.err(
                    '[Miniflux:SyncService] Failed to mark',
                    queue_type,
                    collection_id,
                    'as read (domain returned false)'
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
function SyncService:showCompletionNotification(processed_count, failed_count)
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
function SyncService:clearAllQueues()
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    local status_success = QueueService.clearEntryStatusQueue()
    local feed_success = feed_queue:clear()
    local category_success = category_queue:clear()

    if status_success and feed_success and category_success then
        logger.info('[Miniflux:SyncService] All sync queues cleared')
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
            '[Miniflux:SyncService] Failed to clear queues:',
            table.concat(failed_queues, ', ')
        )
        Notification:error(error_msg)
        return false
    end
end

return SyncService
