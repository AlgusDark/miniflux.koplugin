local UIManager = require('ui/uimanager')
local ReaderUI = require('apps/reader/readerui')
local FFIUtil = require('ffi/util')
local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local lfs = require('libs/libkoreader-lfs')
local _ = require('gettext')
local T = require('ffi/util').template
local Notification = require('shared/utils/notification')
local logger = require('logger')

local EntryEntity = require('domains/entries/entry_entity')
local EntryWorkflow = require('features/entries/services/entry_workflow')
local Files = require('shared/utils/files')
local DownloadCache = require('features/entries/utils/download_cache')

-- **Entry Service** - Handles complex entry workflows and orchestration.
--
-- Service layer for entry operations using proper repository pattern.
-- Provides business logic for entries, delegates data access to repository.
-- Handles UI coordination, navigation, workflows, and queue management.
---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field feeds Feeds Feeds domain module
---@field categories Categories Categories domain module
---@field entries Entries Entries domain module
---@field miniflux_plugin Miniflux Plugin instance for context management
---@field entry_subprocesses table<number, number> Map of entry_id to subprocess PID
local EntryService = {}

---@class EntryServiceDeps
---@field settings MinifluxSettings
---@field feeds Feeds
---@field categories Categories
---@field entries Entries
---@field miniflux_plugin Miniflux

---Create a new EntryService instance
---@param deps EntryServiceDeps Dependencies containing settings, domain modules, and plugin
---@return EntryService
function EntryService:new(deps)
    local instance = {
        settings = deps.settings,
        feeds = deps.feeds,
        categories = deps.categories,
        entries = deps.entries,
        miniflux_plugin = deps.miniflux_plugin,
        entry_subprocesses = {}, -- Track subprocesses per entry
    }
    setmetatable(instance, self)
    self.__index = self

    return instance
end

-- =============================================================================
-- DATA ACCESS OPERATIONS (delegate to repository)
-- =============================================================================

---Get unread entries for entries view
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function EntryService:getUnreadEntries(config)
    return self.entries:getUnreadEntries(config)
end

---Get entries by feed for feed entries view
---@param feed_id number Feed ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function EntryService:getEntriesByFeed(feed_id, config)
    return self.feeds:getEntriesByFeed(feed_id, config)
end

---Get entries by category for category entries view
---@param category_id number Category ID
---@param config? table Optional configuration
---@return MinifluxEntry[]|nil entries, Error|nil error
function EntryService:getEntriesByCategory(category_id, config)
    return self.categories:getEntriesByCategory(category_id, config)
end

-- =============================================================================
-- OFFLINE STATUS QUEUE MANAGEMENT
-- =============================================================================

---Get the path to the status queue file
---@return string Queue file path
function EntryService:getQueueFilePath()
    -- Use the same directory as entries for consistency
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. 'status_queue.lua'
end

---Load the status queue from disk
---@return table Queue data (entry_id -> {new_status, original_status, timestamp})
function EntryService:loadQueue()
    local queue_file = self:getQueueFilePath()

    -- Check if queue file exists
    if not lfs.attributes(queue_file, 'mode') then
        return {} -- Empty queue if file doesn't exist
    end

    -- Load and execute the Lua file
    local success, queue_data = pcall(dofile, queue_file)
    if success and type(queue_data) == 'table' then
        local count = 0
        for _ in pairs(queue_data) do
            count = count + 1
        end
        return queue_data
    else
        return {}
    end
end

---Save the status queue to disk
---@param queue table Queue data to save
---@return boolean success
function EntryService:saveQueue(queue)
    local queue_file = self:getQueueFilePath()

    local count = 0
    for _ in pairs(queue) do
        count = count + 1
    end

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

---Add a status change to the queue
---@param entry_id number Entry ID
---@param opts table Options {new_status: string, original_status: string}
---@return boolean success
function EntryService:enqueueStatusChange(entry_id, opts)
    if not EntryEntity.isValidId(entry_id) then
        return false
    end

    local queue = self:loadQueue()
    local queue_size_before = 0
    for _ in pairs(queue) do
        queue_size_before = queue_size_before + 1
    end

    -- Add/update entry in queue (automatic deduplication via entry_id key)
    queue[entry_id] = {
        new_status = opts.new_status,
        original_status = opts.original_status,
        timestamp = os.time(),
    }

    local queue_size_after = 0
    for _ in pairs(queue) do
        queue_size_after = queue_size_after + 1
    end

    local success = self:saveQueue(queue)

    if success then
        logger.dbg(
            '[Miniflux:EntryService] Enqueued status change for entry',
            entry_id,
            'from',
            opts.original_status,
            'to',
            opts.new_status,
            'queue size:',
            queue_size_after
        )
    else
        logger.err('[Miniflux:EntryService] Failed to save queue after enqueuing entry', entry_id)
    end

    return success
