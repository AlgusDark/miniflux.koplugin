--[[--
Sort Direction Settings Component

Handles sort direction submenu with ascending/descending options.

@module miniflux.menu.settings.sort_direction
--]]

local UIManager = require("ui/uimanager")
local Notification = require("utils/notification")
local _ = require("gettext")
local T = require("ffi/util").template

local SortDirection = {}

---Get the menu item for sort direction configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function SortDirection.getMenuItem(settings)
    return {
        text_func = function()
            local direction_name = settings.direction == "asc" and _("Ascending")
                or _("Descending")
            return T(_("Sort direction - %1"), direction_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return SortDirection.getSubMenu(settings)
        end,
    }
end

---Get sort direction submenu items
---@param settings MinifluxSettings Settings instance
---@return table[] Sort direction menu items
function SortDirection.getSubMenu(settings)
    local current_direction = settings.direction

    return {
        {
            text = _("Ascending") .. (current_direction == "asc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortDirection.updateSetting({
                    settings = settings,
                    new_direction = "asc",
                    touchmenu_instance = touchmenu_instance
                })
            end,
        },
        {
            text = _("Descending") .. (current_direction == "desc" and " ✓" or ""),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortDirection.updateSetting({
                    settings = settings,
                    new_direction = "desc",
                    touchmenu_instance = touchmenu_instance
                })
            end,
        },
    }
end

---Update sort direction setting
---@param config table Configuration containing settings, new_direction, touchmenu_instance
---@return nil
function SortDirection.updateSetting(config)
    -- Extract parameters from config
    local settings = config.settings
    local new_direction = config.new_direction
    local touchmenu_instance = config.touchmenu_instance

    settings.direction = new_direction
    settings:save()

    local notification = Notification:success({
        text = _("Sort direction updated"),
        timeout = 2,
    })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        touchmenu_instance:backToUpperMenu()
    end)
end

return SortDirection
