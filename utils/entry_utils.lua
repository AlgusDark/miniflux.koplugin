--[[--
Entry Utilities

Pure utility functions for entry operations, validation, and file management.
Replaces the Entry entity with simpler, more maintainable functions.

@module koplugin.miniflux.utils.entry_utils
--]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")
local _ = require("gettext")

local EntryUtils = {}

-- =============================================================================
-- DIRECTORY MANAGEMENT (STATIC)
-- =============================================================================

---Get the base download directory for all entries
---@return string Download directory path
function EntryUtils.getDownloadDir()
    return ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
end

---Get the local directory path for a specific entry
---@param entry_id number Entry ID
---@return string Entry directory path
function EntryUtils.getEntryDirectory(entry_id)
    return EntryUtils.getDownloadDir() .. tostring(entry_id) .. "/"
end

---Get the local HTML file path for a specific entry
---@param entry_id number Entry ID
---@return string HTML file path
function EntryUtils.getEntryHtmlPath(entry_id)
    return EntryUtils.getEntryDirectory(entry_id) .. "entry.html"
end

-- =============================================================================
-- VALIDATION UTILITIES
-- =============================================================================

---Check if entry ID is valid
---@param entry_id any Entry ID to validate
---@return boolean True if valid number > 0
function EntryUtils.isValidId(entry_id)
    return type(entry_id) == "number" and entry_id > 0
end

---Check if entry has content to display
---@param entry_data table Entry data from API
---@return boolean True if has content
function EntryUtils.hasContent(entry_data)
    local content = entry_data.content or entry_data.summary or ""
    return content ~= ""
end

---Validate entry data for download (enhanced with better error handling)
---@param entry_data table Entry data from API
---@return boolean success, string? error_message
function EntryUtils.validateForDownload(entry_data)
    if not entry_data or type(entry_data) ~= "table" then
        return false, _("Invalid entry data")
    end

    if not EntryUtils.isValidId(entry_data.id) then
        return false, _("Invalid entry ID")
    end

    if not EntryUtils.hasContent(entry_data) then
        return false, _("No content available for this entry")
    end

    return true
end

-- =============================================================================
-- STATUS UTILITIES
-- =============================================================================

---Check if entry is read
---@param status string Entry status
---@return boolean True if entry is read
function EntryUtils.isEntryRead(status)
    return status == "read"
end

---Get the appropriate toggle button text for current status
---@param status string Entry status
---@return string Button text for marking entry
function EntryUtils.getStatusButtonText(status)
    if EntryUtils.isEntryRead(status) then
        return _("✓ Mark as unread")
    else
        return _("✓ Mark as read")
    end
end

-- =============================================================================
-- FILE OPERATIONS
-- =============================================================================

---Check if entry is already downloaded locally
---@param entry_id number Entry ID
---@return boolean True if downloaded
function EntryUtils.isEntryDownloaded(entry_id)
    local html_file = EntryUtils.getEntryHtmlPath(entry_id)
    return lfs.attributes(html_file, "mode") == "file"
end

-- =============================================================================
-- METADATA OPERATIONS
-- =============================================================================

---Save metadata for an entry using DocSettings
---@param params table Parameters: entry_data, include_images, images_count
---@return boolean True if metadata was saved successfully
function EntryUtils.saveMetadata(params)
    local entry_data = params.entry_data
    local include_images = params.include_images or false
    local images_count = params.images_count or 0

    local html_file = EntryUtils.getEntryHtmlPath(entry_data.id)
    local DocSettings = require("docsettings")
    local doc_settings = DocSettings:open(html_file)

    -- Save flattened metadata with miniflux_ prefix
    doc_settings:saveSetting("miniflux_entry_id", entry_data.id)
    doc_settings:saveSetting("miniflux_title", entry_data.title)
    doc_settings:saveSetting("miniflux_url", entry_data.url)
    doc_settings:saveSetting("miniflux_status", entry_data.status)
    doc_settings:saveSetting("miniflux_published_at", entry_data.published_at)

    -- Feed information
    doc_settings:saveSetting("miniflux_feed_id", entry_data.feed.id)
    doc_settings:saveSetting("miniflux_feed_title", entry_data.feed.title)

    -- Category information
    doc_settings:saveSetting("miniflux_category_id", entry_data.feed.category.id)
    doc_settings:saveSetting("miniflux_category_title", entry_data.feed.category.title)

    -- Image processing results
    doc_settings:saveSetting("miniflux_images_included", include_images)
    doc_settings:saveSetting("miniflux_images_count", images_count)

    return doc_settings:flush()
end

---Update local entry status using DocSettings
---@param entry_id number Entry ID
---@param new_status string New status ("read" or "unread")
---@return boolean success
function EntryUtils.updateEntryStatus(entry_id, new_status)
    local html_file = EntryUtils.getEntryHtmlPath(entry_id)
    local DocSettings = require("docsettings")

    -- Check if HTML file exists first
    if lfs.attributes(html_file, "mode") ~= "file" then
        return false
    end

    local doc_settings = DocSettings:open(html_file)

    -- Update status
    doc_settings:saveSetting("miniflux_status", new_status)

    return doc_settings:flush()
end

-- =============================================================================
-- UI UTILITIES
-- =============================================================================

---Show cancellation choice dialog with context-aware options
---@param context "during_images" | "after_images"
---@return string User choice based on context
function EntryUtils.showCancellationDialog(context)
    local user_choice = nil
    local choice_dialog = nil

    -- Context-specific dialog configuration
    local dialog_config = {}

    if context == "during_images" then
        dialog_config = {
            title = _("Image download was cancelled.\nWhat would you like to do?"),
            buttons = {
                {
                    text = _("Cancel entry creation"),
                    choice = "cancel_entry"
                },
                {
                    text = _("Continue without images"),
                    choice = "continue_without_images"
                },
                {
                    text = _("Resume downloading"),
                    choice = "resume_downloading"
                },
            }
        }
    else -- "after_images"
        dialog_config = {
            title = _(
                "Entry creation was cancelled.\nImages have been downloaded successfully.\n\nWhat would you like to do?"),
            buttons = {
                {
                    text = _("Cancel entry creation"),
                    choice = "cancel_entry"
                },
                {
                    text = _("Continue with entry creation"),
                    choice = "continue_creation"
                },
            }
        }
    end

    -- Build button table for ButtonDialog
    local dialog_buttons = { {} }
    for _, btn in ipairs(dialog_config.buttons) do
        table.insert(dialog_buttons[1], {
            text = btn.text,
            callback = function()
                user_choice = btn.choice
                UIManager:close(choice_dialog)
            end,
        })
    end

    -- Create dialog with context-specific configuration
    choice_dialog = ButtonDialog:new {
        title = dialog_config.title,
        title_align = "center",
        dismissable = false,
        buttons = dialog_buttons,
        -- Handle tap outside dialog - behave like "Cancel entry creation"
        -- tap_close_callback = function()
        --     user_choice = "cancel_entry"
        -- end,
    }

    UIManager:show(choice_dialog)

    -- Use proper modal dialog pattern
    repeat
        UIManager:handleInput()
    until user_choice ~= nil

    return user_choice
end

---Open the Miniflux folder in file manager
---@return nil
function EntryUtils.openMinifluxFolder()
    local download_dir = EntryUtils.getDownloadDir()

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(download_dir)
    else
        FileManager:showFiles(download_dir)
    end
end

---Open an entry file with optional pre-opening configuration
---@param file_path string Path to the entry HTML file
---@param config? {before_open?: function} table Callback to execute before opening (e.g., close browser)
---@return nil
function EntryUtils.openEntry(file_path, config)
    config = config or {}

    local function doOpen()
        -- Open the file directly - context management is handled by plugin-level events
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file_path)
    end

    -- Execute pre-open callback if provided
    if config.before_open then
        config.before_open()
        -- Use nextTick to ensure proper sequencing after UI operations
        local UIManager = require("ui/uimanager")
        UIManager:nextTick(doOpen)
    else
        doOpen()
    end
end

return EntryUtils
