local lfs = require('libs/libkoreader-lfs')
local DataStorage = require('datastorage')
local logger = require('logger')

-- **Browser Cache** - Simple file-based cache for browser navigation context
-- Stores the current browsing context (feed/category/global) to preserve
-- navigation scope when moving between entries
local BrowserCache = {}

---Get the path to the browser context cache file
---@return string file_path
function BrowserCache.getCacheFilePath()
    return DataStorage:getSettingsDir() .. '/miniflux_browser_context.lua'
end

---Save navigation context to cache file
---@param context {type: string, id?: number} Navigation context
---@return boolean success
function BrowserCache.save(context)
    if not context then
        return false
    end

    local cache_file = BrowserCache.getCacheFilePath()

    -- Convert context to Lua code
    local content = 'return {\n'
    content = content .. string.format('  type = %q,\n', context.type or 'global')
    if context.id then
        content = content .. string.format('  id = %d,\n', context.id)
    end
    content = content .. '}\n'

    -- Write to file
    local file = io.open(cache_file, 'w')
    if not file then
        logger.err('[Miniflux:BrowserCache] Failed to open cache file for writing')
        return false
    end

    local write_success = file:write(content)
    file:close()

    if not write_success then
        logger.err('[Miniflux:BrowserCache] Failed to write to cache file')
        return false
    end

    return true
end

---Load navigation context from cache file
---@return {type: string, id?: number}|nil context
function BrowserCache.load()
    local cache_file = BrowserCache.getCacheFilePath()

    -- Check if file exists
    if not lfs.attributes(cache_file, 'mode') then
        return nil
    end

    -- Load and execute the Lua file
    local success, context = pcall(dofile, cache_file)
    if success and type(context) == 'table' then
        return context
    else
        logger.err('[Miniflux:BrowserCache] Failed to load context cache')
        return nil
    end
end

---Clear the context cache
---@return boolean success
function BrowserCache.clear()
    local cache_file = BrowserCache.getCacheFilePath()

    -- Check if file exists before trying to remove it
    local file_exists = lfs.attributes(cache_file, 'mode') == 'file'

    if not file_exists then
        return true -- File doesn't exist, so it's already "cleared"
    end

    -- Remove the cache file
    local success = os.remove(cache_file)
    if success then
        return true
    else
        logger.err('[Miniflux:BrowserCache] Failed to clear cache')
        return false
    end
end

return BrowserCache
