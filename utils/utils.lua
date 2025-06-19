local logger = require("logger")
local util = require("util")

local utils = {}

---Get directory path, creating it if it doesn't exist
---@param full_dir_path string Full path to the directory
---@return string|nil Full directory path or nil if failed
function utils.getOrCreateDirectory(full_dir_path)
    -- Create the directory if it doesn't exist
    local success, err = util.makePath(full_dir_path)
    if not success then
        logger.err("Miniflux: Failed to create directory:", full_dir_path, "Error:", err)
        return nil
    end

    logger.dbg("Miniflux: Directory ready:", full_dir_path)
    return full_dir_path
end

---Remove trailing slashes from a string
---@param s string String to remove trailing slashes from
---@return string String with trailing slashes removed
function utils.rtrim_slashes(s)
    local n = #s
    while n > 0 and s:find("^/", n) do
        n = n - 1
    end
    return s:sub(1, n)
end

return utils
