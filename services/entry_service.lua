local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")
local T = require("ffi/util").template
local Notification = require("utils/notification")
local logger = require("logger")

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
    local DataStorage = require("datastorage")
    local miniflux_dir = DataStorage:getDataDir() .. "/miniflux"
    return miniflux_dir .. "/status_queue.lua"
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
        return queue_data
    else
        logger.warn("Failed to load status queue, starting fresh: " .. tostring(queue_data))
        return {}
    end
end

---Save the status queue to disk
---@param queue table Queue data to save
---@return boolean success
function EntryService:saveQueue(queue)
    local queue_file = self:getQueueFilePath()
    
    -- Ensure miniflux directory exists
    local miniflux_dir = queue_file:match("(.+)/[^/]+$")
    local success, err = Files.createDirectory(miniflux_dir)
    if not success then
        logger.err("Failed to create miniflux directory: " .. tostring(err))
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
        logger.err("Failed to save status queue: " .. tostring(write_err))
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
        logger.warn("Cannot queue invalid entry ID: " .. tostring(entry_id))
        return false
    end
    
    local queue = self:loadQueue()
    
    -- Add/update entry in queue (automatic deduplication via entry_id key)
    queue[entry_id] = {
        new_status = opts.new_status,
        original_status = opts.original_status,
        timestamp = os.time()
    }
    
    local success = self:saveQueue(queue)
    if success then
        logger.info("Queued status change for entry " .. entry_id .. ": " .. opts.original_status .. " -> " .. opts.new_status)
    end
    
    return success
end

---Process the status queue when network is available
---@return boolean success
function EntryService:processStatusQueue()
    local queue = self:loadQueue()
    local queue_size = 0
    for _ in pairs(queue) do queue_size = queue_size + 1 end
    
    if queue_size == 0 then
        return true -- Nothing to process
    end
    
    logger.info("Processing status queue with " .. queue_size .. " entries")
    
    -- Show notification to user
    Notification:info(_("Syncing ") .. queue_size .. _(" status changes..."))
    
    local processed_count = 0
    local failed_entries = {}
    
    -- Process each queued entry
    for entry_id, opts in pairs(queue) do
        -- Smart check: verify if sync is still needed by checking local metadata
        local local_metadata = EntryEntity.loadMetadata(entry_id)
        local current_status = local_metadata and local_metadata.status or "unread"
        local is_already_synced = EntryEntity.isEntryRead(current_status) == EntryEntity.isEntryRead(opts.new_status)
        
        if is_already_synced then
            -- Entry already in desired state, remove from queue
            processed_count = processed_count + 1
            logger.info("Entry " .. entry_id .. " already synced to " .. opts.new_status .. ", removing from queue")
        else
            -- Still needs sync, try API call
            local success = self:tryUpdateEntryStatus(entry_id, opts.new_status)
            if success then
                processed_count = processed_count + 1
                logger.info("Successfully synced entry " .. entry_id .. " status to " .. opts.new_status)
            else
                -- Keep failed entries in queue for next attempt
                failed_entries[entry_id] = opts
                logger.warn("Failed to sync entry " .. entry_id .. " status, keeping in queue")
            end
        end
    end
    
    -- Save remaining failed entries back to queue
    local save_success = self:saveQueue(failed_entries)
    
    if processed_count > 0 then
        logger.info("Successfully processed " .. processed_count .. "/" .. queue_size .. " queued status changes")
        if processed_count == queue_size then
            Notification:success(_("All status changes synced successfully"))
        else
            Notification:info(_("Synced ") .. processed_count .. "/" .. queue_size .. _(" status changes"))
        end
    end
    
    return save_success
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
        -- Update local metadata on success
        EntryEntity.updateEntryStatus(entry_id, new_status)
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

    -- Use batch API call
    local result, err = self.miniflux_api:updateEntries(entry_ids, {
        body = { status = "read" },
        dialogs = {
            loading = { text = progress_message },
            success = { text = _("Successfully marked ") .. #entry_ids .. _(" entries as read") },
            error = { text = _("Failed to mark entries as read") }
        }
    })

    if err then
        return false
    else
        -- TODO: Create EntryEntity.updateEntriesStatus(entry_ids, status) for batch local metadata updates
        -- Currently doing individual updates which could be optimized for large selections
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "read")
        end
        
        -- Invalidate caches so next navigation shows updated counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()
        
        return true
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

    -- Use batch API call
    local result, err = self.miniflux_api:updateEntries(entry_ids, {
        body = { status = "unread" },
        dialogs = {
            loading = { text = progress_message },
            success = { text = _("Successfully marked ") .. #entry_ids .. _(" entries as unread") },
            error = { text = _("Failed to mark entries as unread") }
        }
    })

    if err then
        return false
    else
        -- TODO: Create EntryEntity.updateEntriesStatus(entry_ids, status) for batch local metadata updates
        -- Currently doing individual updates which could be optimized for large selections
        for _, entry_id in ipairs(entry_ids) do
            EntryEntity.updateEntryStatus(entry_id, "unread")
        end
        
        -- Invalidate caches so next navigation shows updated counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()
        
        return true
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
---@return boolean success
function EntryService:changeEntryStatus(entry_id, new_status)
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
            error = { text = error_text }
        }
    })

    if err then
        -- Error dialog already shown by API system
        return false
    else
        -- Update local metadata
        EntryEntity.updateEntryStatus(entry_id, new_status)
        
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
---@param opts {file_path: string} Options containing file path
function EntryService:onReaderReady(opts)
    local file_path = opts.file_path
    self:autoMarkAsRead(file_path)
