local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")
local Error = require("utils/error")
local _ = require("gettext")

-- **Entry Entity** - Pure utility functions for entry operations, validation,
-- and business logic. Delegates file operations to Files utilities while
-- maintaining business logic.
local EntryEntity = {}

---Get the base download directory for all entries
---@return string Download directory path
function EntryEntity.getDownloadDir()
    return ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
end

---Get the local directory path for a specific entry
---@param entry_id number Entry ID
---@return string Entry directory path
function EntryEntity.getEntryDirectory(entry_id)
    return EntryEntity.getDownloadDir() .. tostring(entry_id) .. "/"
end

---Get the local HTML file path for a specific entry
---@param entry_id number Entry ID
---@return string HTML file path
function EntryEntity.getEntryHtmlPath(entry_id)
    return EntryEntity.getEntryDirectory(entry_id) .. "entry.html"
end

-- =============================================================================
-- VALIDATION UTILITIES
-- =============================================================================

---Check if entry ID is valid
---@param entry_id any Entry ID to validate
---@return boolean True if valid number > 0
function EntryEntity.isValidId(entry_id)
    return type(entry_id) == "number" and entry_id > 0
end

---Check if entry has content to display
---@param entry_data table Entry data from API
---@return boolean True if has content
function EntryEntity.hasContent(entry_data)
    local content = entry_data.content or entry_data.summary or ""
    return content ~= ""
end

---Validate entry data for download (enhanced with better error handling)
---@param entry_data table Entry data from API
---@return boolean|nil result, Error|nil error
function EntryEntity.validateForDownload(entry_data)
    if not entry_data or type(entry_data) ~= "table" then
        return nil, Error.new(_("Invalid entry data"))
    end

    if not EntryEntity.isValidId(entry_data.id) then
        return nil, Error.new(_("Invalid entry ID"))
    end

    if not EntryEntity.hasContent(entry_data) then
        return nil, Error.new(_("No content available for this entry"))
    end

    return true, nil
end

-- =============================================================================
-- STATUS UTILITIES
-- =============================================================================

---Check if entry is read
---@param status string Entry status
---@return boolean True if entry is read
function EntryEntity.isEntryRead(status)
    return status == "read"
end

---Get the appropriate toggle button text for current status
---@param status string Entry status
---@return string Button text for marking entry
function EntryEntity.getStatusButtonText(status)
    if EntryEntity.isEntryRead(status) then
        return _("✓ Mark as unread")
    else
        return _("✓ Mark as read")
    end
end

-- =============================================================================
-- FILE PATH UTILITIES
-- =============================================================================

---Check if file path is a miniflux entry
---@param file_path string File path to check
---@return boolean true if miniflux entry, false otherwise
function EntryEntity.isMinifluxEntry(file_path)
    if not file_path then
        return false
    end
    return file_path:match("/miniflux/") and file_path:match("%.html$")
end

---Extract entry ID from miniflux file path
---@param file_path string File path to check
---@return number|nil entry_id Entry ID or nil if not a miniflux entry
function EntryEntity.extractEntryIdFromPath(file_path)
    if not EntryEntity.isMinifluxEntry(file_path) then
        return nil
    end

    local entry_id_str = file_path:match("/miniflux/(%d+)/")
    return entry_id_str and tonumber(entry_id_str)
end

-- =============================================================================
-- FILE OPERATIONS
-- =============================================================================

---Check if entry is already downloaded locally
---@param entry_id number Entry ID
---@return boolean True if downloaded
function EntryEntity.isEntryDownloaded(entry_id)
    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    return lfs.attributes(html_file, "mode") == "file"
end

-- =============================================================================
-- METADATA OPERATIONS
-- =============================================================================

---@class EntryMetadata
---@field id number
---@field title string
---@field url string
---@field status string
---@field published_at string
---@field feed table

---Save metadata for an entry using DocSettings
---@param params table Parameters: entry_data, include_images, images_count
---@return string|nil result, Error|nil error
function EntryEntity.saveMetadata(params)
    local entry_data = params.entry_data
    if not entry_data or not entry_data.id then
        return nil, Error.new("Invalid entry data")
    end

    local include_images = params.include_images or false
    local images_count = params.images_count or 0

    local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)
    if not html_file then
        return nil, Error.new("Could not determine HTML file path")
    end

    local DocSettings = require("docsettings")
    local doc_settings = DocSettings:open(html_file)

    -- Prepare all settings
    local settings = {
        miniflux_entry_id = entry_data.id,
        miniflux_title = entry_data.title,
        miniflux_url = entry_data.url,
        miniflux_status = entry_data.status,
        miniflux_published_at = entry_data.published_at,
        miniflux_images_included = include_images,
        miniflux_images_count = images_count,
        miniflux_last_updated = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    }

    -- Add nested data safely
    if entry_data.feed then
        settings.miniflux_feed_id = entry_data.feed.id
        settings.miniflux_feed_title = entry_data.feed.title

        if entry_data.feed.category then
            settings.miniflux_category_id = entry_data.feed.category.id
            settings.miniflux_category_title = entry_data.feed.category.title
        end
    end

    -- Save all non-nil settings
    for key, value in pairs(settings) do
        if value ~= nil then
            doc_settings:saveSetting(key, value)
        end
    end

    -- Return original pattern: flush result (string|nil) and error
    local flush_result = doc_settings:flush()
    return flush_result, nil
