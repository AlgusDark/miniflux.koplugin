--[[--
Entry Utilities

Pure utility functions for entry operations, validation, and file management.
Replaces the Entry entity with simpler, more maintainable functions.

@module koplugin.miniflux.utils.entry_utils
--]] --

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
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

---Get the local metadata file path for a specific entry
---@param entry_id number Entry ID
---@return string Metadata file path
function EntryUtils.getEntryMetadataPath(entry_id)
    return EntryUtils.getEntryDirectory(entry_id) .. "metadata.lua"
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

---Validate entry data for download
---@param entry_data table Entry data from API
---@return boolean success, string? error_message
function EntryUtils.validateForDownload(entry_data)
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

---Create metadata for an entry
---@param params table Parameters: entry_data, include_images, images_count
---@return table Metadata table
function EntryUtils.createMetadata(params)
    local entry_data = params.entry_data
    local include_images = params.include_images or false
    local images_count = params.images_count or 0

    return {
        -- Entry identification
        id = entry_data.id,
        title = entry_data.title,
        url = entry_data.url,

        -- Entry status and properties
        status = entry_data.status,
        published_at = entry_data.published_at,

        -- Image processing results
        images_included = include_images,
        images_count = images_count
    }
end

return EntryUtils
