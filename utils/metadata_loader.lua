--[[--
Metadata Loader Utility for Miniflux Entries

This utility handles loading entry metadata from the filesystem for
various entry operations and navigation.

@module miniflux.utils.metadata_loader
--]] --

local lfs = require("libs/libkoreader-lfs")

local MetadataLoader = {}

---Load current entry metadata from filesystem
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Metadata table or nil if failed
function MetadataLoader.loadCurrentEntryMetadata(entry_info)
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

return MetadataLoader
