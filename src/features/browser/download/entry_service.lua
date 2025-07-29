local FFIUtil = require('ffi/util')
local _ = require('gettext')
local logger = require('logger')
local NetworkMgr = require('ui/network/manager')

local EntryEntity = require('domains/entries/entry_entity')
local QueueService = require('features/sync/services/queue_service')

-- **Entry Service** - Handles background processing and reader events.
--
-- Core service for entry operations excluding queue management, workflows, and data access.
-- Data access: handled by domains (entries, feeds, categories)
-- Status changes: handled by vertical slices (reader modules, browser services)
-- Workflows: handled by workflow modules (download_entry, batch_download_entries_workflow)
-- Queue management: handled by QueueService
-- Responsibilities: background processing, reader events, subprocess management
---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field feeds Feeds
---@field categories Categories
---@field entries Entries
---@field miniflux_plugin Miniflux
---@field queue_service QueueService
---@field entry_subprocesses table Track subprocesses per entry (entry_id -> pid)
local EntryService = {}

---@class EntryServiceDeps
---@field settings MinifluxSettings
---@field feeds Feeds
---@field categories Categories
---@field entries Entries
---@field miniflux_plugin Miniflux
---@field queue_service QueueService

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
        queue_service = deps.queue_service,
        entry_subprocesses = {}, -- Track subprocesses per entry
    }
    setmetatable(instance, self)
    self.__index = self

    return instance
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
    -- Extract settings data for subprocess (separate memory space)
    local server_address = self.settings.server_address
    local api_token = self.settings.api_token

    local pid = FFIUtil.runInSubProcess(function()
        -- Import required modules in subprocess
        local MinifluxAPI = require('api/miniflux_api')
        -- selene: allow(shadowing)
        local EntryEntity = require('domains/entries/entry_entity')
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
            -- selene: allow(shadowing)
            local QueueService = require('features/sync/services/queue_service')
            QueueService.removeFromEntryStatusQueue(entry_id)
        end
        -- Process exits automatically
    end)

    -- If subprocess couldn't start or we're offline, queue for later
    if not pid or not NetworkMgr:isOnline() then
        -- Fallback to queue for offline sync
        logger.info(
            '[Miniflux:EntryService] Subprocess failed or offline - queueing status change for entry',
            entry_id
        )

        -- Perform optimistic local update for immediate UX
        EntryEntity.updateEntryStatus(entry_id, {
            new_status = new_status,
            doc_settings = doc_settings,
        })

        -- Queue for later sync when online
        QueueService.enqueueStatusChange(entry_id, {
            new_status = new_status,
            original_status = original_status,
        })

        return nil -- No PID since subprocess didn't start
    else
        -- Track subprocess for this entry
        self.entry_subprocesses[entry_id] = pid
    end

    return pid
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

return EntryService
