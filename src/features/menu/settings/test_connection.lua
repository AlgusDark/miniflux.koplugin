local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local _ = require('gettext')

-- **Test Connection Settings** - Handles connection testing to the Miniflux
-- server.
local TestConnection = {}

---Get the menu item for connection testing
---@param entries Entries Entries domain instance for connection testing
---@return table Menu item configuration
function TestConnection.getMenuItem(entries)
    return {
        text = _('Test connection'),
        keep_menu_open = true,
        callback = function()
            -- Show loading message with forceRePaint before API call
            local loading_widget = InfoMessage:new({
                text = _('Testing connection to Miniflux server...'),
            })
            UIManager:show(loading_widget)
            UIManager:forceRePaint()

            local result, err = entries:testConnection({})

            -- Close loading message
            UIManager:close(loading_widget)

            -- Show result based on API response
            if err then
                UIManager:show(InfoMessage:new({
                    text = err.message,
                    timeout = 5,
                }))
            else
                ---@cast result -nil
                UIManager:show(InfoMessage:new({
                    text = _('Connection successful! Logged in as: ') .. result.username,
                    timeout = 2,
                }))
            end
        end,
    }
end

return TestConnection
