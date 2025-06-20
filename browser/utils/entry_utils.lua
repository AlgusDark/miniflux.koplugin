--[[--
Entry Utilities for Miniflux Browser

This module provides UI coordination for entry operations and legacy navigation.
Core entry logic is handled by EntryService. This module primarily manages
the end-of-entry dialog and navigation between entries.

@module miniflux.browser.utils.entry_utils
--]] --

---@class EntryMetadata
---@field id number Entry ID
---@field title string Entry title
---@field url? string Entry URL
---@field status string Entry status ("read" or "unread")
---@field published_at? string Publication timestamp
---@field images_included boolean Whether images were downloaded
---@field images_count number Number of images processed

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

-- UI coordination imports
local ReaderUI = require("apps/reader/readerui")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")

-- Navigation functionality (for legacy navigation methods)
local NavigationContext = require("utils/navigation_context")

-- Import the Entry entity and service
local Entry = require("entities/entry/entry")
local EntryService = require("entities/entry/entry_service")
local NavigationService = require("services/navigation_service")
local MetadataLoader = require("utils/metadata_loader")

---@class EntryUtils UI coordination for entry operations and navigation
---@field settings MinifluxSettings Settings instance
---@field entry_service EntryService Entry service for business logic
---@field navigation_service NavigationService Navigation service for entry navigation
---@field _current_miniflux_entry table|nil Current entry info for dialogs
---@field _current_end_dialog table|nil Current end-of-entry dialog
local EntryUtils = {}
EntryUtils.__index = EntryUtils

---Create a new EntryUtils instance
---@param settings MinifluxSettings Settings instance
---@return EntryUtils
function EntryUtils:new(settings)
    local instance = {
        settings = settings,
        entry_service = EntryService:new(settings),
        navigation_service = NavigationService:new(settings),
        _current_miniflux_entry = nil,
        _current_end_dialog = nil,
    }
    setmetatable(instance, self)
    return instance
end

---Show an entry by downloading and opening it (delegates to EntryService)
---@param params {entry: MinifluxEntry, browser?: table}
function EntryUtils:showEntry(params)
    -- Delegate to EntryService for orchestration
    return self.entry_service:readEntry(params.entry, params.browser)
end

---Download and process an entry with images (delegates to EntryService)
---@param params {entry: MinifluxEntry, browser?: table}
function EntryUtils:downloadEntry(params)
    -- Delegate to EntryService for orchestration
    return self.entry_service:readEntry(params.entry, params.browser)
end

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@return nil
function EntryUtils:openEntryFile(html_file)
    -- Close any existing EndOfBook dialog first (prevent stacking like OPDS pattern)
    self:closeEndOfEntryDialog()

    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil

    if is_miniflux_entry then
        -- Extract entry ID from path for later use
        local entry_id = html_file:match("/miniflux/(%d+)/")

        if entry_id then
            -- Update global navigation context with this entry
            -- Note: We don't have browsing context when opening existing files,
            -- so navigation will be global unless the user came from a browser session
            local NavigationContext = require("utils/navigation_context")
            local entry_id_num = tonumber(entry_id)
            if entry_id_num then
                if not NavigationContext.hasValidContext() then
                    -- Set global context if no context exists
                    NavigationContext.setGlobalContext(entry_id_num)
                else
                    -- Update current entry in existing context
                    NavigationContext.updateCurrentEntry(entry_id_num)
                end
            end
        end

        -- Store the entry info for the EndOfBook event handler
        self._current_miniflux_entry = {
            file_path = html_file,
            entry_id = entry_id
        }
    end

    -- Open the file - EndOfBook event handler will detect miniflux entries automatically
    ReaderUI:showReader(html_file)
end

---Show end of entry dialog with navigation options
---@param params? table Optional parameters (kept for backward compatibility)
---@return nil
function EntryUtils:showEndOfEntryDialog(params)
    local current_entry = self._current_miniflux_entry
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
            self:markEntryAsUnread(current_entry)
        end
    else
        mark_callback = function()
            self:markEntryAsRead(current_entry)
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
                                self:navigateToPreviousEntry(current_entry)
                            end)
                        end,
                    },
                    {
                        text = _("Next →"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                self:navigateToNextEntry(current_entry)
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
                                self:deleteLocalEntry(current_entry)
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
                                self:openMinifluxFolder(current_entry)
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
function EntryUtils:closeEndOfEntryDialog()
    if self._current_end_dialog then
        UIManager:close(self._current_end_dialog)
        self._current_end_dialog = nil
    end
end

-- =============================================================================
-- NAVIGATION FUNCTIONS (DELEGATES TO NAVIGATION SERVICE)
-- =============================================================================

---Navigate to the previous entry (delegates to NavigationService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:navigateToPreviousEntry(entry_info)
    -- Delegate to NavigationService for complex navigation logic
    self.navigation_service:navigateToPreviousEntry(entry_info, self)
end

---Navigate to the next entry (delegates to NavigationService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:navigateToNextEntry(entry_info)
    -- Delegate to NavigationService for complex navigation logic
    self.navigation_service:navigateToNextEntry(entry_info, self)
end

---Download and show an entry (delegates to EntryService)
---@param entry MinifluxEntry Entry to download and show
---@return nil
function EntryUtils:downloadAndShowEntry(entry)
    -- Delegate to EntryService for orchestration
    self.entry_service:readEntry(entry)
end

---Mark an entry as read (delegates to EntryService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:markEntryAsRead(entry_info)
    local entry_id = entry_info.entry_id
    local entry_id_num = tonumber(entry_id)

    -- Delegate to EntryService for orchestration
    self.entry_service:markAsRead(entry_id_num)
end

---Mark an entry as unread (delegates to EntryService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:markEntryAsUnread(entry_info)
    local entry_id = entry_info.entry_id
    local entry_id_num = tonumber(entry_id)

    -- Delegate to EntryService for orchestration
    self.entry_service:markAsUnread(entry_id_num)
end

---Delete a local entry (delegates to EntryService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:deleteLocalEntry(entry_info)
    local entry_id = entry_info.entry_id
    local entry_id_num = tonumber(entry_id)

    if not entry_id_num then
        UIManager:show(InfoMessage:new {
            text = _("Cannot delete: invalid entry ID"),
            timeout = 3,
        })
        return
    end

    -- Delegate to EntryService for orchestration
    self.entry_service:deleteLocalEntry(entry_id_num)
end

---Open the Miniflux folder in file manager (delegates to EntryService)
---@param entry_info table Current entry information
---@return nil
function EntryUtils:openMinifluxFolder(entry_info)
    -- Delegate to EntryService for orchestration
    self.entry_service:openMinifluxFolder()
end

return EntryUtils
