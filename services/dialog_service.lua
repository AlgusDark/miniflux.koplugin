--[[--
Dialog Service for Miniflux Entries

This service handles end-of-entry dialog creation, management, and lifecycle.
Provides clean separation between dialog UI logic and entry coordination.

@module miniflux.services.dialog_service
--]] --

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")

-- Import dependencies
local Entry = require("entities/entry/entry")
local MetadataLoader = require("utils/metadata_loader")

---@class DialogService
---@field _current_end_dialog table|nil Current end-of-entry dialog reference
local DialogService = {}

---Create a new DialogService instance
---@return DialogService
function DialogService:new()
    local instance = {
        _current_end_dialog = nil,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- DIALOG MANAGEMENT
-- =============================================================================

---Show end of entry dialog with navigation and action options
---@param current_entry table Current entry info with file_path and entry_id
---@param entry_utils table EntryUtils instance for callback delegation
---@return nil
function DialogService:showEndOfEntryDialog(current_entry, entry_utils)
    if not current_entry then
        return
    end

    -- Close any existing EndOfBook dialog first (prevent stacking)
    self:closeEndOfEntryDialog()

    -- Load entry metadata to check current status with error handling
    local metadata = nil
    local metadata_success = pcall(function()
        metadata = MetadataLoader.loadCurrentEntryMetadata(current_entry)
    end)

    if not metadata_success then
        -- If metadata loading fails, assume unread status
        metadata = { status = "unread" }
    end

    -- Create Entry entity from metadata for business logic
    local entry_status = metadata and metadata.status or "unread"
    local entry = Entry:new({
        id = current_entry.entry_id and tonumber(current_entry.entry_id),
        status = entry_status
    })

    -- Use entity logic for button text and callback
    local mark_button_text = entry:getToggleButtonText()
    local mark_callback
    if entry:isRead() then
        mark_callback = function()
            entry_utils:markEntryAsUnread(current_entry)
        end
    else
        mark_callback = function()
            entry_utils:markEntryAsRead(current_entry)
        end
    end

    -- Create dialog and store reference for later cleanup with error handling
    local dialog_success = pcall(function()
        self._current_end_dialog = ButtonDialogTitle:new {
            title = _("You've reached the end of the entry."),
            title_align = "center",
            buttons = {
                {
                    {
                        text = _("← Previous"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                entry_utils:navigateToPreviousEntry(current_entry)
                            end)
                        end,
                    },
                    {
                        text = _("Next →"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                entry_utils:navigateToNextEntry(current_entry)
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⚠ Delete local entry"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                entry_utils:deleteLocalEntry(current_entry)
                            end)
                        end,
                    },
                    {
                        text = mark_button_text,
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                mark_callback()
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⌂ Miniflux folder"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                entry_utils:openMinifluxFolder(current_entry)
                            end)
                        end,
                    },
                    {
                        text = _("Cancel"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                        end,
                    },
                },
            },
        }

        UIManager:show(self._current_end_dialog)
    end)

    if not dialog_success then
        -- If dialog creation fails, show a simple error message
        UIManager:show(InfoMessage:new {
            text = _("Failed to create end of entry dialog"),
            timeout = 3,
        })
    end
end

---Close any existing EndOfEntry dialog
---@return nil
function DialogService:closeEndOfEntryDialog()
    if self._current_end_dialog then
        UIManager:close(self._current_end_dialog)
        self._current_end_dialog = nil
    end
end

return DialogService
