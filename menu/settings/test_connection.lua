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
            local success, result = api:testConnection({
                dialogs = {
                    loading = {
                        text = _("Testing connection to Miniflux server...")
                    }
                }
            })

            -- Show the result message (API handles loading and validation automatically)
            UIManager:show(InfoMessage:new({
                text = result, -- API provides good success/error messages
                timeout = success and 3 or 5,
            }))
        end,
    }
end

return TestConnection
