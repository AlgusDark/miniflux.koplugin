local Notification = require("utils/notification")
local _ = require("gettext")

-- **Test Connection Settings** - Handles connection testing to the Miniflux
-- server.
local TestConnection = {}

---Get the menu item for connection testing
---@param miniflux_api MinifluxAPI Miniflux API instance
---@return table Menu item configuration
function TestConnection.getMenuItem(miniflux_api)
    return {
        text = _("Test connection"),
        keep_menu_open = true,
        callback = function()
            local result, err = miniflux_api:getMe({
                dialogs = {
                    loading = {
                        text = _("Testing connection to Miniflux server...")
                    }
                }
            })

            -- Show result based on API response
            if err then
                Notification:error(err.message) -- Error message from API
            else
                ---@cast result -nil
                Notification:success(_("Connection successful! Logged in as: ") .. result.username)
            end
        end,
    }
end

return TestConnection
