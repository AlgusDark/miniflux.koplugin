local _ = require('gettext')
local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local EntryPaths = require('domains/utils/entry_paths')
local EntryMetadata = require('domains/utils/entry_metadata')
local QueueService = require('features/sync/services/queue_service')

-- **Entry Batch Operations Service** - Browser-specific batch operations for entries
--
-- Handles selection-based batch operations like marking entries as read/unread.
-- This is a browser-specific service following vertical slice architecture.
local EntryBatchOperations = {}

---@class BatchOperationDeps
---@field entries Entries Entry domain for API calls

---Private function to handle batch status change with API fallback to queue
---@param entry_ids table Array of entry IDs
---@param new_status string New status ("read" or "unread")
---@param deps BatchOperationDeps Dependencies
---@return boolean success
local function batchChangeStatus(entry_ids, new_status, deps)
    if not entry_ids or #entry_ids == 0 then
        return false
    end

    -- Prepare status-specific messages
    local progress_message, success_message, offline_message
    if new_status == 'read' then
        progress_message = _('Marking ') .. #entry_ids .. _(' entries as read...')
        success_message = _('Successfully marked ') .. #entry_ids .. _(' entries as read')
        offline_message = _('Marked as read (will sync when online)')
    else -- 'unread'
        progress_message = _('Marking ') .. #entry_ids .. _(' entries as unread...')
        success_message = _('Successfully marked ') .. #entry_ids .. _(' entries as unread')
        offline_message = _('Marked as unread (will sync when online)')
    end

    -- Show loading message with forceRePaint before API call
    local loading_widget = InfoMessage:new({
        text = progress_message,
    })
    UIManager:show(loading_widget)
    UIManager:forceRePaint()

    -- Try batch API call first
    local _result, err = deps.entries:updateEntries(entry_ids, {
        body = { status = new_status },
    })

    -- Close loading message
    UIManager:close(loading_widget)

    if not err then
        -- Check ReaderUI once for efficiency (instead of checking for each entry)
        local current_entry_id = nil
        local doc_settings = nil

        local ReaderUI = require('apps/reader/readerui')
        if ReaderUI.instance and ReaderUI.instance.document then
            local current_file = ReaderUI.instance.document.file
            if EntryPaths.isMinifluxEntry(current_file) then
                current_entry_id = EntryPaths.extractEntryIdFromPath(current_file)
                doc_settings = ReaderUI.instance.doc_settings
            end
        end

        -- API success - update local metadata
        for _, entry_id in ipairs(entry_ids) do
            -- Pass doc_settings only if this entry is currently open
            local entry_doc_settings = (entry_id == current_entry_id) and doc_settings or nil
            EntryMetadata.updateEntryStatus(entry_id, {
                new_status = new_status,
                doc_settings = entry_doc_settings,
            })
            -- Remove from queue since server is now source of truth
            QueueService.removeFromEntryStatusQueue(entry_id)
        end

        -- Show success notification
        UIManager:show(InfoMessage:new({
            text = success_message,
            timeout = 2,
        }))

        -- Invalidate caches so next navigation shows updated counts
        local MinifluxEvent = require('shared/event')
        MinifluxEvent:broadcastMinifluxInvalidateCache()

        return true
    else
        -- API failed - use queue fallback with better UX messaging
        -- Perform optimistic local updates immediately for good UX
        local original_status = (new_status == 'read') and 'unread' or 'read' -- Assume opposite

        for _, entry_id in ipairs(entry_ids) do
            EntryMetadata.updateEntryStatus(entry_id, { new_status = new_status })
            -- Queue each entry for later sync
            QueueService.enqueueStatusChange(entry_id, {
                new_status = new_status,
                original_status = original_status,
            })
        end

        -- Show simple offline message
        UIManager:show(InfoMessage:new({
            text = offline_message,
        }))

        return true -- Still successful from user perspective
    end
end

---Mark multiple entries as read in batch
---@param entry_ids table Array of entry IDs
---@param deps BatchOperationDeps Dependencies
---@return boolean success
function EntryBatchOperations.markEntriesAsRead(entry_ids, deps)
    return batchChangeStatus(entry_ids, 'read', deps)
end

---Mark multiple entries as unread in batch
---@param entry_ids table Array of entry IDs
---@param deps BatchOperationDeps Dependencies
---@return boolean success
function EntryBatchOperations.markEntriesAsUnread(entry_ids, deps)
    return batchChangeStatus(entry_ids, 'unread', deps)
end

return EntryBatchOperations
