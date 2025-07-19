local UIManager = require('ui/uimanager')
local MultiConfirmBox = require('ui/widget/multiconfirmbox')
local Notification = require('utils/notification')
local _ = require('gettext')

local UpdateSettings = {}

---Create update frequency selection dialog
---@param settings MinifluxSettings Settings instance
---@param callback function Callback after setting change
function UpdateSettings.showFrequencyDialog(settings, callback)
    local current_frequency = settings.auto_update_check_frequency

    local frequency_options = {
        {
            text = _('Manual only'),
            value = 'manual',
            description = _('Check for updates only when manually requested'),
        },
        {
            text = _('Daily'),
            value = 'daily',
            description = _('Check for updates once per day'),
        },
        {
            text = _('Weekly'),
            value = 'weekly',
            description = _('Check for updates once per week'),
        },
        {
            text = _('Monthly'),
            value = 'monthly',
            description = _('Check for updates once per month'),
        },
    }

    local buttons = {}
    for _, option in ipairs(frequency_options) do
        local button_text = option.text
        if option.value == current_frequency then
            button_text = button_text .. ' ✓'
        end

        table.insert(buttons, {
            text = button_text,
            callback = function()
                settings.auto_update_check_frequency = option.value

                Notification:success(string.format(_('Update frequency set to: %s'), option.text))

                if callback then
                    callback()
                end
            end,
        })
    end

    UIManager:show(MultiConfirmBox:new({
        text = _('How often should the plugin check for updates?'),
        choice1_text = buttons[1].text,
        choice1_callback = buttons[1].callback,
        choice2_text = buttons[2].text,
        choice2_callback = buttons[2].callback,
        choice3_text = buttons[3].text,
        choice3_callback = buttons[3].callback,
        choice4_text = buttons[4].text,
        choice4_callback = buttons[4].callback,
    }))
end

---Get the menu item for update settings configuration
---@param plugin table The Miniflux plugin instance
---@return table Menu item configuration
function UpdateSettings.getMenuItem(plugin)
    return {
        text = _('Updates'),
        keep_menu_open = true,
        sub_item_table_func = function()
            return UpdateSettings.getSubMenu(plugin)
        end,
    }
end

---Get update settings submenu items
---@param plugin table The Miniflux plugin instance
---@return table[] Update settings menu items
function UpdateSettings.getSubMenu(plugin)
    local CheckUpdates = require('menu/settings/check_updates')

    local settings = plugin.settings

    return {
        -- Check for updates action
        CheckUpdates.getMenuItem(plugin),

        -- Enable auto-update toggle
        {
            text = _('Enable Auto-Update'),
            checked_func = function()
                return settings.auto_update_enabled
            end,
            callback = function()
                settings.auto_update_enabled = not settings.auto_update_enabled

                local status_text = settings.auto_update_enabled and _('Auto-update enabled')
                    or _('Auto-update disabled')

                Notification:success(status_text)
            end,
        },

        -- Update frequency submenu
        {
            text_func = function()
                local frequency_map = {
                    manual = _('Manual only'),
                    daily = _('Daily'),
                    weekly = _('Weekly'),
                    monthly = _('Monthly'),
                }
                local current_frequency = frequency_map[settings.auto_update_check_frequency]
                    or _('Unknown')
                return _('Update Frequency') .. ' - ' .. current_frequency
            end,
            keep_menu_open = true,
            sub_item_table_func = function()
                return {
                    {
                        text = _('Manual only')
                            .. (settings.auto_update_check_frequency == 'manual' and ' ✓' or ''),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UpdateSettings.updateFrequencySetting({
                                settings = settings,
                                new_frequency = 'manual',
                                touchmenu_instance = touchmenu_instance,
                                message = _('Update frequency: Manual only'),
                            })
                        end,
                    },
                    {
                        text = _('Daily')
                            .. (settings.auto_update_check_frequency == 'daily' and ' ✓' or ''),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UpdateSettings.updateFrequencySetting({
                                settings = settings,
                                new_frequency = 'daily',
                                touchmenu_instance = touchmenu_instance,
                                message = _('Update frequency: Daily'),
                            })
                        end,
                    },
                    {
                        text = _('Weekly')
                            .. (settings.auto_update_check_frequency == 'weekly' and ' ✓' or ''),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UpdateSettings.updateFrequencySetting({
                                settings = settings,
                                new_frequency = 'weekly',
                                touchmenu_instance = touchmenu_instance,
                                message = _('Update frequency: Weekly'),
                            })
                        end,
                    },
                    {
                        text = _('Monthly')
                            .. (settings.auto_update_check_frequency == 'monthly' and ' ✓' or ''),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UpdateSettings.updateFrequencySetting({
                                settings = settings,
                                new_frequency = 'monthly',
                                touchmenu_instance = touchmenu_instance,
                                message = _('Update frequency: Monthly'),
                            })
                        end,
                    },
                }
            end,
        },

        -- Include beta releases toggle
        {
            text = _('Include Beta Releases'),
            help_text = _(
                'Include pre-release versions (e.g., v1.0.0-beta.1) when checking for updates'
            ),
            checked_func = function()
                return settings.auto_update_include_beta
            end,
            callback = function()
                settings.auto_update_include_beta = not settings.auto_update_include_beta

                local status_text = settings.auto_update_include_beta and _('Beta releases enabled')
                    or _('Beta releases disabled')

                Notification:success(status_text)
            end,
        },
    }
