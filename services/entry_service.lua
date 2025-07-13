local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")
local T = require("ffi/util").template
local Notification = require("utils/notification")

-- Import dependencies
local EntryEntity = require("entities/entry_entity")
local Navigation = require("services/navigation_service")
local EntryWorkflow = require("services/entry_workflow")
local Files = require("utils/files")

-- **Entry Service** - Handles complex entry workflows and orchestration.
--
-- It coordinates between the Entry entity, repositories, and infrastructure
-- services to provide high-level entry operations including UI coordination,
-- navigation, and dialog management.
---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field miniflux_plugin Miniflux Plugin instance for context management
---@field feed_repository FeedRepository Feed repository for cache invalidation
---@field category_repository CategoryRepository Category repository for cache invalidation
local EntryService = {}

---@class EntryServiceDeps
---@field settings MinifluxSettings
---@field miniflux_api MinifluxAPI
---@field miniflux_plugin Miniflux
---@field feed_repository FeedRepository
---@field category_repository CategoryRepository

---Create a new EntryService instance
---@param deps EntryServiceDeps Dependencies containing settings, API, plugin, and repositories
---@return EntryService
function EntryService:new(deps)
    local instance = {
        settings = deps.settings,
        miniflux_api = deps.miniflux_api,
        miniflux_plugin = deps.miniflux_plugin,
        feed_repository = deps.feed_repository,
        category_repository = deps.category_repository,
    }
    setmetatable(instance, self)
    self.__index = self

    return instance
end

-- =============================================================================
-- OFFLINE STATUS QUEUE MANAGEMENT
-- =============================================================================

---Get the path to the status queue file
---@return string Queue file path
function EntryService:getQueueFilePath()
    -- Use the same directory as entries for consistency
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. "status_queue.lua"
end

---Load the status queue from disk
---@return table Queue data (entry_id -> {new_status, original_status, timestamp})
function EntryService:loadQueue()
    local queue_file = self:getQueueFilePath()


    -- Check if queue file exists
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(queue_file, "mode") then
        return {} -- Empty queue if file doesn't exist
    end

    -- Load and execute the Lua file
    local success, queue_data = pcall(dofile, queue_file)
    if success and type(queue_data) == "table" then
        local count = 0
        for i in pairs(queue_data) do count = count + 1 end
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
    for i in pairs(queue) do count = count + 1 end

    -- Ensure miniflux directory exists
    local miniflux_dir = queue_file:match("(.+)/[^/]+$")
    local success, err = Files.createDirectory(miniflux_dir)
    if not success then

        return false
    end

    -- Convert queue table to Lua code
    local queue_content = "return {\n"
    for entry_id, opts in pairs(queue) do
        queue_content = queue_content .. string.format(
            "  [%d] = {\n    new_status = %q,\n    original_status = %q,\n    timestamp = %d\n  },\n",
            entry_id, opts.new_status, opts.original_status, opts.timestamp
        )
    end
    queue_content = queue_content .. "}\n"

    -- Write to file
    local write_success, write_err = Files.writeFile(queue_file, queue_content)
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
    for i in pairs(queue) do queue_size_before = queue_size_before + 1 end

    -- Add/update entry in queue (automatic deduplication via entry_id key)
    queue[entry_id] = {
        new_status = opts.new_status,
        original_status = opts.original_status,
        timestamp = os.time()
    }

    local queue_size_after = 0
    for i in pairs(queue) do queue_size_after = queue_size_after + 1 end

    local success = self:saveQueue(queue)

    if success then
    end


    return success
end

---Show confirmation dialog before clearing the status queue
---@param queue_size number Number of entries in queue
function EntryService:confirmClearStatusQueue(queue_size)
    local ConfirmBox = require("ui/widget/confirmbox")
    
    local message = T(_("Are you sure you want to delete the sync queue?\n\nYou still have %1 entries that need to sync with the server.\n\nThis action cannot be undone."), queue_size)
    
    local confirm_dialog = ConfirmBox:new{
        text = message,
        ok_text = _("Delete Queue"),
        ok_callback = function()
            local result, err = self:clearStatusQueue()
            if err then
                Notification:error(err.message)
            else
                Notification:info(_("Sync queue cleared"))
            end
        end,
        cancel_text = _("Cancel"),
    }
    
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
---@return boolean|nil result, table|nil error
function EntryService:clearStatusQueue()
    local queue_file = self:getQueueFilePath()
    
    -- Remove the queue file
    local success = os.remove(queue_file)
    if success then
        return true, nil
    else
        return nil, { message = _("Failed to clear sync queue") }
    end
end

