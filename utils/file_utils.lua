--[[--
File Utilities

This utility module provides file and string operations for the Miniflux plugin.
Contains only functions that are actually used (YAGNI principle).

@module miniflux.utils.file_utils
--]]

local FileUtils = {}

---Remove trailing slashes from a string
---@param s string String to remove trailing slashes from
---@return string String with trailing slashes removed
function FileUtils.rtrimSlashes(s)
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
function FileUtils.writeFile(file_path, content)
    local file = io.open(file_path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

return FileUtils
