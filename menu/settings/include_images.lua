local UIManager = require("ui/uimanager")
local Notification = require("utils/notification")
local _ = require("gettext")

-- **Include Images Settings** - Handles "include images" submenu with ON/OFF
-- toggle for image downloading.
local IncludeImages = {}

---Get the menu item for include images configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function IncludeImages.getMenuItem(settings)
    return {
        text_func = function()
            return settings.include_images and _("Include images - ON")
                or _("Include images - OFF")
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return {
                {
                    text = _("ON") .. (settings.include_images and " ✓" or ""),
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        IncludeImages.updateSetting({
                            settings = settings,
                            new_value = true,
                            touchmenu_instance = touchmenu_instance,
                            message = _("Images will be downloaded with entries")
                        })
                    end,
                },
                {
                    text = _("OFF") .. (not settings.include_images and " ✓" or ""),
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        IncludeImages.updateSetting({
                            settings = settings,
                            new_value = false,
                            touchmenu_instance = touchmenu_instance,
                            message = _("Images will be skipped when downloading entries")
                        })
                    end,
                },
            }
        end,
    }
end

---Update include images setting
---@param options {settings: MinifluxSettings, new_value: boolean, touchmenu_instance: table, message: string} Options table containing:
---@return nil
function IncludeImages.updateSetting(options)
    options.settings.include_images = options.new_value
    options.settings:save()

    local notification = Notification:success(options.message, { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        options.touchmenu_instance:backToUpperMenu()
    end)
end

return IncludeImages