---Process the status queue when network is available (with user confirmation)
---@param auto_confirm? boolean Skip confirmation dialog if true
---@return boolean success
function EntryService:processStatusQueue(auto_confirm)
    local queue = self:loadQueue()
    local queue_size = 0
    for i in pairs(queue) do queue_size = queue_size + 1 end

    if queue_size == 0 then
        -- Show friendly message only when manually triggered (auto_confirm is nil)
        if auto_confirm == nil then
            Notification:info(_("All changes are already synced"))
        end
        return true -- Nothing to process
    end


    -- Ask user for confirmation unless auto_confirm is true
    if not auto_confirm then

        local sync_dialog
        sync_dialog = ButtonDialogTitle:new({
            title = T(_("Sync %1 pending status changes?"), queue_size),
            title_align = "center",
            buttons = {
                {
                    {
                        text = _("Later"),
                        callback = function()
                            UIManager:close(sync_dialog)
                        end,
                    },
                    {
                        text = _("Sync Now"),
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
                        text = _("Delete Queue"),
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
        if opts.new_status == "read" then
            table.insert(read_entries, entry_id)
        elseif opts.new_status == "unread" then
            table.insert(unread_entries, entry_id)
        end
    end

    local processed_count = 0
    local failed_count = 0
    local read_success = false
    local unread_success = false

    -- Process read entries in single batch API call
    if #read_entries > 0 then
        read_success = self:tryBatchUpdateEntries(read_entries, "read")
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
        unread_success = self:tryBatchUpdateEntries(unread_entries, "unread")
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
            for i, entry_id in ipairs(read_entries) do
                queue[entry_id] = nil
            end
        end
        if unread_success then
            for i, entry_id in ipairs(unread_entries) do
                queue[entry_id] = nil
            end
        end
    end

    -- Save updated queue
    self:saveQueue(queue)

    -- Show completion notification
    if processed_count > 0 then
        local message = processed_count .. " entries synced"
        if failed_count > 0 then
            message = message .. ", " .. failed_count .. " failed"
        end
        Notification:success(message)
    elseif failed_count > 0 then
        Notification:error("Failed to sync " .. failed_count .. " entries")
    end


    return true
end

---Try to update entry status via API (helper for queue processing)
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:tryUpdateEntryStatus(entry_id, new_status)
    -- Use existing API with minimal dialogs
    local result, err = self.miniflux_api:updateEntries(entry_id, {
        body = { status = new_status }
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
        
        EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
        
        -- Remove from queue since server is now source of truth
        self:removeFromQueue(entry_id)
        return true
    end

    return false
end

---Try to update multiple entries status via batch API (optimized for queue processing)
---@param entry_ids table Array of entry IDs
---@param new_status string New status ("read" or "unread")
---@return boolean success
function EntryService:tryBatchUpdateEntries(entry_ids, new_status)
    if not entry_ids or #entry_ids == 0 then
        return true -- No entries to process
    end

    -- Use existing batch API without dialogs for background processing
    local result, err = self.miniflux_api:updateEntries(entry_ids, {
        body = { status = new_status }
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
        for i, entry_id in ipairs(entry_ids) do
            -- Pass doc_settings only if this entry is currently open
            local entry_doc_settings = (entry_id == current_entry_id) and doc_settings or nil
            EntryEntity.updateEntryStatus(entry_id, new_status, entry_doc_settings)
        end
        return true
    end

    return false
end


---Read an entry (download if needed and open)
---@param entry_data table Raw entry data from API
---@param browser? MinifluxBrowser Browser instance to close
function EntryService:readEntry(entry_data, browser)
    -- Validate entry data with enhanced validation
    local valid, err = EntryEntity.validateForDownload(entry_data)
    if err then
        Notification:error(err.message)
        return false
    end

    -- Execute complete workflow (fire-and-forget)
    EntryWorkflow.execute({
        entry_data = entry_data,
        settings = self.settings,
        browser = browser
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
    local progress_message = _("Marking ") .. #entry_ids .. _(" entries as read...")

    -- Try batch API call first
    local result, err = self.miniflux_api:updateEntries(entry_ids, {
        body = { status = "read" },
        dialogs = {
            loading = { text = progress_message },
            -- Note: Don't show success/error dialogs here - we'll handle fallback ourselves
        }
    })

    if not err then
        -- API success - update local metadata
        for i, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "read")
            -- Remove from queue since server is now source of truth
            self:removeFromQueue(entry_id)
        end

        -- Show success notification
        Notification:success(_("Successfully marked ") .. #entry_ids .. _(" entries as read"))

        -- Invalidate caches so next navigation shows updated counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()

        return true
    else
        -- API failed - use queue fallback with better UX messaging
        -- Perform optimistic local updates immediately for good UX
        for i, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "read")
            -- Queue each entry for later sync
            self:enqueueStatusChange(entry_id, {
                new_status = "read",
                original_status = "unread" -- Assume opposite for batch operations
            })
        end

        -- Show simple offline message
        local message = _("Marked as read (will sync when online)")
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
    local progress_message = _("Marking ") .. #entry_ids .. _(" entries as unread...")

    -- Try batch API call first
    local result, err = self.miniflux_api:updateEntries(entry_ids, {
        body = { status = "unread" },
        dialogs = {
            loading = { text = progress_message },
            -- Note: Don't show success/error dialogs here - we'll handle fallback ourselves
        }
    })

    if not err then
        -- API success - update local metadata
        for i, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "unread")
            -- Remove from queue since server is now source of truth
            self:removeFromQueue(entry_id)
        end

        -- Show success notification
        Notification:success(_("Successfully marked ") .. #entry_ids .. _(" entries as unread"))

        -- Invalidate caches so next navigation shows updated counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()

        return true
    else
        -- API failed - use queue fallback with better UX messaging
        -- Perform optimistic local updates immediately for good UX
        for i, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "unread")
            -- Queue each entry for later sync
            self:enqueueStatusChange(entry_id, {
                new_status = "unread",
                original_status = "read" -- Assume opposite for batch operations
            })
        end

        -- Show simple offline message
        local message = _("Marked as unread (will sync when online)")
        Notification:info(message)

        return true -- Still successful from user perspective
    end
end

---Download multiple entries without opening them
---@param entry_data_list table Array of entry data objects
---@param completion_callback? function Optional callback called when batch completes
---@return boolean success Always returns true (fire-and-forget operations)
function EntryService:downloadEntries(entry_data_list, completion_callback)
    local BatchDownloadEntriesWorkflow = require("services/batch_download_entries_workflow")

    BatchDownloadEntriesWorkflow.execute({
        entry_data_list = entry_data_list,
        settings = self.settings,
        completion_callback = completion_callback
    })

    return true
end

---Change entry status with validation and side effects
---@param entry_id number Entry ID
---@param new_status string New status
---@param doc_settings? table Optional ReaderUI DocSettings instance to use
---@return boolean success
function EntryService:changeEntryStatus(entry_id, new_status, doc_settings)
    if not EntryEntity.isValidId(entry_id) then
        Notification:error(_("Cannot change status: invalid entry ID"))
        return false
    end

    -- Prepare status messages using templates
    local loading_text = T(_("Marking entry as %1..."), new_status)
    local success_text = T(_("Entry marked as %1"), new_status)
    local error_text = T(_("Failed to mark entry as %1"), new_status)

    -- Call API with automatic dialog management
    local result, err = self.miniflux_api:updateEntries(entry_id, {
        body = { status = new_status },
        dialogs = {
            loading = { text = loading_text },
            success = { text = success_text },
            -- Note: No error dialog - we handle fallback gracefully
        }
    })

    if err then
        -- API failed - use queue fallback for offline mode
        -- Perform optimistic local update for immediate UX
        EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
        
        -- Queue for later sync (determine original status from current metadata)
        local metadata = EntryEntity.loadMetadata(entry_id)
        local original_status = (new_status == "read") and "unread" or "read" -- Assume opposite
        
        self:enqueueStatusChange(entry_id, {
            new_status = new_status,
            original_status = original_status
        })
        
        -- Show offline message instead of error
        local message = new_status == "read" 
            and _("Marked as read (will sync when online)")
            or _("Marked as unread (will sync when online)")
        Notification:info(message)
        
        return true -- Still successful from user perspective
    else
        -- API success - update local metadata using provided DocSettings if available
        EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
        
        -- Remove from queue since server is now source of truth
        self:removeFromQueue(entry_id)

        -- Invalidate caches so next navigation shows updated counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()

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
    local pid = self:spawnUpdateStatus(entry_id, "read", doc_settings)
    if pid then
    else
    end
end

-- =============================================================================
-- UI COORDINATION & FILE OPERATIONS
-- =============================================================================

---Show end of entry dialog with navigation options
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Dialog reference for caller management or nil if failed
function EntryService:showEndOfEntryDialog(entry_info)
    if not entry_info or not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    -- Load entry metadata to check current status
    local metadata = EntryEntity.loadMetadata(entry_info.entry_id)

    -- Use status for business logic
    local entry_status = metadata and metadata.status or "unread"

    -- Get ReaderUI's DocSettings to avoid cache conflicts
    local doc_settings = self.miniflux_plugin.ui and self.miniflux_plugin.ui.doc_settings

    -- Use utility functions for button text and callback
    local mark_button_text = EntryEntity.getStatusButtonText(entry_status)
    local mark_callback
    if EntryEntity.isEntryRead(entry_status) then
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "unread", doc_settings)
        end
    else
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "read", doc_settings)
        end
    end

    -- Create dialog and return reference for caller management
    local dialog
    dialog = ButtonDialogTitle:new({
        title = _("You've reached the end of the entry."),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("← Previous"),
                    callback = function()
                        UIManager:close(dialog)
                        Navigation.navigateToEntry(entry_info, {
                            navigation_options = { direction = "previous" },
                            settings = self.settings,
                            miniflux_api = self.miniflux_api,
                            entry_service = self,
                            miniflux_plugin = self.miniflux_plugin
                        })
                    end,
                },
                {
                    text = _("Next →"),
                    callback = function()
                        UIManager:close(dialog)
                        Navigation.navigateToEntry(entry_info, {
                            navigation_options = { direction = "next" },
                            settings = self.settings,
                            miniflux_api = self.miniflux_api,
                            entry_service = self,
                            miniflux_plugin = self.miniflux_plugin
                        })
                    end,
                },
            },
            {
                {
                    text = _("⚠ Delete local entry"),
                    callback = function()
                        UIManager:close(dialog)
                        -- Inline deletion with validation
                        if not EntryEntity.isValidId(entry_info.entry_id) then
                            Notification:warning(_("Cannot delete: invalid entry ID"))
                            return
                        end
                        self:deleteLocalEntry(entry_info.entry_id)
                    end,
                },
                {
                    text = mark_button_text,
                    callback = function()
                        UIManager:close(dialog)
                        mark_callback()
                        -- TODO: Dialog Refresh After Status Change (Feature C - MVP excluded)
                        -- CURRENT: Dialog closes, user needs to manually reopen to see updated status
                        -- DESIRED: After API success notification (2.5s), automatically recreate dialog
                        --          with opposite button text (read->unread or unread->read)
                        -- IMPLEMENTATION: Add refreshDialog() callback to mark_callback, use
                        --                UIManager:scheduleIn(2.5, refreshDialog) after successful API call
                    end,
                },
            },
            {
                {
                    text = _("⌂ Miniflux folder"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryEntity.openMinifluxFolder()
                    end,
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    })

    -- Enhance dialog with key handlers if available
    if self.miniflux_plugin.key_handler_service then
        dialog = self.miniflux_plugin.key_handler_service:enhanceDialogWithKeys(dialog, entry_info)
    end

    -- Show dialog and return reference for caller management
    UIManager:show(dialog)
    return dialog
end

-- =============================================================================
-- PRIVATE HELPER METHODS
-- =============================================================================

---Spawn update entry status with optimistic update and queue fallback
---@param entry_id number Entry ID to update
---@param new_status string New status ("read" or "unread")
---@param doc_settings? table Optional ReaderUI DocSettings instance
---@return boolean success True if operation initiated successfully
function EntryService:spawnUpdateStatus(entry_id, new_status, doc_settings)
    -- Check if auto-mark feature is enabled
    if not self.settings.mark_as_read_on_open then
        return false
    end

    -- Validate entry ID first
    if not EntryEntity.isValidId(entry_id) then
        return false
    end

    -- Load current metadata to get original status
    local local_metadata = EntryEntity.loadMetadata(entry_id)
    local original_status = local_metadata and local_metadata.status or "unread"

    -- Smart check: First check local metadata to avoid unnecessary work
    local is_already_target_status = local_metadata and
        EntryEntity.isEntryRead(local_metadata.status) == EntryEntity.isEntryRead(new_status)

    if is_already_target_status then
        return false
    end

    -- Smart queue logic: try direct API call if online, queue only if failed or offline
    local NetworkMgr = require("ui/network/manager")
    local success = false

    if NetworkMgr:isOnline() then
        -- Online: Try direct API call first

        -- Step 1: Optimistic update (immediate UX)
        local optimistic_success = EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
        if not optimistic_success then
            return false
        end

        -- Step 2: Try immediate API call
        success = self:tryUpdateEntryStatus(entry_id, new_status)

        if success then
            return true
        else
            -- Fall through to queue logic below
        end
    else
        -- Offline: Do optimistic update only
        local optimistic_success = EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
        if not optimistic_success then
            return false
        end
    end

    -- Queue for later sync (either because offline or API call failed)
    local queue_success = self:enqueueStatusChange(entry_id, {
        new_status = new_status,
        original_status = original_status
    })

    if queue_success then
        success = true
    else
        -- Optimistic update still provides immediate UX even if queue fails
        success = true
    end


    return success
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
        Notification:success(_("Local entry deleted successfully"))

        -- Open Miniflux folder
        EntryEntity.openMinifluxFolder()

        return true
    else
        Notification:error(_("Failed to delete local entry: ") .. tostring(ok))
        return false
    end
end

return EntryService
