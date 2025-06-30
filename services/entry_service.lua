--[[--
Entry Service

This service handles complex entry workflows and orchestration.
It coordinates between the Entry entity, repositories, and infrastructure services
to provide high-level entry operations including UI coordination, navigation,
and dialog management.

@module koplugin.miniflux.services.entry_service
--]]

local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")
local T = require("ffi/util").template
local Notification = require("utils/notification")

-- Import dependencies
local EntryUtils = require("utils/entry_utils")
local Navigation = require("utils/navigation")
local Files = require("utils/files")
local EntryDownloader = require("services/entry_downloader")

---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field miniflux_plugin Miniflux Plugin instance for context management
local EntryService = {}

---Create a new EntryService instance
---@param settings MinifluxSettings Settings instance
---@param miniflux_api MinifluxAPI Miniflux API instance
---@param miniflux_plugin Miniflux Plugin instance for context management
---@return EntryService
function EntryService:new(settings, miniflux_api, miniflux_plugin)
    local instance = {
        settings = settings,
        miniflux_api = miniflux_api,
        miniflux_plugin = miniflux_plugin,
    }
    setmetatable(instance, self)
    self.__index = self



    return instance
end

-- =============================================================================
-- ENTRY READING WORKFLOW
-- =============================================================================

---Read an entry (download if needed and open)
---@param entry_data table Raw entry data from API
---@param browser? MinifluxBrowser Browser instance to close
---@return boolean success
function EntryService:readEntry(entry_data, browser)
    -- Validate entry data with enhanced validation
    local valid, error_msg = EntryUtils.validateForDownload(entry_data)
    if not valid then
        Notification:error(error_msg)
        return false
    end

    -- Download entry if needed
    local success = self:downloadEntryContent(entry_data, browser)
    if not success then
        Notification:error(_("Failed to download and show entry"))
        return false
    end

    return true
end

---Download entry content using EntryDownloader with progress tracking
---@param entry_data table Entry data from API
---@param browser? MinifluxBrowser Browser instance to close
---@return boolean success
function EntryService:downloadEntryContent(entry_data, browser)
    return EntryDownloader.startCancellableDownload({
        entry_data = entry_data,
        settings = self.settings,
        browser = browser
    })
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

---Change entry status with validation and side effects
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:changeEntryStatus(entry_id, new_status)
    if not EntryUtils.isValidId(entry_id) then
        Notification:error(_("Cannot change status: invalid entry ID"))
        return false
    end

    -- Prepare status messages using templates
    local loading_text = T(_("Marking entry as %1..."), new_status)
    local success_text = T(_("Entry marked as %1"), new_status)
    local error_text = T(_("Failed to mark entry as %1"), new_status)

    -- Call API with automatic dialog management
    local success, result = self.miniflux_api:updateEntries(entry_id, {
        body = { status = new_status },
        dialogs = {
            loading = { text = loading_text },
            success = { text = success_text },
            error = { text = error_text }
        }
    })

    if success then
        -- Update local metadata
        EntryUtils.updateEntryStatus(entry_id, new_status)
        return true
    else
        -- Error dialog already shown by API system
        return false
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

    -- Load entry metadata to check current status with error handling
    local metadata = nil
    local metadata_success = pcall(function()
        metadata = Files.loadCurrentEntryMetadata(entry_info)
    end)

    if not metadata_success then
        -- If metadata loading fails, assume unread status
        metadata = { status = "unread" }
    end

    -- Use status for business logic
    local entry_status = metadata and metadata.status or "unread"

    -- Use utility functions for button text and callback
    local mark_button_text = EntryUtils.getStatusButtonText(entry_status)
    local mark_callback
    if EntryUtils.isEntryRead(entry_status) then
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "unread")
        end
    else
        mark_callback = function()
            self:changeEntryStatus(entry_info.entry_id, "read")
        end
    end

    -- Create dialog and return reference for caller management
    local dialog = nil
    local dialog_success = pcall(function()
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
                            if not EntryUtils.isValidId(entry_info.entry_id) then
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
                        end,
                    },
                },
                {
                    {
                        text = _("⌂ Miniflux folder"),
                        callback = function()
                            UIManager:close(dialog)
                            EntryUtils.openMinifluxFolder()
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
    end)

    if dialog_success and dialog then
        -- Show dialog and return reference for caller management
        UIManager:show(dialog)
        return dialog
    else
        -- If dialog creation fails, show a simple error message
        Notification:error(_("Failed to create end of entry dialog"))
        return nil
    end
end

-- =============================================================================
-- PRIVATE HELPER METHODS
-- =============================================================================

---Delete a local entry
---@param entry_id number Entry ID
---@return boolean success
function EntryService:deleteLocalEntry(entry_id)
    local entry_dir = EntryUtils.getEntryDirectory(entry_id)

    local success = pcall(function()
        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end
        FFIUtil.purgeDir(entry_dir)
        return true
    end)

    if success then
        Notification:success(_("Local entry deleted successfully"))

        -- Open Miniflux folder
        EntryUtils.openMinifluxFolder()

        return true
    else
        Notification:error(_("Failed to delete local entry"))
        return false
    end
end

return EntryService
