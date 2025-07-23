--[[--
**End of Book Dialog for Miniflux Plugin**

This module handles the end-of-book/end-of-entry dialog functionality that appears
when users reach the end of a Miniflux RSS entry. It provides navigation options,
status management, and local entry operations.

The module provides two main functions:
1. Overriding KOReader's default end-of-book behavior for Miniflux entries
2. Displaying the custom end-of-entry dialog with navigation and status options

This centralizes all end-of-book dialog logic that was previously split between
main.lua and entry_service.lua.
--]]

local UIManager = require('ui/uimanager')
local ButtonDialogTitle = require('ui/widget/buttondialogtitle')
local Notification = require('utils/notification')
local Device = require('device')
local _ = require('gettext')

local EntryEntity = require('domains/entries/entry_entity')

---@class EndOfBookDialog
local EndOfBookDialog = {}

---Override ReaderStatus EndOfBook behavior to handle miniflux entries
---
---This function replaces KOReader's default end-of-book behavior with custom
---handling for Miniflux RSS entries. When a user reaches the end of a Miniflux
---entry, it shows the custom navigation dialog instead of the default behavior.
---
---@param miniflux_plugin Miniflux The main plugin instance
---@return nil
function EndOfBookDialog.overrideReaderBehavior(miniflux_plugin)
    if not miniflux_plugin.ui or not miniflux_plugin.ui.status then
        return
    end

    -- Save the original onEndOfBook method
    local original_onEndOfBook = miniflux_plugin.ui.status.onEndOfBook

    -- Replace with our custom handler
    miniflux_plugin.ui.status.onEndOfBook = function(reader_status_instance)
        -- Check if current document is a miniflux HTML file
        if
            not miniflux_plugin.ui
            or not miniflux_plugin.ui.document
            or not miniflux_plugin.ui.document.file
        then
            -- Fallback to original behavior
            return original_onEndOfBook(reader_status_instance)
        end

        local file_path = miniflux_plugin.ui.document.file

        -- Check if this is a miniflux HTML entry
        if file_path:match('/miniflux/') and file_path:match('%.html$') then
            -- Extract entry ID from path and convert to number
            local entry_id_str = file_path:match('/miniflux/(%d+)/')
            local entry_id = entry_id_str and tonumber(entry_id_str)

            if entry_id then
                -- Show the end of entry dialog with entry info as parameter
                local entry_info = {
                    file_path = file_path,
                    entry_id = entry_id,
                }

                local dependencies = {
                    settings = miniflux_plugin.settings,
                    miniflux_api = miniflux_plugin.api,
                    entry_service = miniflux_plugin.entry_service,
                    miniflux_plugin = miniflux_plugin,
                }

                EndOfBookDialog.showDialog(entry_info, dependencies)
                return -- Don't call original handler
            end
        end

        -- For non-miniflux files, use original behavior
        return original_onEndOfBook(reader_status_instance)
    end
end

---Show end of entry dialog with navigation options
---
---Creates and displays a dialog with multiple action buttons for when users
---reach the end of a Miniflux RSS entry. Provides navigation (previous/next),
---status management (mark as read/unread), local operations (delete entry),
---and folder access.
---
---@param entry_info table Entry information with file_path and entry_id
---@param dependencies table Dependencies containing settings, api, entry_service, and plugin
---@return table|nil Dialog reference for caller management or nil if failed
function EndOfBookDialog.showDialog(entry_info, dependencies)
    if not entry_info or not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    if not dependencies or not dependencies.entry_service or not dependencies.miniflux_plugin then
        return nil
    end

    -- Extract dependencies for cleaner code
    local entry_service = dependencies.entry_service
    local miniflux_plugin = dependencies.miniflux_plugin

    -- Load entry metadata to check current status
    local metadata = EntryEntity.loadMetadata(entry_info.entry_id)

    -- Use status for business logic
    local entry_status = metadata and metadata.status or 'unread'

    -- Get ReaderUI's DocSettings to avoid cache conflicts
    local doc_settings = miniflux_plugin.ui and miniflux_plugin.ui.doc_settings

    -- Helper function to navigate to entry with consistent parameters
    local function navigateToEntry(direction)
        local Navigation = require('features/reader/services/navigation_service')
        Navigation.navigateToEntry(entry_info, miniflux_plugin, { direction = direction })
    end

    -- Use utility functions for button text and callback
    local mark_button_text = EntryEntity.getStatusButtonText(entry_status)
    local mark_callback
    if EntryEntity.isEntryRead(entry_status) then
        mark_callback = function()
            entry_service:changeEntryStatus(
                entry_info.entry_id,
                { new_status = 'unread', doc_settings = doc_settings }
            )
        end
    else
        mark_callback = function()
            entry_service:changeEntryStatus(
                entry_info.entry_id,
                { new_status = 'read', doc_settings = doc_settings }
            )
        end
    end

    -- Create dialog and return reference for caller management
    ---@class dialog: ButtonDialogTitle
    local dialog = ButtonDialogTitle:new({
        title = _("You've reached the end of the entry."),
        title_align = 'center',
        buttons = {
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
                        entry_service:deleteLocalEntry(entry_info.entry_id)
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
        },
    })

    -- Enhance dialog with physical key handlers for navigation (inline)
    if Device:hasKeys() then
        -- Add key event handlers to the dialog
        dialog.key_events = dialog.key_events or {}

        -- Navigate to previous entry (logical "back" direction)
        dialog.key_events.NavigatePrevious = {
            Device.input.group.PgBack, -- Page back buttons
            event = 'NavigateTo',
            args = 'previous',
        }

        -- Navigate to next entry (logical "forward" direction)
        dialog.key_events.NavigateNext = {
            Device.input.group.PgFwd, -- Page forward buttons
            event = 'NavigateTo',
            args = 'next',
        }
    end

    ---@param direction 'previous'|'next' # Direction of where to navigate
    function dialog:onNavigateTo(direction)
        UIManager:close(self)
        navigateToEntry(direction)
        return true
    end

    -- Show dialog and return reference for caller management
    UIManager:show(dialog)
    return dialog
end

return EndOfBookDialog
