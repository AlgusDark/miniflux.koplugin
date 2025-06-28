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

---Load current entry metadata from filesystem
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Metadata table or nil if failed
function Files.loadCurrentEntryMetadata(entry_info)
    if not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    local entry_dir = entry_info.file_path:match("(.*)/entry%.html$")
    if not entry_dir then
        return nil
    end

    local metadata_file = entry_dir .. "/metadata.lua"
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return nil
    end

    local success, metadata = pcall(dofile, metadata_file)
    if success and metadata then
        return metadata
    end

    return nil
end

return Files
