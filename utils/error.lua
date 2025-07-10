local _ = require("gettext")

-- **Error** - Simple error handling utility that provides consistent error
-- objects. Focuses on what we actually need: standardized error objects with
-- message property.
---@class Error # Error object with message property
---@field message string
local Error = {}

-- =============================================================================
-- ERROR CONSTRUCTION
-- =============================================================================

---Create a new error object
---@param message string Human-readable error message
---@return Error # Error object with message property
function Error.new(message)
    return {
        message = message or _("Unknown error occurred")
    }
end

return Error