end

---Show confirmation dialog before clearing the status queue
---@param queue_size number Number of entries in queue
function EntryService:confirmClearStatusQueue(queue_size)
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
            local success = self:clearStatusQueue()
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

---Remove a specific entry from the status queue (when API succeeds)
---@param entry_id number Entry ID to remove
---@return boolean success
function EntryService:removeFromQueue(entry_id)
    if not EntryEntity.isValidId(entry_id) then
        return false
    end

    local queue = self:loadQueue()

    -- Check if entry exists in queue
    if not queue[entry_id] then
        return true -- Entry not in queue, nothing to do
    end

    -- Remove entry from queue
    queue[entry_id] = nil

    -- Save updated queue
    return self:saveQueue(queue)
end

---Clear the status queue (delete all pending changes)
---@return boolean success
function EntryService:clearStatusQueue()
    local queue_file = self:getQueueFilePath()

    -- Check if file exists before trying to remove it
    local file_exists = lfs.attributes(queue_file, 'mode') == 'file'

    if not file_exists then
        return true -- File doesn't exist, so it's already "cleared"
    end

    -- Remove the queue file
    local success = os.remove(queue_file)
    return success ~= nil
end

---Process the status queue when network is available (with user confirmation)
---@param auto_confirm? boolean Skip confirmation dialog if true
---@param silent? boolean Skip notifications if true
---@return boolean success
function EntryService:processStatusQueue(auto_confirm, silent)
    logger.info(
        '[Miniflux:EntryService] Processing status queue, auto_confirm:',
        auto_confirm,
        'silent:',
        silent
    )

    local queue = self:loadQueue()
    local queue_size = 0
    for _ in pairs(queue) do
        queue_size = queue_size + 1
    end

    logger.dbg('[Miniflux:EntryService] Queue size:', queue_size)

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
                                self:processStatusQueue(true) -- auto_confirm = true
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
                                self:confirmClearStatusQueue(queue_size)
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
    self:saveQueue(queue)

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

---Try to update entry status via API (helper for queue processing)
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:tryUpdateEntryStatus(entry_id, new_status)
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
        self:removeFromQueue(entry_id)
        return true
    end

    return false
end

