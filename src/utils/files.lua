local lfs = require('libs/libkoreader-lfs')
local Error = require('utils/error')
local logger = require('logger')

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

---@class OpenWithReaderCallbacks
---@field before_open? function Callback executed before opening the file
---@field on_ready? function Callback executed after ReaderUI is ready

---@class MinifluxContext
---@field type string Context type ("feed", "category", "global", "local")
---@field id? number Feed or category ID
---@field ordered_entries? table[] Ordered entries for navigation

---@class OpenWithReaderOptions : OpenWithReaderCallbacks
---@field context? MinifluxContext Optional navigation context to attach to ReaderUI.instance

---Open a file with ReaderUI and optional callbacks
---@param file_path string Path to the file to open
---@param opts? OpenWithReaderOptions Options including callbacks and context
---@return nil
function Files.openWithReader(file_path, opts)
    opts = opts or {}
    local context = opts.context

    -- Execute pre-open callback if provided
    if opts.before_open then
        opts.before_open()
    end

    -- Open the file
    local ReaderUI = require('apps/reader/readerui')

    -- Save navigation context to cache if provided
    if context then
        local BrowserCache = require('utils/browser_cache')
        BrowserCache.save(context)
    end

    -- Show the reader
    ReaderUI:showReader(file_path)

    -- Handle post-ready callback if provided
    -- Note: This won't work reliably because showReader is async
    -- Callbacks should be registered through the plugin system instead
    if opts.on_ready then
        logger.warn(
            '[Miniflux:Files] on_ready callback may not work reliably with async showReader'
        )
    end
end

return Files
