local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local ConfirmBox = require('ui/widget/confirmbox')
local Notification = require('ui/widget/notification')
local ProgressWidget = require('ui/widget/progresswidget')
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
        cancel_callback = has_update
                and function()
                    UIManager:show(InfoMessage:new({
                        text = _('Update skipped. You can check for updates again later.'),
                        timeout = 3,
                    }))
                end
            or nil,
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
        UIManager:show(InfoMessage:new({
            text = _('No download available for this update.'),
            timeout = 3,
        }))
        return
    end

    -- Show progress dialog
    local progress_widget = ProgressWidget:new({
        title = _('Downloading Update'),
        text = string.format(_('Downloading %s...'), update_info.latest_version),
        percentage = 0,
        width = math.floor(UIManager.screen:getWidth() * 0.8),
        height = math.floor(UIManager.screen:getHeight() * 0.3),
    })
    UIManager:show(progress_widget)

    -- Download in background
    UIManager:nextTick(function()
        CheckUpdates.downloadAndInstall(update_info, progress_widget)
    end)
end

---Download and install the update
---@param update_info table Update information
---@param progress_widget ProgressWidget Progress dialog to update
function CheckUpdates.downloadAndInstall(update_info, progress_widget)
    local temp_dir = '/tmp/miniflux_update'
    local zip_path = temp_dir .. '/update.zip'

    -- Create temp directory
    os.execute('mkdir -p "' .. temp_dir .. '"')

    -- Track download progress
    local downloaded_bytes = 0
    local total_bytes = update_info.download_size or (1024 * 1024) -- 1MB fallback

    local progress_callback = function(chunk_size)
        downloaded_bytes = downloaded_bytes + chunk_size
        local percentage = math.min(math.floor((downloaded_bytes / total_bytes) * 100), 100)

        UIManager:nextTick(function()
            progress_widget:setPercentage(percentage)
            progress_widget:setText(
                string.format(
                    _('Downloaded %d%% (%s / %s)'),
                    percentage,
                    util.getFriendlySize(downloaded_bytes),
                    util.getFriendlySize(total_bytes)
                )
            )
        end)
    end

    -- Download the update
    local download_success, download_error = UpdateService.downloadFile({
        url = update_info.download_url,
        local_path = zip_path,
        progress_callback = progress_callback,
    })

    if not download_success then
        UIManager:close(progress_widget)
        UIManager:show(InfoMessage:new({
            text = _('Download failed: ') .. (download_error or _('Unknown error')),
            timeout = 5,
        }))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Update progress for extraction
    UIManager:nextTick(function()
        progress_widget:setPercentage(100)
        progress_widget:setText(_('Extracting update...'))
    end)

    -- Create backup before installation
    local backup_path, backup_error = UpdateService.createBackup()
    if not backup_path then
        UIManager:close(progress_widget)
        UIManager:show(InfoMessage:new({
            text = _('Backup failed: ') .. (backup_error or _('Unknown error')),
            timeout = 5,
        }))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Extract to temp directory
    local extract_success, extract_error = UpdateService.extractZip(zip_path, temp_dir)
    if not extract_success then
        UIManager:close(progress_widget)
        UIManager:show(InfoMessage:new({
            text = _('Extraction failed: ') .. (extract_error or _('Unknown error')),
            timeout = 5,
        }))
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
        UIManager:close(progress_widget)
        UIManager:show(InfoMessage:new({
            text = _('Invalid update package: plugin directory not found'),
            timeout = 5,
        }))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Install the update
    UIManager:nextTick(function()
        progress_widget:setText(_('Installing update...'))
    end)

    local plugin_path = UpdateService.getPluginPath()
    local install_cmd =
        string.format('rm -rf "%s" && mv "%s" "%s"', plugin_path, plugin_dir, plugin_path)
    local install_result = os.execute(install_cmd)

    if install_result ~= 0 then
        -- Installation failed, restore backup
        local restore_success = UpdateService.restoreBackup(backup_path)
        UIManager:close(progress_widget)

        if restore_success then
            UIManager:show(InfoMessage:new({
                text = _('Installation failed. Plugin restored to previous version.'),
                timeout = 5,
            }))
        else
            UIManager:show(InfoMessage:new({
                text = _(
                    'Installation failed and backup restoration failed! Please reinstall manually.'
                ),
                timeout = 10,
            }))
        end

        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Clean up
    os.execute('rm -rf "' .. temp_dir .. '"')
    os.execute('rm -rf "' .. backup_path .. '"')

    UIManager:close(progress_widget)

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
            UIManager:show(InfoMessage:new({
                text = _('Restarting KOReader...'),
                timeout = 2,
            }))
            UIManager:nextTick(function()
                UIManager:restartKOReader()
            end)
        end,
        cancel_callback = function()
            UIManager:show(InfoMessage:new({
                text = _('Please restart KOReader to complete the update.'),
                timeout = 5,
            }))
        end,
    }))
end

---Check for updates and show result
---@param show_no_update boolean Whether to show message when no update is available
function CheckUpdates.checkForUpdates(show_no_update)
    if show_no_update == nil then
        show_no_update = true
    end

    -- Show checking message
    local checking_notification = Notification:new({
        text = _('Checking for updates...'),
        timeout = 2,
    })
    UIManager:show(checking_notification)

    UIManager:nextTick(function()
        local update_info, error = UpdateService.checkForUpdates()

        if error then
            UIManager:show(InfoMessage:new({
                text = _('Update check failed: ') .. error,
                timeout = 5,
            }))
            return
        end

        if update_info and (update_info.has_update or show_no_update) then
            CheckUpdates.showUpdateDialog(update_info)
        end
    end)
end

---Get menu item for checking updates
---@return table Menu item configuration
function CheckUpdates.getMenuItem()
    return {
        text = _('Check for Updates'),
        callback = function()
            CheckUpdates.checkForUpdates(true)
        end,
    }
end

return CheckUpdates
