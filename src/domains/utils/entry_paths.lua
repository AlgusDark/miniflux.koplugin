local DataStorage = require('datastorage')
local lfs = require('libs/libkoreader-lfs')
local ReaderUI = require('apps/reader/readerui')
local FileManager = require('apps/filemanager/filemanager')
local _ = require('gettext')
local logger = require('logger')

-- **Entry Path Utilities** - Pure filesystem and path operations for entries
-- Handles directory structures, file paths, and basic file operations
local EntryPaths = {}

---Get the base download directory for all entries
---@return string Download directory path
function EntryPaths.getDownloadDir()
    return ('%s/%s/'):format(DataStorage:getFullDataDir(), 'miniflux')
end

---Get the local directory path for a specific entry
---@param entry_id number Entry ID
---@return string Entry directory path
function EntryPaths.getEntryDirectory(entry_id)
    return EntryPaths.getDownloadDir() .. tostring(entry_id) .. '/'
end

---Get the local HTML file path for a specific entry
---@param entry_id number Entry ID
---@return string HTML file path
function EntryPaths.getEntryHtmlPath(entry_id)
    return EntryPaths.getEntryDirectory(entry_id) .. 'entry.html'
end

---Check if file path is a miniflux entry
---@param file_path string File path to check
---@return boolean true if miniflux entry, false otherwise
function EntryPaths.isMinifluxEntry(file_path)
    if not file_path then
        return false
    end
    return file_path:match('/miniflux/') and file_path:match('%.html$')
end

---Extract entry ID from miniflux file path
---@param file_path string File path to check
---@return number|nil entry_id Entry ID or nil if not a miniflux entry
function EntryPaths.extractEntryIdFromPath(file_path)
    if not EntryPaths.isMinifluxEntry(file_path) then
        return nil
    end

    local entry_id_str = file_path:match('/miniflux/(%d+)/')
    return entry_id_str and tonumber(entry_id_str)
end

---Check if an entry is downloaded (has HTML file)
---@param entry_id number Entry ID
---@return boolean downloaded True if entry is downloaded locally
function EntryPaths.isEntryDownloaded(entry_id)
    local html_file = EntryPaths.getEntryHtmlPath(entry_id)
    return lfs.attributes(html_file, 'mode') == 'file'
end

---Delete a local entry and its files
---@param entry_id number Entry ID
---@return boolean success True if deletion succeeded
function EntryPaths.deleteLocalEntry(entry_id)
    local _ = require('gettext')
    local UIManager = require('ui/uimanager')
    local InfoMessage = require('ui/widget/infomessage')
    local FFIUtil = require('ffi/util')

    local entry_dir = EntryPaths.getEntryDirectory(entry_id)
    local ok = FFIUtil.purgeDir(entry_dir)

    if ok then
        -- Invalidate download cache for this entry
        local MinifluxBrowser = require('features/browser/miniflux_browser')
        MinifluxBrowser.deleteEntryInfoCache(entry_id)
        logger.dbg(
            '[Miniflux:EntryPaths] Invalidated download cache after deleting entry',
            entry_id
        )
        UIManager:show(InfoMessage:new({
            text = _('Local entry deleted successfully'),
            timeout = 2,
        }))

        -- Open Miniflux folder
        EntryPaths.openMinifluxFolder()

        return true
    else
        UIManager:show(InfoMessage:new({
            text = _('Failed to delete local entry: ') .. tostring(ok),
            timeout = 5,
        }))
        return false
    end
end

---Open the Miniflux folder in file manager
---@return nil
function EntryPaths.openMinifluxFolder()
    local download_dir = EntryPaths.getDownloadDir()

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(download_dir)
    else
        FileManager:showFiles(download_dir)
    end
end

return EntryPaths
