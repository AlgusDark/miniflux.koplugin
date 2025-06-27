--[[--
Test Connection Settings Component

Handles connection testing to the Miniflux server.

@module miniflux.menu.settings.test_connection
--]]

local Notification = require("utils/notification")
local _ = require("gettext")

local TestConnection = {}

---Get the menu item for connection testing
---@param api MinifluxAPI API client instance
---@return table Menu item configuration
function TestConnection.getMenuItem(api)
    return {
        text = _("Test connection"),
        keep_menu_open = true,
        callback = function()
            local success, result = api:get("/me", {
                dialogs = {
                    loading = {
                        text = _("Testing connection to Miniflux server...")
                    }
                }
            })

            -- Show result based on API response
            if success then
                Notification:success(_("Connection successful! Logged in as: ") .. result.username)
            else
                Notification:error(result) -- Error message from API
            end
        end,
    }
end

return TestConnection
