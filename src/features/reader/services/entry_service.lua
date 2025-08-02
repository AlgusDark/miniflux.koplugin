local EventListener = require('ui/widget/eventlistener')
local FFIUtil = require('ffi/util')
local NetworkMgr = require('ui/network/manager')
local _ = require('gettext')
local logger = require('logger')

local EntryPaths = require('domains/utils/entry_paths')
local EntryValidation = require('domains/utils/entry_validation')
local EntryMetadata = require('domains/utils/entry_metadata')
local QueueService = require('features/sync/services/queue_service')

-- TODO: Maybe the subprocesses should be tracked in main Miniflux instance?

-- **Reader Entry Service** - Handles reader-specific entry operations and events.
---@class ReaderEntryService : EventListener
---@field settings MinifluxSettings Settings instance
---@field feeds Feeds
---@field categories Categories
---@field entries Entries
---@field miniflux_plugin Miniflux
---@field entry_subprocesses table Track subprocesses per entry (entry_id -> pid)
local ReaderEntryService = EventListener:extend({
    entry_subprocesses = {}, -- Track subprocesses per entry
})

-- =============================================================================
-- READER EVENT HANDLING
-- =============================================================================

---Handle DocSettingsLoad event - called when document settings are loaded
---Perform auto-mark-as-read for miniflux entries with optimistic doc_settings update
---@param doc_settings DocSettings Document settings instance
---@param document table Document instance
---@return nil
function ReaderEntryService:onDocSettingsLoad(doc_settings, document)
    local file_path = document and document.file
    if not file_path then
        return
    end

    -- Check if current document is a miniflux HTML file
    if not EntryPaths.isMinifluxEntry(file_path) then
        return
    end

    -- Check if auto-mark-as-read is enabled
    if not self.settings.mark_as_read_on_open then
        return
    end

    -- Extract entry ID from path
    local entry_id = EntryPaths.extractEntryIdFromPath(file_path)
    if not entry_id then
        return
    end

    -- Check current status from doc_settings
    local current_metadata = doc_settings:readSetting('miniflux_entry')
    if not current_metadata then
        logger.warn('[Miniflux:ReaderEntryService] No miniflux metadata found for entry:', entry_id)
        return
    end

    logger.dbg('[Miniflux:ReaderEntryService] Current metadata:', current_metadata)

    -- Only auto-mark-as-read if entry is currently unread
    if current_metadata.status ~= 'read' then
        -- Optimistically update doc_settings cache immediately
        current_metadata.status = 'read'
        current_metadata.last_updated = os.date('%Y-%m-%d %H:%M:%S')
        doc_settings:saveSetting('miniflux_entry', current_metadata)

        -- Spawn subprocess for server sync
        local pid = self:spawnUpdateStatus(entry_id)
        if pid then
            logger.info('[Miniflux:ReaderEntryService] Auto-mark-as-read spawned with PID:', pid)
            -- Track the subprocess for proper cleanup
            ReaderEntryService.entry_subprocesses[entry_id] = pid
            self.miniflux_plugin:trackSubprocess(pid)
        else
            logger.dbg('[Miniflux:ReaderEntryService] Auto-mark-as-read skipped (spawn failed)')
        end
    else
        logger.dbg('[Miniflux:ReaderEntryService] Entry already marked as read, skipping auto-mark')
    end
end

-- =============================================================================
-- PUBLIC API METHODS
-- =============================================================================

