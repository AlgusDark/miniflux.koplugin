local MultiInputDialog = require('ui/widget/multiinputdialog')
local UIManager = require('ui/uimanager')
local Notification = require('utils/notification')
local _ = require('gettext')

-- **Proxy Image Downloader Settings** - Handles proxy configuration for image downloads
local ProxyImageDownloader = {}

---Get the menu item for proxy image downloader configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function ProxyImageDownloader.getMenuItem(settings)
    return {
        text = _('Proxy Image Downloader'),
        keep_menu_open = true,
        callback = function()
            ProxyImageDownloader.showDialog(settings)
        end,
    }
end

---Show proxy image downloader configuration dialog
---@param settings MinifluxSettings Settings instance
---@return nil
function ProxyImageDownloader.showDialog(settings)
    local proxy_url = settings.proxy_image_downloader_url
    local proxy_token = settings.proxy_image_downloader_token

    local function showConfigDialog()
        local config_dialog
        config_dialog = MultiInputDialog:new({
            title = _('Proxy Image Downloader Settings'),
            fields = {
                {
                    text = proxy_url,
                    input_type = 'string',
                    hint = _('Proxy URL (e.g., https://example.com)'),
                },
                {
                    text = proxy_token,
                    input_type = 'string',
                    hint = _('API Token (optional)'),
                    text_type = 'password',
                },
            },
            buttons = {
                {
                    {
                        text = _('Cancel'),
                        callback = function()
                            UIManager:close(config_dialog)
                        end,
                    },
                    {
                        text = _('Save'),
                        callback = function()
                            local fields = config_dialog:getFields()
                            if fields[1] then
                                settings.proxy_image_downloader_url = fields[1]
                            end
                            if fields[2] then
                                settings.proxy_image_downloader_token = fields[2]
                            end
                            -- Auto-enable if URL is provided, disable if empty
                            settings.proxy_image_downloader_enabled = fields[1] and fields[1] ~= ''
                            settings:save()
                            Notification:success(_('Settings saved'))
                            UIManager:close(config_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(config_dialog)
        config_dialog:onShowKeyboard()
    end

    showConfigDialog()
end

return ProxyImageDownloader
