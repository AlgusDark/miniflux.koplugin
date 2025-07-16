local UIManager = require('ui/uimanager')
local ConfirmBox = require('ui/widget/confirmbox')
local Notification = require('utils/notification')
local InfoMessage = require('ui/widget/infomessage')
local Trapper = require('ui/trapper')
local util = require('util')
local lfs = require('libs/libkoreader-lfs')
local _ = require('gettext')

local UpdateService = require('services/update_service')

local CheckUpdates = {}

---Show update check dialog with current and available versions
---@param update_info table Update information from UpdateService
function CheckUpdates.showUpdateDialog(update_info)
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
            CheckUpdates.performUpdate(update_info)
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
                    CheckUpdates.showReleaseNotes(update_info)
                end,
            },
        } or nil,
    }))
end

---Show release notes dialog
---@param update_info table Update information with release notes
function CheckUpdates.showReleaseNotes(update_info)
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
            CheckUpdates.performUpdate(update_info)
        end,
    }))
end

---Perform the actual update download and installation
---@param update_info table Update information with download URL
function CheckUpdates.performUpdate(update_info)
    if not update_info.download_url then
        Notification:warning(_('No download available for this update.'))
        return
    end

    -- Use Trapper to handle progress updates
    Trapper:wrap(function()
        CheckUpdates.downloadAndInstall(update_info)
    end)
end

---Download and install the update
---@param update_info table Update information
function CheckUpdates.downloadAndInstall(update_info)
    local temp_dir = '/tmp/miniflux_update'
    local zip_path = temp_dir .. '/update.zip'

    -- Create temp directory
    os.execute('mkdir -p "' .. temp_dir .. '"')

    -- Show initial progress
    local initial_message = string.format(_('Downloading %s...'), update_info.latest_version)
    if not Trapper:info(initial_message) then
        -- User dismissed, cancel update
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Track download progress
    local downloaded_bytes = 0
    local total_bytes = update_info.download_size or (1024 * 1024) -- 1MB fallback

    local progress_callback = function(chunk_size)
        downloaded_bytes = downloaded_bytes + chunk_size
        local percentage = math.min(math.floor((downloaded_bytes / total_bytes) * 100), 100)

        local progress_message = string.format(
            _('Downloaded %d%% (%s / %s)'),
            percentage,
            util.getFriendlySize(downloaded_bytes),
            util.getFriendlySize(total_bytes)
        )

        -- Update progress, skip dismiss check for frequent updates
        Trapper:info(progress_message, true, true)
    end

    -- Download the update
    local download_success, download_error = UpdateService.downloadFile({
        url = update_info.download_url,
        local_path = zip_path,
        progress_callback = progress_callback,
    })

    if not download_success then
        Trapper:clear()
        Notification:error(_('Download failed: ') .. (download_error or _('Unknown error')))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Update progress for extraction
    if not Trapper:info(_('Extracting update...')) then
        -- User dismissed, cancel update
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Create backup before installation
    local backup_path, backup_error = UpdateService.createBackup()
    if not backup_path then
        Trapper:clear()
        Notification:error(_('Backup failed: ') .. (backup_error or _('Unknown error')))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Extract to temp directory
    local extract_success, extract_error = UpdateService.extractZip(zip_path, temp_dir)
    if not extract_success then
        Trapper:clear()
        Notification:error(_('Extraction failed: ') .. (extract_error or _('Unknown error')))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Find extracted plugin directory
    local plugin_dir = temp_dir .. '/miniflux.koplugin'
    if not lfs.attributes(plugin_dir, 'mode') then
        -- Look for any .koplugin directory
        for file in lfs.dir(temp_dir) do
            if file:match('%.koplugin$') then
                plugin_dir = temp_dir .. '/' .. file
                break
            end
        end
    end

    if not lfs.attributes(plugin_dir, 'mode') then
        Trapper:clear()
        Notification:error(_('Invalid update package: plugin directory not found'))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Install the update
    if not Trapper:info(_('Installing update...')) then
        -- User dismissed, cancel update
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    local plugin_path = UpdateService.getPluginPath()
    local install_cmd =
        string.format('rm -rf "%s" && mv "%s" "%s"', plugin_path, plugin_dir, plugin_path)
    local install_result = os.execute(install_cmd)

    if install_result ~= 0 then
        -- Installation failed, restore backup
        local restore_success = UpdateService.restoreBackup(backup_path)
        Trapper:clear()

        if restore_success then
            Notification:error(_('Installation failed. Plugin restored to previous version.'))
        else
            Notification:error(
                _('Installation failed and backup restoration failed! Please reinstall manually.'),
                { timeout = 10 }
            )
        end

        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Clean up
    os.execute('rm -rf "' .. temp_dir .. '"')
    UpdateService.cleanupBackup(backup_path)

    Trapper:clear()

    -- Show success message and prompt for restart
    UIManager:show(ConfirmBox:new({
        text = string.format(
            _(
                'Update installed successfully!\n\nUpdated to version %s.\n\nKOReader needs to be restarted for the changes to take effect.'
            ),
            update_info.latest_version
        ),
        ok_text = _('Restart Now'),
        cancel_text = _('Restart Later'),
        ok_callback = function()
            Notification:info(_('Restarting KOReader...'), { timeout = 2 })
            UIManager:nextTick(function()
                UIManager:restartKOReader()
            end)
        end,
        cancel_callback = function()
            Notification:info(_('Please restart KOReader to complete the update.'), { timeout = 5 })
        end,
    }))
end

---Check for updates and show result
---@param options table Options table with show_no_update, settings, and plugin_instance
function CheckUpdates.checkForUpdates(options)
    local show_no_update = options.show_no_update
    local settings = options.settings
    local plugin_instance = options.plugin_instance

    if show_no_update == nil then
        show_no_update = true
    end

    -- Show checking message only for manual checks
    local checking_notification
    if show_no_update then
        checking_notification = Notification:info(_('Checking for updates...'), { timeout = 2 })
    end

    local update_info, error = UpdateService.checkForUpdates(plugin_instance)

    -- Mark check as performed if settings provided (for automatic checks)
    if settings then
        local UpdateSettings = require('menu/settings/update_settings')
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
        CheckUpdates.showUpdateDialog(update_info)
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

            -- Check network status first
            if not NetworkMgr:isOnline() then
                -- Show Wi-Fi prompt instead of attempting update check
                NetworkMgr:runWhenOnline(function()
                    CheckUpdates.checkForUpdates({
                        show_no_update = true,
                        plugin_instance = plugin,
                    })
                end)
            else
                -- Network is available, proceed with update check
                CheckUpdates.checkForUpdates({
                    show_no_update = true,
                    plugin_instance = plugin,
                })
            end
        end,
    }
end

return CheckUpdates