---Change entry status with API sync and queue fallback
---@param entry_id number Entry ID to update
---@param new_status string New status ("read" or "unread")
---@param doc_settings? table Optional ReaderUI DocSettings instance
---@return boolean success True if status change succeeded
function ReaderEntryService:changeEntryStatus(entry_id, new_status, doc_settings)
    local T = require('ffi/util').template
    local Notification = require('shared/widgets/notification')

    if not EntryValidation.isValidId(entry_id) then
        Notification:error(_('Cannot change status: invalid entry ID'))
        return false
    end

    -- Kill any active subprocess for this entry (prevents conflicting updates)
    local pid = ReaderEntryService.entry_subprocesses[entry_id]
    if pid then
        logger.info('[Miniflux:ReaderEntryService] Killing subprocess', pid, 'for entry', entry_id)
        FFIUtil.terminateSubProcess(pid)
        ReaderEntryService.entry_subprocesses[entry_id] = nil
    end

    -- Prepare status messages using templates
    local loading_text = T(_('Marking entry as %1...'), new_status)
    local success_text = T(_('Entry marked as %1'), new_status)

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
        -- Perform optimistic local update for immediate UX
        EntryMetadata.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Queue for later sync (determine original status)
        local original_status = (new_status == 'read') and 'unread' or 'read' -- Assume opposite
        QueueService.enqueueStatusChange(entry_id, {
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
        EntryMetadata.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Remove from queue since server is now source of truth
        QueueService.removeFromEntryStatusQueue(entry_id)

        -- Invalidate caches so next navigation shows updated counts
        local MinifluxEvent = require('shared/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        return true
    end
end

-- =============================================================================
-- SYNC INFRASTRUCTURE METHODS
-- =============================================================================

---Spawn subprocess to sync entry status with server (auto-mark-as-read)
---@param entry_id number Entry ID to update
---@return number|nil pid Process ID if spawned, nil if operation skipped
function ReaderEntryService:spawnUpdateStatus(entry_id)
    local new_status = 'read'
    local original_status = 'unread'

    -- Step 1: Always add to queue first (guarantee it's queued)
    QueueService.enqueueStatusChange(entry_id, {
        new_status = new_status,
        original_status = original_status,
    })
    logger.dbg('[Miniflux:ReaderEntryService] Entry', entry_id, 'added to queue before subprocess')

    -- Step 2: Background API call in subprocess (non-blocking)
    -- Extract settings data for subprocess (separate memory space)
    local server_address = self.settings.server_address
    local api_token = self.settings.api_token

    local pid = FFIUtil.runInSubProcess(function()
        -- Import required modules in subprocess
        local MinifluxAPI = require('api/miniflux_api')
        -- selene: allow(shadowing)
        local logger = require('logger')

        -- Create API instance for subprocess with direct configuration
        local miniflux_api = MinifluxAPI:new({
            api_token = api_token,
            server_address = server_address,
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
            -- Item stays in queue for later sync, no SDR revert to avoid race conditions
            logger.dbg('[Miniflux:Subprocess] Entry', entry_id, 'remains in queue for later sync')
        else
            logger.dbg(
                '[Miniflux:Subprocess] Successfully updated entry',
                entry_id,
                'to',
                new_status
            )
            -- Remove from queue since server is now source of truth
            -- selene: allow(shadowing)
            local QueueService = require('features/sync/services/queue_service')
            QueueService.removeFromEntryStatusQueue(entry_id)
        end
        -- Process exits automatically
    end)

    -- Track subprocess if it started (item already in queue)
    if pid and NetworkMgr:isOnline() then
        ReaderEntryService.entry_subprocesses[entry_id] = pid
        logger.dbg(
            '[Miniflux:ReaderEntryService] Subprocess spawned for entry',
            entry_id,
            'with PID:',
            pid
        )
    else
        if not NetworkMgr:isOnline() then
            logger.info(
                '[Miniflux:ReaderEntryService] Device offline - entry',
                entry_id,
                'queued for later sync'
            )
        else
            logger.info(
                '[Miniflux:ReaderEntryService] Subprocess failed to start for entry',
                entry_id,
                '- item remains in queue'
            )
        end
    end

    return pid
end

---Kill any active subprocess for an entry
---@param entry_id number Entry ID
function ReaderEntryService:killEntrySubprocess(entry_id)
    local pid = ReaderEntryService.entry_subprocesses[entry_id]
    if pid then
        logger.info('[Miniflux:ReaderEntryService] Killing subprocess', pid, 'for entry', entry_id)
        FFIUtil.terminateSubProcess(pid)
        ReaderEntryService.entry_subprocesses[entry_id] = nil
    end
end

return ReaderEntryService
