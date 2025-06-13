--[[--
Legacy Browser utilities (to be deprecated)

This legacy file contains some remaining utility functions. Most functionality
has been moved to specialized modules in browser/utils/.

@module koplugin.miniflux.browser.browser_utils
@deprecated Use specialized modules in browser/utils/ instead
--]]--

local _ = require("gettext")

local BrowserUtils = {}

---Convert table to string representation for serialization
---@param tbl table Table to convert
---@param indent? number Current indentation level
---@return string String representation of table
function BrowserUtils.tableToString(tbl, indent)
    indent = indent or 0
    local result = {}
    local spaces = string.rep("  ", indent)
    
    table.insert(result, "{\n")
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
        local value
        if type(v) == "string" then
            value = string.format('"%s"', v:gsub('"', '\\"'))
        elseif type(v) == "table" then
            value = BrowserUtils.tableToString(v, indent + 1)
        else
            value = tostring(v)
        end
        table.insert(result, string.format("%s  [%s] = %s,\n", spaces, key, value))
    end
    table.insert(result, spaces .. "}")
    
    return table.concat(result)
end

---Get API options based on current settings
---@param settings SettingsManager Settings manager instance
---@return ApiOptions Options for API calls
function BrowserUtils.getApiOptions(settings)
    local options = {
        limit = settings:getLimit(),
        order = settings:getOrder(),
        direction = settings:getDirection(),
    }
    
    -- Use server-side filtering based on settings
    local hide_read_entries = settings:getHideReadEntries()
    if hide_read_entries then
        -- Only fetch unread entries
        options.status = {"unread"}
    else
        -- Fetch both read and unread entries, but never "removed" ones
        options.status = {"unread", "read"}
    end
    
    return options
end

-- Note: All entry processing functionality has been moved to:
-- - browser/utils/entry_utils.lua (main coordination)
-- - browser/utils/progress_utils.lua (progress tracking)
-- - browser/utils/image_utils.lua (image processing)
-- - browser/utils/html_utils.lua (HTML document creation)
-- - browser/utils/navigation_utils.lua (entry navigation)

return BrowserUtils 