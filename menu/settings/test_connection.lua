--[[--
Test Connection Settings Component

Handles connection testing to the Miniflux server.

@module miniflux.menu.settings.test_connection
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
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

            -- Format result message based on API response
            local message
            if success then
                message = _("Connection successful! Logged in as: ") .. result.username
            else
                message = result -- Error message from API
            end

            UIManager:show(InfoMessage:new({
                text = message,
                timeout = success and 3 or 5,
            }))
        end,
    }
end

return TestConnection
