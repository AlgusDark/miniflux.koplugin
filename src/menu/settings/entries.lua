local InputDialog = require('ui/widget/inputdialog')
local UIManager = require('ui/uimanager')
local Notification = require('src/utils/notification')
local _ = require('gettext')
local T = require('ffi/util').template

-- **Entries Limit Settings** - Handles entries limit configuration dialog.
local Entries = {}

---Get the menu item for entries limit configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function Entries.getMenuItem(settings)
    return {
        text_func = function()
            return T(_('Entries limit - %1'), settings.limit)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            Entries.showDialog(settings, function()
                touchmenu_instance:updateItems()
            end)
        end,
    }
end

---Show entries limit configuration dialog
---@param settings MinifluxSettings Settings instance
---@param refresh_callback? function Optional callback to refresh the menu after saving
---@return nil
function Entries.showDialog(settings, refresh_callback)
    local current_limit = tostring(settings.limit)

    local limit_dialog
    limit_dialog = InputDialog:new({
        title = _('Entries limit'),
        input = current_limit,
        input_type = 'number',
        buttons = {
            {
                {
                    text = _('Cancel'),
                    callback = function()
                        UIManager:close(limit_dialog)
                    end,
                },
                {
                    text = _('Save'),
                    is_enter_default = true,
                    callback = function()
                        local new_limit = tonumber(limit_dialog:getInputText())
                        if new_limit and new_limit > 0 then
                            settings.limit = new_limit
                            settings:save()
                            UIManager:close(limit_dialog)
                            Notification:success(_('Entries limit saved'))
                            -- Refresh the menu to show updated limit
                            if refresh_callback then
                                refresh_callback()
                            end
                        else
                            Notification:warning(_('Please enter a valid number greater than 0'))
                        end
                    end,
                },
            },
        },
    })
    UIManager:show(limit_dialog)
    limit_dialog:onShowKeyboard()
end

return Entries