end

---Update local entry status using DocSettings
---@param entry_id number Entry ID
---@param new_status string New status ("read" or "unread")
---@return boolean success
function EntryEntity.updateEntryStatus(entry_id, new_status)
    -- Use the new updateMetadata function for consistency
    local doc_settings, err = EntryEntity.updateMetadata(entry_id, {
        miniflux_status = new_status
    })

    if err then
        return false
    end

    local success = doc_settings ~= nil
    return success
end

---Load metadata for an entry using DocSettings
---@param entry_id number Entry ID
---@return EntryMetadata|nil Metadata table or nil if failed
function EntryEntity.loadMetadata(entry_id)
    if not EntryEntity.isValidId(entry_id) then
        return nil
    end

    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil
    end

    local DocSettings = require("docsettings")

    -- Use KOReader's pattern for checking sidecar existence
    if not DocSettings:hasSidecarFile(html_file) then
        return nil
    end

    local doc_settings = DocSettings:open(html_file)

    -- Check if this is actually a miniflux entry
    local stored_entry_id = doc_settings:readSetting("miniflux_entry_id")
    if not stored_entry_id then
        return nil
    end

    -- Batch read all settings into a local table for efficiency
    local settings_keys = {
        "miniflux_title", "miniflux_url", "miniflux_status",
        "miniflux_published_at", "miniflux_feed_id", "miniflux_feed_title",
        "miniflux_category_id", "miniflux_category_title",
        "miniflux_images_included", "miniflux_images_count",
        "miniflux_last_updated"
    }

    local settings = {}
    for _, key in ipairs(settings_keys) do
        settings[key] = doc_settings:readSetting(key)
    end

    -- Return structured metadata
    return {
        id = stored_entry_id,
        title = settings.miniflux_title,
        url = settings.miniflux_url,
        status = settings.miniflux_status,
        published_at = settings.miniflux_published_at,
        feed = {
            id = settings.miniflux_feed_id,
            title = settings.miniflux_feed_title,
        },
        category = {
            id = settings.miniflux_category_id,
            title = settings.miniflux_category_title,
        },
        images_included = settings.miniflux_images_included,
        images_count = settings.miniflux_images_count,
        last_updated = settings.miniflux_last_updated,
    }
end

---Update metadata for an entry with flexible field updates
---@param entry_id number Entry ID
---@param updates table Key-value pairs of fields to update (must be miniflux_ prefixed)
---@return DocSettings|nil doc_settings, Error|nil error
function EntryEntity.updateMetadata(entry_id, updates)
    if not EntryEntity.isValidId(entry_id) then
        return nil, Error.new("Invalid entry ID")
    end

    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil, Error.new("Could not determine HTML file path")
    end

    local DocSettings = require("docsettings")

    -- Force fresh load to avoid stale cache issues
    local doc_settings = DocSettings:open(html_file)

    -- Check if this is actually a miniflux entry
    local stored_entry_id = doc_settings:readSetting("miniflux_entry_id")
    if not stored_entry_id then
        return nil, Error.new("No miniflux metadata found")
    end

    -- Update only the specified fields
    for key, value in pairs(updates) do
        if key:match("^miniflux_") then -- Safety check for miniflux fields
            doc_settings:saveSetting(key, value)
        end
    end

    -- Add timestamp
    doc_settings:saveSetting("miniflux_last_updated", os.date("%Y-%m-%d %H:%M:%S", os.time()))

    local flush_result = doc_settings:flush()
    if flush_result then
        return doc_settings, nil
    else
        return nil, Error.new("Failed to flush DocSettings")
    end
end

-- =============================================================================
-- UI UTILITIES
-- =============================================================================

---Show cancellation choice dialog with context-aware options
---@param context "during_images" | "after_images"
---@return string|nil User choice based on context (nil if dialog fails)
function EntryEntity.showCancellationDialog(context)
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
                "Entry creation was interrupted.\nImages have been downloaded successfully.\n\nWhat would you like to do?"),
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
function EntryEntity.openMinifluxFolder()
    local download_dir = EntryEntity.getDownloadDir()

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(download_dir)
    else
        FileManager:showFiles(download_dir)
    end
end

return EntryEntity
