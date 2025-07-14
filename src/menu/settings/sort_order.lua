local UIManager = require('ui/uimanager')
local Notification = require('src/utils/notification')
local _ = require('gettext')
local T = require('ffi/util').template

-- **Sort Order Settings** - Handles "sort order" submenu with various sorting
-- options.
local SortOrder = {}

---Get display names for sort orders
---@return table<string, string> Mapping of order keys to display names
local function getSortOrderNames()
    return {
        id = _('ID'),
        status = _('Status'),
        published_at = _('Published date'),
        category_title = _('Category title'),
        category_id = _('Category ID'),
    }
end

---Get the menu item for sort order configuration
---@param settings MinifluxSettings Settings instance
---@return table Menu item configuration
function SortOrder.getMenuItem(settings)
    return {
        text_func = function()
            local order_names = getSortOrderNames()
            local current_order = settings.order
            local order_name = order_names[current_order] or _('Published date')
            return T(_('Sort order - %1'), order_name)
        end,
        keep_menu_open = true,
        sub_item_table_func = function()
            return SortOrder.getSubMenu(settings)
        end,
    }
end

---Get sort order submenu items
---@param settings MinifluxSettings Settings instance
---@return table[] Sort order menu items
function SortOrder.getSubMenu(settings)
    local current_order = settings.order

    return {
        {
            text = _('ID') .. (current_order == 'id' and ' ✓' or ''),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortOrder.updateSetting({
                    settings = settings,
                    new_order = 'id',
                    touchmenu_instance = touchmenu_instance,
                })
            end,
        },
        {
            text = _('Status') .. (current_order == 'status' and ' ✓' or ''),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortOrder.updateSetting({
                    settings = settings,
                    new_order = 'status',
                    touchmenu_instance = touchmenu_instance,
                })
            end,
        },
        {
            text = _('Published date') .. (current_order == 'published_at' and ' ✓' or ''),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortOrder.updateSetting({
                    settings = settings,
                    new_order = 'published_at',
                    touchmenu_instance = touchmenu_instance,
                })
            end,
        },
        {
            text = _('Category title') .. (current_order == 'category_title' and ' ✓' or ''),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortOrder.updateSetting({
                    settings = settings,
                    new_order = 'category_title',
                    touchmenu_instance = touchmenu_instance,
                })
            end,
        },
        {
            text = _('Category ID') .. (current_order == 'category_id' and ' ✓' or ''),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                SortOrder.updateSetting({
                    settings = settings,
                    new_order = 'category_id',
                    touchmenu_instance = touchmenu_instance,
                })
            end,
        },
    }
end

---Update sort order setting
---@param opts table Options containing settings, new_order, touchmenu_instance
---@return nil
function SortOrder.updateSetting(opts)
    -- Extract parameters from opts
    local settings = opts.settings
    local new_order = opts.new_order
    local touchmenu_instance = opts.touchmenu_instance

    settings.order = new_order
    settings:save()

    local notification = Notification:success(_('Sort order updated'), { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        touchmenu_instance:backToUpperMenu()
    end)
end

return SortOrder
