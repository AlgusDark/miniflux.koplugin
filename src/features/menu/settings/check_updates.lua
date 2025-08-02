local UIManager = require('ui/uimanager')
local ConfirmBox = require('ui/widget/confirmbox')
local Notification = require('shared/widgets/notification')
local Trapper = require('ui/trapper')
local _ = require('gettext')

local CheckUpdates = {}

---Show update check dialog with current and available versions
---@param update_info UpdateInfo Update information from UpdateService
---@param update_service UpdateService UpdateService instance for performing updates
function CheckUpdates.showUpdateDialog(update_info, update_service)
    local current_version = update_info.current_version
    local latest_version = update_info.latest_version
    local has_update = update_info.has_update

    local dialog_text

    if has_update then
        dialog_text = string.format(
            _(
                'Update Available!\n\nCurrent version: %s\nLatest version: %s\n\nRelease: %s\n\nWould you like to download and install the update?'
            ),
            current_version,
            latest_version,
            update_info.release_name or latest_version
        )
    else
        dialog_text = string.format(
            _("You're up to date!\n\nCurrent version: %s\nLatest version: %s"),
            current_version,
            latest_version
        )
    end

    UIManager:show(ConfirmBox:new({
        text = dialog_text,
        ok_text = has_update and _('Update Now') or _('OK'),
        cancel_text = has_update and _('Skip') or nil,
        ok_callback = has_update and function()
            CheckUpdates.performUpdate(update_info, update_service)
        end or nil,
        cancel_callback = has_update and function()
            Notification:info(
                _('Update skipped. You can check for updates again later.'),
                { timeout = 3 }
            )
        end or nil,
        other_buttons = has_update and {
            {
                text = _('Release Notes'),
                callback = function()
                    CheckUpdates.showReleaseNotes(update_info, update_service)
                end,
            },
        } or nil,
    }))
end

---Show release notes dialog
---@param update_info UpdateInfo Update information with release notes
---@param update_service UpdateService UpdateService instance for performing updates
function CheckUpdates.showReleaseNotes(update_info, update_service)
    local release_notes = update_info.release_notes or _('No release notes available')

    -- Limit release notes length for display
    if #release_notes > 500 then
        release_notes = release_notes:sub(1, 500) .. '...'
    end

    local dialog_text =
        string.format(_('Release Notes for %s\n\n%s'), update_info.latest_version, release_notes)

    UIManager:show(ConfirmBox:new({
        text = dialog_text,
        ok_text = _('Update Now'),
        cancel_text = _('Close'),
        ok_callback = function()
            CheckUpdates.performUpdate(update_info, update_service)
        end,
    }))
end

---Perform the actual update download and installation
---@param update_info UpdateInfo Update information with download URL
---@param update_service UpdateService UpdateService instance for performing updates
function CheckUpdates.performUpdate(update_info, update_service)
    if not update_info.download_url then
        Notification:warning(_('No download available for this update.'))
        return
    end

    -- Use Trapper to handle progress updates
    Trapper:wrap(function()
        update_service:downloadAndInstall(update_info)
    end)
end

---Check for updates and show result
---@param options table Options table with show_no_update, settings, update_service, and current_version
function CheckUpdates.checkForUpdates(options)
    local show_no_update = options.show_no_update
    local settings = options.settings
    local update_service = options.update_service
    local current_version = options.current_version

    if show_no_update == nil then
        show_no_update = true
    end

    local update_info, error = update_service:checkForUpdates({
        current_version = current_version,
        include_beta = settings and settings.auto_update_include_beta or false,
    })

    -- Mark check as performed if settings provided (for automatic checks)
    if settings then
        local UpdateSettings = require('features/menu/settings/update_settings')
        UpdateSettings.markUpdateCheckPerformed(settings)
    end

    if error then
        -- Only show error notification for manual checks
        if show_no_update then
            Notification:error(_('Update check failed: ') .. error)
        end
        return
    end

    if update_info and (update_info.has_update or show_no_update) then
        CheckUpdates.showUpdateDialog(update_info, update_service)
    end
end

---Get menu item for checking updates
---@param plugin table The Miniflux plugin instance
---@return table Menu item configuration
function CheckUpdates.getMenuItem(plugin)
    return {
        text = _('Check for Updates'),
        callback = function()
            local NetworkMgr = require('ui/network/manager')

            NetworkMgr:runWhenOnline(function()
                CheckUpdates.checkForUpdates({
                    show_no_update = true,
                    settings = plugin.settings,
                    update_service = plugin.update_service,
                    current_version = plugin.version,
                })
            end)
        end,
    }
end

return CheckUpdates
