--[[--
**Miniflux End of Book Module**

This module handles the end-of-book/end-of-entry dialog functionality that appears
when users reach the end of a Miniflux RSS entry. It provides navigation options,
status management, and local entry operations.

This module integrates with KOReader's event system by extending Widget and
overriding the ReaderStatus onEndOfBook behavior specifically for Miniflux entries.
--]]

local EventListener = require('ui/widget/eventlistener')
local UIManager = require('ui/uimanager')
local ButtonDialog = require('ui/widget/buttondialog')
local Notification = require('shared/widgets/notification')
local Device = require('device')
local util = require('util')
local _ = require('gettext')

local EntryEntity = require('domains/entries/entry_entity')
local QueueService = require('features/sync/services/queue_service')

---Local function to change entry status (extracted from EntryService for vertical slice architecture)
---@param entry_id number Entry ID
---@param new_status string New status ("read" or "unread")
---@param doc_settings? table Optional ReaderUI DocSettings instance
---@param miniflux Miniflux Miniflux plugin instance for accessing domains
---@return boolean success True if status change succeeded
local function changeEntryStatus(entry_id, new_status, doc_settings, miniflux)
    local T = require('ffi/util').template

    if not EntryEntity.isValidId(entry_id) then
        Notification:error(_('Cannot change status: invalid entry ID'))
        return false
    end

    -- Kill any active subprocess for this entry (prevents conflicting updates)
    -- Access through entry_service since that's where subprocess tracking lives
    if miniflux.entry_service then
        local pid = miniflux.entry_service.entry_subprocesses[entry_id]
        if pid then
            local FFIUtil = require('ffi/util')
            local logger = require('logger')
            logger.info('[Miniflux:EndOfBook] Killing subprocess', pid, 'for entry', entry_id)
            FFIUtil.terminateSubProcess(pid)
            miniflux.entry_service.entry_subprocesses[entry_id] = nil
        end
    end

    -- Prepare status messages using templates
    local loading_text = T(_('Marking entry as %1...'), new_status)
    local success_text = T(_('Entry marked as %1'), new_status)
    local _error_text = T(_('Failed to mark entry as %1'), new_status)

    -- Call API with automatic dialog management
    local _result, err = miniflux.entries:updateEntries(entry_id, {
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
        EntryEntity.updateEntryStatus(
            entry_id,
            { new_status = new_status, doc_settings = doc_settings }
        )

        -- Queue for later sync (determine original status from current metadata)
        local _metadata = EntryEntity.loadMetadata(entry_id)
        local original_status = (new_status == 'read') and 'unread' or 'read' -- Assume opposite

        -- Use queue service for queue operations
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
        EntryEntity.updateEntryStatus(
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

---@class MinifluxEndOfBook : EventListener
---@field miniflux Miniflux The main Miniflux plugin instance
---@field wrapped_method table The wrapped method object
local MinifluxEndOfBook = EventListener:extend({
    name = 'miniflux_end_of_book',
    wrapped_method = nil,
    miniflux = nil,
})

---Initialize the module and wrap the onEndOfBook method
function MinifluxEndOfBook:init()
    if self.miniflux and self.miniflux.ui and self.miniflux.ui.status then
        local reader_status = self.miniflux.ui.status

        self.wrapped_method = util.wrapMethod(reader_status, 'onEndOfBook', function(...)
            if self:shouldShowCustomDialog() then
                return self:showCustomEndOfBookDialog()
            else
                return self.wrapped_method:raw_method_call(...)
            end
        end)
    end
end

---Check if we should show custom dialog for miniflux entries
---@return boolean
function MinifluxEndOfBook:shouldShowCustomDialog()
    if
        not self.miniflux.ui
        or not self.miniflux.ui.document
        or not self.miniflux.ui.document.file
    then
        return false
    end

    local file_path = self.miniflux.ui.document.file
    -- Check if this is a miniflux HTML entry
    return file_path:match('/miniflux/') and file_path:match('%.html$')
end

---Show custom end of book dialog for miniflux entries
---@return boolean
function MinifluxEndOfBook:showCustomEndOfBookDialog()
    local file_path = self.miniflux.ui.document.file

    -- Extract entry ID from path and convert to number
    local entry_id_str = file_path:match('/miniflux/(%d+)/')
    local entry_id = entry_id_str and tonumber(entry_id_str)

    if entry_id then
        -- Show the end of entry dialog with entry info as parameter
        local entry_info = {
            file_path = file_path,
            entry_id = entry_id,
        }

        self:showDialog(entry_info)
        return true -- Handled by custom dialog
    end

    return false -- Should not happen if shouldShowCustomDialog works correctly
end

---Show end of entry dialog with navigation options
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Dialog reference for caller management or nil if failed
function MinifluxEndOfBook:showDialog(entry_info)
    if not entry_info or not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    if not self.miniflux or not self.miniflux.entry_service then
        return nil
    end

    -- Load entry metadata to check current status
    local metadata = EntryEntity.loadMetadata(entry_info.entry_id)

    -- Use status for business logic
    local entry_status = metadata and metadata.status or 'unread'

    -- Get ReaderUI's DocSettings to avoid cache conflicts
    local doc_settings = self.miniflux.ui and self.miniflux.ui.doc_settings

    -- Helper function to navigate to entry with consistent parameters
    local function navigateToEntry(direction)
        local Navigation = require('features/reader/services/navigation_service')
        Navigation.navigateToEntry(entry_info, self.miniflux, { direction = direction })
    end

    -- Use utility functions for button text and callback
    local mark_button_text = EntryEntity.getStatusButtonText(entry_status)
    local mark_callback
    if EntryEntity.isEntryRead(entry_status) then
        mark_callback = function()
            changeEntryStatus(entry_info.entry_id, 'unread', doc_settings, self.miniflux)
        end
    else
        mark_callback = function()
            changeEntryStatus(entry_info.entry_id, 'read', doc_settings, self.miniflux)
        end
    end

    -- Declare dialog variable first for proper scoping in callbacks
    ---@type ButtonDialog
    local dialog
    local buttons = {
        {
            {
                text = _('← Previous'),
                callback = function()
                    UIManager:close(dialog)
                    navigateToEntry('previous')
                end,
            },
            {
                text = _('Next →'),
                callback = function()
                    UIManager:close(dialog)
                    navigateToEntry('next')
                end,
            },
        },
        {
            {
                text = _('⚠ Delete local entry'),
                callback = function()
                    UIManager:close(dialog)
                    -- Inline deletion with validation
                    if not EntryEntity.isValidId(entry_info.entry_id) then
                        Notification:warning(_('Cannot delete: invalid entry ID'))
                        return
                    end

                    local success = EntryEntity.deleteLocalEntry(entry_info.entry_id)
                    if success then
                        local ReaderUI = require('apps/reader/readerui')
                        if ReaderUI.instance then
                            ReaderUI.instance:onClose()
                        end
                    end
                end,
            },
            {
                text = mark_button_text,
                callback = function()
                    UIManager:close(dialog)
                    mark_callback()
                end,
            },
        },
        {
            {
                text = _('⌂ Miniflux folder'),
                callback = function()
                    UIManager:close(dialog)
                    EntryEntity.openMinifluxFolder()
                end,
            },
            {
                text = _('Cancel'),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
        },
    }

    -- Create dialog and assign to the pre-declared variable
    dialog = ButtonDialog:new({
        name = 'miniflux_end_of_entry',
        title = _("You've reached the end of the entry.\nWhat would you like to do?"),
        title_align = 'center',
        buttons = buttons,
    })

    -- Enhance dialog with physical key handlers for navigation (inline)
    if Device:hasKeys() then
        -- Add key event handlers to the dialog
        ---@diagnostic disable: inject-field
        dialog.key_events = dialog.key_events or {}

        -- Navigate to previous entry (logical "back" direction)
        dialog.key_events.NavigatePrevious = {
            { Device.input.group.PgBack }, -- Page back buttons
            event = 'NavigateTo',
            args = 'previous',
        }

        -- Navigate to next entry (logical "forward" direction)
        dialog.key_events.NavigateNext = {
            { Device.input.group.PgFwd }, -- Page forward buttons
            event = 'NavigateTo',
            args = 'next',
        }
    end

    ---@param direction 'previous'|'next' # Direction of where to navigate
    -- selene: allow(shadowing)
    ---@diagnostic disable: inject-field
    function dialog:onNavigateTo(direction)
        UIManager:close(dialog)
        navigateToEntry(direction)
        return true
    end

    -- Show dialog and return reference for caller management
    UIManager:show(dialog)
    return dialog
end

---Cleanup method - revert the wrapped method
function MinifluxEndOfBook:onCloseWidget()
    if self.wrapped_method then
        self.wrapped_method:revert()
        self.wrapped_method = nil
    end
end

return MinifluxEndOfBook
