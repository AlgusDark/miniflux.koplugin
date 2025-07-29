local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local UIManager = require('ui/uimanager')
local Notification = require('shared/widgets/notification')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')
local lfs = require('libs/libkoreader-lfs')

local EntryEntity = require('domains/entries/entry_entity')
local Files = require('shared/files')
local ReaderUI = require('apps/reader/readerui')

---@class QueueService
---@field entries Entries Reference to entries domain for entry status operations
---@field feeds Feeds Reference to feeds domain for feed operations
---@field categories Categories Reference to categories domain for category operations
local QueueService = {}

---Create a new QueueService instance
---@param config table Configuration with entries, feeds, and categories
---@return QueueService
function QueueService:new(config)
    local instance = {
        entries = config.entries,
        feeds = config.feeds,
        categories = config.categories,
    }
    setmetatable(instance, { __index = self })
    return instance
end

-- =============================================================================
-- ENTRY STATUS QUEUE MANAGEMENT
-- =============================================================================

---Get the path to the status queue file
---@return string Queue file path
function QueueService.getEntryStatusQueueFilePath()
    -- Use the same directory as entries for consistency
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. 'status_queue.lua'
end

---Load the entry status queue from disk (static/pure function)
---@return table Queue data (entry_id -> {new_status, original_status, timestamp})
function QueueService.loadEntryStatusQueue()
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Check if queue file exists
    if not lfs.attributes(queue_file, 'mode') then
        return {} -- Empty queue if file doesn't exist
    end

    -- Load and execute the Lua file
    local success, queue_data = pcall(dofile, queue_file)
    if success and type(queue_data) == 'table' then
        return queue_data
    else
        return {}
    end
end

---Save the entry status queue to disk (static/pure function)
---@param queue table Queue data to save
---@return boolean success
function QueueService.saveEntryStatusQueue(queue)
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Ensure miniflux directory exists
    local miniflux_dir = queue_file:match('(.+)/[^/]+$')
    local success, _err = Files.createDirectory(miniflux_dir)
    if not success then
        return false
    end

    -- Convert queue table to Lua code
    local queue_content = 'return {\n'
    for entry_id, opts in pairs(queue) do
        queue_content = queue_content
            .. string.format(
                '  [%d] = {\n    new_status = %q,\n    original_status = %q,\n    timestamp = %d\n  },\n',
                entry_id,
                opts.new_status,
                opts.original_status,
                opts.timestamp
            )
    end
    queue_content = queue_content .. '}\n'

    -- Write to file
    local write_success, _write_err = Files.writeFile(queue_file, queue_content)
    if not write_success then
        return false
    end

    return true
end

---Add a status change to the entry status queue (static/pure function)
---@param entry_id number Entry ID
---@param opts table Options {new_status: string, original_status: string}
---@return boolean success
function QueueService.enqueueStatusChange(entry_id, opts)
    if not EntryEntity.isValidId(entry_id) then
        return false
    end

    local queue = QueueService.loadEntryStatusQueue()

    -- Add/update entry in queue (automatic deduplication via entry_id key)
    queue[entry_id] = {
        new_status = opts.new_status,
        original_status = opts.original_status,
        timestamp = os.time(),
    }

    local success = QueueService.saveEntryStatusQueue(queue)

    if success then
        logger.dbg(
            '[Miniflux:QueueService] Enqueued status change for entry',
            entry_id,
            'from',
            opts.original_status,
            'to',
            opts.new_status
        )
    else
        logger.err('[Miniflux:QueueService] Failed to save queue after enqueuing entry', entry_id)
    end

    return success
end

---Remove a specific entry from the status queue (static/pure function)
---@param entry_id number Entry ID to remove
---@return boolean success
function QueueService.removeFromEntryStatusQueue(entry_id)
    if not EntryEntity.isValidId(entry_id) then
        return false
    end

    local queue = QueueService.loadEntryStatusQueue()

    -- Check if entry exists in queue
    if not queue[entry_id] then
        return true -- Entry not in queue, nothing to do
    end

    -- Remove entry from queue
    queue[entry_id] = nil

    -- Save updated queue
    return QueueService.saveEntryStatusQueue(queue)
end

---Clear the entry status queue (static/pure function)
---@return boolean success
function QueueService.clearEntryStatusQueue()
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Check if file exists before trying to remove it
    local file_exists = lfs.attributes(queue_file, 'mode') == 'file'

    if not file_exists then
        return true -- File doesn't exist, so it's already "cleared"
    end

    -- Remove the queue file
    local success = os.remove(queue_file)
    return success ~= nil
end

---Get total count across all queue types (static/pure function)
---@return number total_count, number status_count, number feed_count, number category_count
function QueueService.getTotalQueueCount()
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    -- Count entry status queue
    local status_queue = QueueService.loadEntryStatusQueue()
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

---Show confirmation dialog before clearing the entry status queue
---@param queue_size number Number of entries in queue
function QueueService:confirmClearEntryStatusQueue(queue_size)
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
function QueueService:tryUpdateEntryStatus(entry_id, new_status)
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
            if EntryEntity.isMinifluxEntry(current_file) then
                local current_entry_id = EntryEntity.extractEntryIdFromPath(current_file)
                if current_entry_id == entry_id then
                    doc_settings = ReaderUI.instance.doc_settings
                end
            end
        end

        EntryEntity.updateEntryStatus(
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
function QueueService:tryBatchUpdateEntries(entry_ids, new_status)
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
            if EntryEntity.isMinifluxEntry(current_file) then
                current_entry_id = EntryEntity.extractEntryIdFromPath(current_file)
                doc_settings = ReaderUI.instance.doc_settings
            end
        end

        -- Update local metadata for all entries on success (Miniflux returns 204 for success)
        for _, entry_id in ipairs(entry_ids) do
            -- Pass doc_settings only if this entry is currently open
            local entry_doc_settings = (entry_id == current_entry_id) and doc_settings or nil
            EntryEntity.updateEntryStatus(
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
function QueueService:processEntryStatusQueue(auto_confirm, silent)
    logger.info(
        '[Miniflux:QueueService] Processing status queue, auto_confirm:',
        auto_confirm,
        'silent:',
        silent
    )

    local queue = QueueService.loadEntryStatusQueue()
    local queue_size = 0
    for _ in pairs(queue) do
        queue_size = queue_size + 1
    end

    logger.dbg('[Miniflux:QueueService] Queue size:', queue_size)

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

-- =============================================================================
-- MULTI-DOMAIN QUEUE MANAGEMENT
-- =============================================================================

---Show sync dialog or process queues based on queue state
---@return boolean success
function QueueService:processAllQueues()
    local total_count, status_count, feed_count, category_count = QueueService.getTotalQueueCount()

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
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local queue_instance = CollectionsQueue:new(queue_type)
    local queue_data = queue_instance:load()
    local processed_count = 0
    local failed_count = 0

    for collection_id, opts in pairs(queue_data) do
        if opts and opts.operation == 'mark_all_read' and collection_id then
            local success = false
            if queue_type == 'feed' then
                success = self.feeds:markAsRead(collection_id)
            elseif queue_type == 'category' then
                success = self.categories:markAsRead(collection_id)
            end
            local err = not success

            if not err then
                -- Success - remove from queue
                queue_instance:remove(collection_id)
                processed_count = processed_count + 1
            else
                logger.err(
                    '[Miniflux:QueueService] Failed to mark',
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
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    local status_success = QueueService.clearEntryStatusQueue()
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
