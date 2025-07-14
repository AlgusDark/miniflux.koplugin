local lfs = require('libs/libkoreader-lfs')
local Error = require('src/utils/error')

-- **Files** - Consolidated file utilities including basic file operations and
-- metadata loading. Combines functionality from file_utils and metadata_loader
-- for better organization.
local Files = {}

-- =============================================================================
-- BASIC FILE OPERATIONS
-- =============================================================================

---Remove trailing slashes from a string
---@param s string String to remove trailing slashes from
---@return string String with trailing slashes removed
function Files.rtrimSlashes(s)
    local n = #s
    while n > 0 and s:find('^/', n) do
        n = n - 1
    end
    return s:sub(1, n)
end

---Write content to a file
---@param file_path string Path to write to
---@param content string Content to write
---@return boolean|nil success, Error|nil error
function Files.writeFile(file_path, content)
    local file, errmsg = io.open(file_path, 'w')
    if not file then
        return nil, Error.new('Failed to open file for writing: ' .. (errmsg or 'unknown error'))
    end

    local success, write_errmsg = file:write(content)
    if not success then
        file:close()
        return nil, Error.new('Failed to write content: ' .. (write_errmsg or 'unknown error'))
    end

    file:close()
    return true, nil
end

---Create directory if it doesn't exist
---@param dir_path string Directory path to create
---@return boolean|nil success, Error|nil error
function Files.createDirectory(dir_path)
    if not lfs.attributes(dir_path, 'mode') then
        local success = lfs.mkdir(dir_path)
        if not success then
            return nil, Error.new('Failed to create directory')
        end
    end
    return true, nil
end

-- =============================================================================
-- READER INTEGRATION
-- =============================================================================

---Open a file with ReaderUI and optional callbacks
---@param file_path string Path to the file to open
---@param callbacks? {before_open?: function, on_ready?: function} table Optional callbacks
---@return nil
function Files.openWithReader(file_path, callbacks)
    callbacks = callbacks or {}

    -- Execute pre-open callback if provided
    if callbacks.before_open then
        callbacks.before_open()
    end

    -- Open the file
    local ReaderUI = require('apps/reader/readerui')
    ReaderUI:showReader(file_path)

    -- Register post-ready callback if provided and ReaderUI instance exists
    if callbacks.on_ready and ReaderUI.instance then
        ReaderUI.instance:registerPostReaderReadyCallback(callbacks.on_ready)
    end
end

return Files
