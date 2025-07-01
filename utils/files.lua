--[[--
File Operations Utilities

Consolidated file utilities including basic file operations and metadata loading.
Combines functionality from file_utils and metadata_loader for better organization.

@module miniflux.utils.files
--]]

local lfs = require("libs/libkoreader-lfs")

local Files = {}

-- =============================================================================
-- BASIC FILE OPERATIONS
-- =============================================================================

---Remove trailing slashes from a string
---@param s string String to remove trailing slashes from
---@return string String with trailing slashes removed
function Files.rtrimSlashes(s)
    local n = #s
    while n > 0 and s:find("^/", n) do
        n = n - 1
    end
    return s:sub(1, n)
end

---Write content to a file
---@param file_path string Path to write to
---@param content string Content to write
---@return boolean True if successful
function Files.writeFile(file_path, content)
    local file = io.open(file_path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

-- =============================================================================
-- METADATA LOADING
-- =============================================================================

---@class EntryMetadata
---@field id number
---@field title string
---@field url string
---@field status string
---@field published_at string
---@field feed table

---Load current entry metadata from DocSettings
---@param entry_info table Entry information with file_path and entry_id
---@return EntryMetadata|nil Metadata table or nil if failed
function Files.loadCurrentEntryMetadata(entry_info)
    if not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    local html_file = entry_info.file_path
    local DocSettings = require("docsettings")

    -- Check if HTML file exists
    if lfs.attributes(html_file, "mode") ~= "file" then
        return nil
    end

    local doc_settings = DocSettings:open(html_file)

    -- Check if this is actually a miniflux entry by checking for our metadata
    local entry_id = doc_settings:readSetting("miniflux_entry_id")
    if not entry_id then
        return nil
    end

    -- Return metadata in the same structure as before for compatibility
    return {
        id = entry_id,
        title = doc_settings:readSetting("miniflux_title"),
        url = doc_settings:readSetting("miniflux_url"),
        status = doc_settings:readSetting("miniflux_status"),
        published_at = doc_settings:readSetting("miniflux_published_at"),
        feed = {
            id = doc_settings:readSetting("miniflux_feed_id"),
            title = doc_settings:readSetting("miniflux_feed_title"),
        },
        category = {
            id = doc_settings:readSetting("miniflux_category_id"),
            title = doc_settings:readSetting("miniflux_category_title"),
        },
        images_included = doc_settings:readSetting("miniflux_images_included"),
        images_count = doc_settings:readSetting("miniflux_images_count"),
    }
end

return Files