end

---Update auto-update enabled setting
---@param options {settings: MinifluxSettings, new_value: boolean, touchmenu_instance: table} Options table
---@return nil
function UpdateSettings.updateAutoUpdateSetting(options)
    options.settings.auto_update_enabled = options.new_value

    local status_text = options.new_value and _('Auto-update enabled') or _('Auto-update disabled')

    local notification = Notification:success(status_text, { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        options.touchmenu_instance:backToUpperMenu()
    end)
end

---Update update frequency setting
---@param options {settings: MinifluxSettings, new_frequency: string, touchmenu_instance: table, message: string} Options table
---@return nil
function UpdateSettings.updateFrequencySetting(options)
    options.settings.auto_update_check_frequency = options.new_frequency

    local notification = Notification:success(options.message, { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        options.touchmenu_instance:backToUpperMenu()
    end)
end

---Update beta releases setting
---@param options {settings: MinifluxSettings, new_value: boolean, touchmenu_instance: table} Options table
---@return nil
function UpdateSettings.updateBetaSetting(options)
    options.settings.auto_update_include_beta = options.new_value

    local status_text = options.new_value and _('Beta releases enabled')
        or _('Beta releases disabled')

    local notification = Notification:success(status_text, { timeout = 2 })

    -- Close notification and navigate back after a brief delay
    UIManager:scheduleIn(0.5, function()
        notification:close()
        options.touchmenu_instance:backToUpperMenu()
    end)
end

---Create auto-update settings menu items (deprecated - use individual getMenuItem functions)
---@param settings MinifluxSettings Settings instance
---@return table Menu items array
function UpdateSettings.createMenuItems(settings)
    return {
        {
            text = _('Enable Auto-Update'),
            checked_func = function()
                return settings.auto_update_enabled
            end,
            callback = function()
                settings.auto_update_enabled = not settings.auto_update_enabled

                local status_text = settings.auto_update_enabled and _('Auto-update enabled')
                    or _('Auto-update disabled')

                Notification:success(status_text)
            end,
        },
        {
            text = _('Update Frequency'),
            sub_item_table = {
                {
                    text = _('Manual only'),
                    checked_func = function()
                        return settings.auto_update_check_frequency == 'manual'
                    end,
                    callback = function()
                        settings.auto_update_check_frequency = 'manual'
                        Notification:success(_('Update frequency: Manual only'))
                    end,
                },
                {
                    text = _('Daily'),
                    checked_func = function()
                        return settings.auto_update_check_frequency == 'daily'
                    end,
                    callback = function()
                        settings.auto_update_check_frequency = 'daily'
                        Notification:success(_('Update frequency: Daily'))
                    end,
                },
                {
                    text = _('Weekly'),
                    checked_func = function()
                        return settings.auto_update_check_frequency == 'weekly'
                    end,
                    callback = function()
                        settings.auto_update_check_frequency = 'weekly'
                        Notification:success(_('Update frequency: Weekly'))
                    end,
                },
                {
                    text = _('Monthly'),
                    checked_func = function()
                        return settings.auto_update_check_frequency == 'monthly'
                    end,
                    callback = function()
                        settings.auto_update_check_frequency = 'monthly'
                        Notification:success(_('Update frequency: Monthly'))
                    end,
                },
            },
        },
        {
            text = _('Include Beta Releases'),
            checked_func = function()
                return settings.auto_update_include_beta
            end,
            callback = function()
                settings.auto_update_include_beta = not settings.auto_update_include_beta

                local status_text = settings.auto_update_include_beta and _('Beta releases enabled')
                    or _('Beta releases disabled')

                Notification:success(status_text)
            end,
        },
    }
end

---Check if it's time for an automatic update check
---@param settings MinifluxSettings Settings instance
---@return boolean True if check is due
function UpdateSettings.isUpdateCheckDue(settings)
    if not settings.auto_update_enabled then
        return false
    end

    if settings.auto_update_check_frequency == 'manual' then
        return false
    end

    local last_check = settings.auto_update_last_check
    local current_time = os.time()
    local time_diff = current_time - last_check

    local frequency_seconds = {
        daily = 24 * 60 * 60, -- 1 day
        weekly = 7 * 24 * 60 * 60, -- 7 days
        monthly = 30 * 24 * 60 * 60, -- 30 days
    }

    local required_interval = frequency_seconds[settings.auto_update_check_frequency]
    if not required_interval then
        return false
    end

    return time_diff >= required_interval
end

---Mark that an update check was performed
---@param settings MinifluxSettings Settings instance
function UpdateSettings.markUpdateCheckPerformed(settings)
    settings.auto_update_last_check = os.time()
end

return UpdateSettings
