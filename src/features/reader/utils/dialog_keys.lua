--[[--
**Dialog Key Enhancement Utility for Miniflux Plugin**

This utility adds physical key navigation to dialogs, allowing users to navigate 
between entries using page turn keys.
--]]

local UIManager = require('ui/uimanager')
local Device = require('device')

local DialogKeys = {}

---Enhance end-of-entry dialog with key event support if device has keys
---
---This function adds physical key navigation to the existing end-of-entry dialog,
---allowing users to navigate between entries using the same keys they use for page turning.
---
---Key Mapping Strategy:
---- Back Keys (RPgBack, LPgBack) - Navigate to previous entry
---- Forward Keys (RPgFwd, LPgFwd) - Navigate to next entry
---
---This mirrors the logical direction of page turning and provides an intuitive
---navigation experience for users with physical keys (Kobo, Kindle, etc.).
---
---The enhancement is applied to the existing dialog without replacing it,
---maintaining compatibility with touch-only devices while adding key support
---for devices that have physical buttons.
---
---@param dialog table Existing dialog to enhance
---@param entry_info table Entry information with file_path and entry_id
---@param miniflux_plugin table Reference to main plugin instance
---@return table Enhanced dialog (same instance, modified)
function DialogKeys.enhanceDialogWithKeys(dialog, entry_info, miniflux_plugin)
    if not dialog then
        return dialog
    end

    if not Device:hasKeys() then
        return dialog -- No physical keys, return dialog unchanged
    end

    -- Add key event handlers to the existing dialog
    dialog.key_events = dialog.key_events or {}

    -- Register key events for entry navigation
    -- Each key event maps a physical key to an event name that triggers a handler function

    -- Navigate to previous entry (logical "back" direction)
    dialog.key_events.NavigatePrevious = {
        Device.input.group.PgBack, -- Page back buttons
        event = 'NavigatePrevious',
    }

    -- Navigate to next entry (logical "forward" direction)
    dialog.key_events.NavigateNext = {
        Device.input.group.PgFwd, -- Page forward buttons
        event = 'NavigateNext',
    }

    -- Store references for navigation
    local stored_entry_info = entry_info
    local stored_plugin = miniflux_plugin

    -- Add event handlers
    function dialog:onNavigatePrevious()
        UIManager:close(self)
        local Navigation = require('features/browser/services/navigation_service')
        Navigation.navigateToEntry(stored_entry_info, {
            navigation_options = { direction = 'previous' },
            settings = stored_plugin.settings,
            miniflux_api = stored_plugin.miniflux_api,
            entry_service = stored_plugin.entry_service,
            miniflux_plugin = stored_plugin,
        })
        return true
    end

    function dialog:onNavigateNext()
        UIManager:close(self)
        local Navigation = require('features/browser/services/navigation_service')
        Navigation.navigateToEntry(stored_entry_info, {
            navigation_options = { direction = 'next' },
            settings = stored_plugin.settings,
            miniflux_api = stored_plugin.miniflux_api,
            entry_service = stored_plugin.entry_service,
            miniflux_plugin = stored_plugin,
        })
        return true
    end

    return dialog
end

return DialogKeys