end

---Auto-mark miniflux entry as read if enabled
---@param file_path string File path to process
function EntryService:autoMarkAsRead(file_path)
    -- Check if auto-mark-as-read is enabled
    if not self.settings.mark_as_read_on_open then
        logger.info("Auto-mark-as-read is disabled, skipping")
        return
    end

    -- Check if current document is a miniflux HTML file
    if not EntryEntity.isMinifluxEntry(file_path) then
        logger.info("Not a miniflux entry, skipping auto-mark")
        return
    end

    -- Extract entry ID from path
    local entry_id = EntryEntity.extractEntryIdFromPath(file_path)
    if not entry_id then
        logger.warn("Could not extract entry ID from path: " .. tostring(file_path))
        return
    end

    logger.info("Auto-marking miniflux entry " .. entry_id .. " as read (onReaderReady)")

    -- Spawn update status to "read"
    local pid = self:spawnUpdateStatus(entry_id, "read")
    if pid then
        logger.info("Auto-mark spawned with PID: " .. tostring(pid))
    else
        logger.info("Auto-mark skipped (feature disabled)")
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

    -- Use utility functions for button text and callback
    local mark_button_text = EntryEntity.getStatusButtonText(entry_status)
    local mark_callback
    if EntryEntity.isEntryRead(entry_status) then
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "unread")
        end
    else
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "read")
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

    -- Show dialog and return reference for caller management
    UIManager:show(dialog)
    return dialog
end

-- =============================================================================
-- PRIVATE HELPER METHODS
-- =============================================================================

---Update entry status in background subprocess
---@param entry_id number Entry ID to update
---@param new_status string New status ("read" or "unread")
---@return number|nil pid Process ID if spawned, nil if disabled
function EntryService:spawnUpdateStatus(entry_id, new_status)
    -- Check if auto-mark feature is enabled
    if not self.settings.mark_as_read_on_open then
        return nil
    end

    -- Validate entry ID first
    if not EntryEntity.isValidId(entry_id) then
        return nil
    end

    -- Load current metadata to get original status for auto-healing
    local local_metadata = EntryEntity.loadMetadata(entry_id)
    local original_status = local_metadata and local_metadata.status or "unread"

    -- Smart check: First check local metadata to avoid unnecessary work
    local is_already_target_status = local_metadata and
        EntryEntity.isEntryRead(local_metadata.status) == EntryEntity.isEntryRead(new_status)

    if is_already_target_status then
        return nil
    end

    -- Check connectivity before making API call
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then
        -- Main thread - safe to queue immediately when offline
        self:enqueueStatusChange(entry_id, {
            new_status = new_status,
            original_status = original_status
        })
        logger.info("Queued status change for offline processing: entry " .. entry_id)
        return nil -- Skip subprocess when offline
    end

    -- Step 1: Queue the operation first (handles all failure scenarios)
    self:enqueueStatusChange(entry_id, {
        new_status = new_status,
        original_status = original_status
    })

    -- Step 2: Optimistic update - immediately update local metadata
    local update_success = EntryEntity.updateEntryStatus(entry_id, new_status)
    
    -- NOTE: We deliberately do NOT invalidate caches here because:
    -- 1. This is fire-and-forget background operation - user doesn't expect immediate UI updates
    -- 2. API call happens in subprocess and could fail, causing auto-healing to revert local metadata
    -- 3. If we invalidate cache but API fails, cache shows wrong counts until next natural refresh
    -- 4. Cache will refresh naturally when user navigates later
    -- For immediate user-triggered operations, use changeEntryStatus() which invalidates after API success

    -- Step 2: Background API call with auto-healing
    local FFIUtil = require("ffi/util")

    -- Extract settings data for subprocess (separate memory space)
    local server_address = self.settings.server_address
    local api_token = self.settings.api_token

    local pid = FFIUtil.runInSubProcess(function()
        -- Create a minimal settings object for the subprocess
        local subprocess_settings = {
            server_address = server_address,
            api_token = api_token
        }

        -- Import and recreate our API clients (they have separate memory space)
        local APIClient = require("api/api_client")
        local MinifluxAPI = require("api/miniflux_api")

        -- Create API client instances inside subprocess
        local api_client = APIClient:new({ settings = subprocess_settings })
        local miniflux_api = MinifluxAPI:new({ api_client = api_client })

        -- Use our proper API layer with built-in timeout handling
        local result, err = miniflux_api:updateEntries(entry_id, {
            body = { status = new_status }
            -- No dialogs config - silent background operation
        })

        if err then
            -- Auto-healing: If API call failed, revert local metadata
            local EntryEntity = require("entities/entry_entity")
            local revert_success = EntryEntity.updateEntryStatus(entry_id, original_status)
        end

        -- Process exits automatically - no return value needed for fire-and-forget
        -- Note: Entry remains queued and will be processed by queue processor on next network event
        -- Queue processor will check actual status and only sync if still needed
    end)

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
