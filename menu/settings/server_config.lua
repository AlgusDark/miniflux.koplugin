--[[--
Server Configuration Settings Component

Handles server address and API token configuration dialog.

@module miniflux.menu.settings.server_config
--]]

local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ServerConfig = {}

---Get the menu item for server configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function ServerConfig.getMenuItem(settings)
    return {
        text = _("Server Settings"),
        keep_menu_open = true,
        callback = function()
            ServerConfig.showDialog(settings)
        end,
    }
end

---Show server configuration dialog
---@param settings MinifluxSettings Settings instance
---@return nil
function ServerConfig.showDialog(settings)
    local server_address = settings.server_address
    local api_token = settings.api_token

    local settings_dialog
    settings_dialog = MultiInputDialog:new({
        title = _("Miniflux server settings"),
        fields = {
            {
                text = server_address,
                input_type = "string",
                hint = _("Server address (e.g., https://miniflux.example.com)"),
            },
            {
                text = api_token,
                input_type = "string",
                hint = _("API Token"),
                text_type = "password",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        if fields[1] and fields[1] ~= "" then
                            settings.server_address = fields[1]
                        end
                        if fields[2] and fields[2] ~= "" then
                            settings.api_token = fields[2]
                        end
                        settings:save()
                        UIManager:show(InfoMessage:new({
                            text = _("Settings saved"),
                            timeout = 2,
                        }))
                        UIManager:close(settings_dialog)
                    end,
                },
            },
        },
    })
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

return ServerConfig
