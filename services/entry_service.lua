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

-- **Entry Service** - Handles complex entry workflows and orchestration.
--
-- It coordinates between the Entry entity, repositories, and infrastructure
-- services to provide high-level entry operations including UI coordination,
-- navigation, and dialog management.
---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field miniflux_plugin Miniflux Plugin instance for context management
local EntryService = {}

---Create a new EntryService instance
---@param deps table Dependencies containing settings, miniflux_api, miniflux_plugin
---@return EntryService
function EntryService:new(deps)
    local instance = {
        settings = deps.settings,
        miniflux_api = deps.miniflux_api,
        miniflux_plugin = deps.miniflux_plugin,
    }
    setmetatable(instance, self)
    self.__index = self



    return instance
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
        return true
    end
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
        -- TODO: Implement offline batching - queue status changes when no network
        return nil
    end

    -- Step 1: Optimistic update - immediately update local metadata
    local update_success = EntryEntity.updateEntryStatus(entry_id, new_status)

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
