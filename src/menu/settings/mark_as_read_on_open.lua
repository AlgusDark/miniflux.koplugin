local UIManager = require('ui/uimanager')
local Notification = require('utils/notification')
local _ = require('gettext')

-- **Mark as Read on Open Settings** - Handles "mark as read on open" submenu
-- with ON/OFF toggle for automatic status updates.
local MarkAsReadOnOpen = {}

---Get the menu item for mark as read on open configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function MarkAsReadOnOpen.getMenuItem(settings)
    return {
        text_func = function()
            return settings.mark_as_read_on_open and _('Mark as read on open - ON')
                or _('Mark as read on open - OFF')
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return {
                {
                    text = _('ON') .. (settings.mark_as_read_on_open and ' ✓' or ''),
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        MarkAsReadOnOpen.updateSetting({
                            settings = settings,
                            new_value = true,
                            touchmenu_instance = touchmenu_instance,
                            message = _('Entries will be automatically marked as read when opened'),
                        })
                    end,
                },
                {
                    text = _('OFF') .. (not settings.mark_as_read_on_open and ' ✓' or ''),
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        MarkAsReadOnOpen.updateSetting({
                            settings = settings,
                            new_value = false,
                            touchmenu_instance = touchmenu_instance,
                            message = _('Entries will keep their original read status'),
                        })
                    end,
                },
            }
        end,
    }
end

---Update mark as read on open setting
---@param options {settings: MinifluxSettings, new_value: boolean, touchmenu_instance: table, message: string} Options table containing:
---@return nil
function MarkAsReadOnOpen.updateSetting(options)
    options.settings.mark_as_read_on_open = options.new_value
    options.settings:save()

    local notification = Notification:success(options.message, { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        options.touchmenu_instance:backToUpperMenu()
    end)
end

return MarkAsReadOnOpen