---Try to update multiple entries status via batch API (optimized for queue processing)
---@param entry_ids table Array of entry IDs
---@param new_status string New status ("read" or "unread')
---@return boolean success
function EntryService:tryBatchUpdateEntries(entry_ids, new_status)
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

---@class ReadEntryOptions
---@field browser? MinifluxBrowser Browser instance to close
---@field context? MinifluxContext Navigation context to attach to ReaderUI.instance

---Read an entry (download if needed and open)
---@param entry_data table Raw entry data from API
---@param opts? ReadEntryOptions Options for entry reading
function EntryService:readEntry(entry_data, opts)
    opts = opts or {}
    local browser = opts.browser
    local context = opts.context

    -- Validate entry data with enhanced validation
    local _valid, err = EntryEntity.validateForDownload(entry_data)
    if err then
        Notification:error(err.message)
        return false
    end

    -- Execute complete workflow (fire-and-forget)
    EntryWorkflow.execute({
        entry_data = entry_data,
        settings = self.settings,
        browser = browser,
        context = context,
    })
end

---Mark multiple entries as read in batch
---@param entry_ids table Array of entry IDs
---@return boolean success
function EntryService:markEntriesAsRead(entry_ids)
    if not entry_ids or #entry_ids == 0 then
        return false
    end

    -- Show progress notification
    local progress_message = _('Marking ') .. #entry_ids .. _(' entries as read...')

    -- Try batch API call first
    local _result, err = self.entries:updateEntries(entry_ids, {
        body = { status = 'read' },
        dialogs = {
            loading = { text = progress_message },
            -- Note: Don't show success/error dialogs here - we'll handle fallback ourselves
        },
    })

    if not err then
        -- API success - update local metadata
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, { new_status = 'read' })
            -- Remove from queue since server is now source of truth
            self:removeFromQueue(entry_id)
        end

        -- Show success notification
        Notification:success(_('Successfully marked ') .. #entry_ids .. _(' entries as read'))

        -- Invalidate caches so next navigation shows updated counts
        local MinifluxEvent = require('shared/utils/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        return true
    else
        -- API failed - use queue fallback with better UX messaging
        -- Perform optimistic local updates immediately for good UX
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, { new_status = 'read' })
            -- Queue each entry for later sync
            self:enqueueStatusChange(entry_id, {
                new_status = 'read',
                original_status = 'unread', -- Assume opposite for batch operations
            })
        end

        -- Show simple offline message
        local message = _('Marked as read (will sync when online)')
        Notification:info(message)

        return true -- Still successful from user perspective
    end
end

---Mark multiple entries as unread in batch
---@param entry_ids table Array of entry IDs
---@return boolean success
function EntryService:markEntriesAsUnread(entry_ids)
    if not entry_ids or #entry_ids == 0 then
        return false
    end

    -- Show progress notification
    local progress_message = _('Marking ') .. #entry_ids .. _(' entries as unread...')

    -- Try batch API call first
    local _result, err = self.entries:updateEntries(entry_ids, {
        body = { status = 'unread' },
        dialogs = {
            loading = { text = progress_message },
            -- Note: Don't show success/error dialogs here - we'll handle fallback ourselves
        },
    })

    if not err then
        -- API success - update local metadata
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, { new_status = 'unread' })
            -- Remove from queue since server is now source of truth
            self:removeFromQueue(entry_id)
        end

        -- Show success notification
        Notification:success(_('Successfully marked ') .. #entry_ids .. _(' entries as unread'))

        -- Invalidate caches so next navigation shows updated counts
        local MinifluxEvent = require('shared/utils/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        return true
    else
        -- API failed - use queue fallback with better UX messaging
        -- Perform optimistic local updates immediately for good UX
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, { new_status = 'unread' })
            -- Queue each entry for later sync
            self:enqueueStatusChange(entry_id, {
                new_status = 'unread',
                original_status = 'read', -- Assume opposite for batch operations
            })
        end

        -- Show simple offline message
        local message = _('Marked as unread (will sync when online)')
        Notification:info(message)

        return true -- Still successful from user perspective
    end
end

---Download multiple entries without opening them
---@param entry_data_list table Array of entry data objects
---@param completion_callback? function Optional callback called when batch completes
---@return boolean success Always returns true (fire-and-forget operations)
function EntryService:downloadEntries(entry_data_list, completion_callback)
    local BatchDownloadEntriesWorkflow =
        require('features/entries/services/batch_download_entries_workflow')

    BatchDownloadEntriesWorkflow.execute({
        entry_data_list = entry_data_list,
        settings = self.settings,
        completion_callback = completion_callback,
    })

    return true
end

---Kill any active subprocess for an entry
---@param entry_id number Entry ID
---@private
function EntryService:killEntrySubprocess(entry_id)
    local pid = self.entry_subprocesses[entry_id]
    if pid then
        logger.info('[Miniflux:EntryService] Killing subprocess', pid, 'for entry', entry_id)
        FFIUtil.terminateSubProcess(pid)
        self.entry_subprocesses[entry_id] = nil
    end
end

---Change entry status with validation and side effects
---@param entry_id number Entry ID
---@param opts EntryStatusOptions Options for status update
---@return boolean success True if status change succeeded
function EntryService:changeEntryStatus(entry_id, opts)
    local new_status = opts.new_status
    local doc_settings = opts.doc_settings

    if not EntryEntity.isValidId(entry_id) then
        Notification:error(_('Cannot change status: invalid entry ID'))
        return false
    end

    -- Kill any active subprocess for this entry (prevents conflicting updates)
    self:killEntrySubprocess(entry_id)

    -- Prepare status messages using templates
    local loading_text = T(_('Marking entry as %1...'), new_status)
    local success_text = T(_('Entry marked as %1'), new_status)
    local _error_text = T(_('Failed to mark entry as %1'), new_status)

    -- Call API with automatic dialog management
    local _result, err = self.entries:updateEntries(entry_id, {
        body = { status = new_status },
        dialogs = {
            loading = { text = loading_text },
            success = { text = success_text },
            -- Note: No error dialog - we handle fallback gracefully
        },
    })

    if err then
        -- API failed - use queue fallback for offline mode
        -- Perform optimistic local update for _mmediate UX
        EntryEntity.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Queue for later sync (determine original status from current metadata)
        local _metadata = EntryEntity.loadMetadata(entry_id)
        local original_status = (new_status == 'read') and 'unread' or 'read' -- Assume opposite

        self:enqueueStatusChange(entry_id, {
            new_status = new_status,
            original_status = original_status,
        })

        -- Show offline message instead of error
        local message = new_status == 'read' and _('Marked as read (will sync when online)')
            or _('Marked as unread (will sync when online)')
        Notification:info(message)

        return true -- Still successful from user perspective
    else
        -- API success - update local metadata using provided DocSettings if available
        EntryEntity.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Remove from queue since server is now source of truth
        self:removeFromQueue(entry_id)

        -- Invalidate caches so next navigation shows updated counts
        local MinifluxEvent = require('shared/utils/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        return true
    end
end

-- =============================================================================
-- READER EVENT HANDLING
-- =============================================================================

---Handle ReaderReady event for miniflux entries
---@param opts {file_path: string, doc_settings?: table} Options containing file path and optional DocSettings
function EntryService:onReaderReady(opts)
    local file_path = opts.file_path
    local doc_settings = opts.doc_settings -- ReaderUI's cached DocSettings
    self:autoMarkAsRead(file_path, doc_settings)
end

---Auto-mark miniflux entry as read if enabled
---@param file_path string File path to process
---@param doc_settings? table Optional ReaderUI DocSettings instance
function EntryService:autoMarkAsRead(file_path, doc_settings)
    -- Check if auto-mark-as-read is enabled
    if not self.settings.mark_as_read_on_open then
        return
    end

    -- Check if current document is a miniflux HTML file
    if not EntryEntity.isMinifluxEntry(file_path) then
        return
    end

    -- Extract entry ID from path
    local entry_id = EntryEntity.extractEntryIdFromPath(file_path)
    if not entry_id then
        return
    end

    -- Spawn update status to "read" with ReaderUI's DocSettings
    local pid =
        self:spawnUpdateStatus(entry_id, { new_status = 'read', doc_settings = doc_settings })
    if pid then
        logger.info('[Miniflux:EntryService] Auto-mark-as-read spawned with PID:', pid)
        -- Track the subprocess for proper cleanup
        self.miniflux_plugin:trackSubprocess(pid)
        -- Also track per entry so we can kill it on manual status change
        self.entry_subprocesses[entry_id] = pid
    else
        logger.dbg('[Miniflux:EntryService] Auto-mark-as-read skipped (already read or disabled)')
    end
end

-- =============================================================================
-- UI COORDINATION & FILE OPERATIONS
-- =============================================================================

-- =============================================================================
-- PRIVATE HELPER METHODS
-- =============================================================================

---Spawn update entry status in subprocess with optimistic update and queue fallback
---@param entry_id number Entry ID to update
---@param opts EntryStatusOptions Options for status update
---@return number|nil pid Process ID if spawned, nil if operation skipped
function EntryService:spawnUpdateStatus(entry_id, opts)
    local new_status = opts.new_status
    local doc_settings = opts.doc_settings

    -- Check if auto-mark feature is enabled
    if not self.settings.mark_as_read_on_open then
        return nil
    end

    -- Validate entry ID first
    if not EntryEntity.isValidId(entry_id) then
        return nil
    end

    -- Load current metadata to get original status
    local local_metadata = EntryEntity.loadMetadata(entry_id)
    local original_status = local_metadata and local_metadata.status or 'unread'

    -- Smart check: First check local metadata to avoid unnecessary work
    local is_already_target_status = local_metadata
        and EntryEntity.isEntryRead(local_metadata.status)
            == EntryEntity.isEntryRead(new_status)

    if is_already_target_status then
        -- Clean up any existing subprocess for this entry
        self:killEntrySubprocess(entry_id)
        return nil
    end

    -- Step 1: Always do optimistic update first (immediate UX)
    local optimistic_success = EntryEntity.updateEntryStatus(
        entry_id,
        { new_status = new_status, doc_settings = doc_settings }
    )
    if not optimistic_success then
        return nil
    end

    -- Step 2: Background API call in subprocess (non-blocking)
    local NetworkMgr = require('ui/network/manager')

    -- Extract settings data for subprocess (separate memory space)
    local server_address = self.settings.server_address
    local api_token = self.settings.api_token

    local pid = FFIUtil.runInSubProcess(function()
        -- Import required modules in subprocess
        local MinifluxAPI = require('shared/api/miniflux_api')
        -- selene: allow(shadowing)
        local EntryEntity = require('domains/entries/entry_entity')
        -- selene: allow(shadowing)
        local logger = require('logger')

        -- Create settings object for subprocess
        local subprocess_settings = {
            server_address = server_address,
            api_token = api_token,
        }

        local miniflux_api = MinifluxAPI:new({
            getSettings = function()
                return subprocess_settings
            end,
        })

        -- Check network connectivity
        -- selene: allow(shadowing)
        local NetworkMgr = require('ui/network/manager')
        if not NetworkMgr:isOnline() then
            logger.dbg(
                '[Miniflux:Subprocess] Device offline, skipping API call for entry:',
                entry_id
            )
            -- Can't queue from subprocess, main process will handle it
            return
        end

        -- Make API call with built-in timeout handling
        local _, err = miniflux_api:updateEntries(entry_id, {
            body = { status = new_status },
            -- No dialogs config - silent background operation
        })

        if err then
            logger.warn(
                '[Miniflux:Subprocess] API call failed for entry:',
                entry_id,
                'error:',
                err.message or err
            )
            -- Auto-healing: If API call failed, revert local metadata
            EntryEntity.updateEntryStatus(
                entry_id,
                { new_status = original_status, subprocess = true }
            )
        else
            logger.dbg(
                '[Miniflux:Subprocess] Successfully updated entry',
                entry_id,
                'to',
                new_status
            )
            -- Remove from queue since server is now source of truth
            -- Note: Queue operations need to be duplicated in subprocess
            -- selene: allow(shadowing)
            local Files = require('shared/utils/files')
            local miniflux_dir = EntryEntity.getDownloadDir()
            local queue_file = miniflux_dir .. 'status_queue.lua'

            -- Load queue
            -- selene: allow(shadowing)
            local lfs = require('libs/libkoreader-lfs')
            if lfs.attributes(queue_file, 'mode') then
                local success, queue_data = pcall(dofile, queue_file)
                if success and type(queue_data) == 'table' then
                    -- Remove this entry from queue
                    queue_data[entry_id] = nil

                    -- Save updated queue
                    local queue_content = 'return {\n'
                    for qid, qopts in pairs(queue_data) do
                        queue_content = queue_content
                            .. string.format(
                                '  [%d] = {\n    new_status = %q,\n    original_status = %q,\n    timestamp = %d\n  },\n',
                                qid,
                                qopts.new_status,
                                qopts.original_status,
                                qopts.timestamp
                            )
                    end
                    queue_content = queue_content .. '}\n'
                    Files.writeFile(queue_file, queue_content)
                end
            end
        end
        -- Process exits automatically
    end)

    -- If subprocess couldn't start or we're offline, queue for later
    if not pid or not NetworkMgr:isOnline() then
        self:enqueueStatusChange(entry_id, {
            new_status = new_status,
            original_status = original_status,
        })
    else
        -- Track subprocess for this entry
        self.entry_subprocesses[entry_id] = pid

        -- Schedule cleanup check to remove from tracking when done
        UIManager:scheduleIn(30, function()
            if self.entry_subprocesses[entry_id] == pid then
                -- Check if subprocess is done
                if FFIUtil.isSubProcessDone(pid) then
                    self.entry_subprocesses[entry_id] = nil
                    logger.dbg(
                        '[Miniflux:EntryService] Cleaned up completed subprocess',
                        pid,
                        'for entry',
                        entry_id
                    )
                end
            end
        end)
    end

    return pid
end

---Delete a local entry
---@param entry_id number Entry ID
---@return boolean success
function EntryService:deleteLocalEntry(entry_id)
    local entry_dir = EntryEntity.getEntryDirectory(entry_id)

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end
    local ok = FFIUtil.purgeDir(entry_dir)

    if ok then
        -- Invalidate download cache for this entry
        DownloadCache.invalidate(entry_id)
        logger.dbg(
            '[Miniflux:EntryService] Invalidated download cache after deleting entry',
            entry_id
        )

        Notification:success(_('Local entry deleted successfully'))

        -- Open Miniflux folder
        EntryEntity.openMinifluxFolder()

        return true
    else
        Notification:error(_('Failed to delete local entry: ') .. tostring(ok))
        return false
    end
end

return EntryService
