local UIManager = require('ui/uimanager')
local Notification = require('utils/notification')
local ConfirmBox = require('ui/widget/confirmbox')
local Device = require('device')
local _ = require('gettext')
local logger = require('logger')

local ExportLogs = {}

---Get current runtime logs if available (Android only)
---@return string? logs Runtime logs or nil
local function getRuntimeLogs()
    -- On Android, we can get runtime logs from logcat
    if Device:isAndroid() then
        -- Try to get logs from Android logcat
        local handle = io.popen('logcat -d | grep -i "miniflux\\|koreader.*miniflux" 2>/dev/null')
        if handle then
            local logs = handle:read('*a')
            handle:close()
            if logs and #logs > 0 then
                return logs
            end
        end
    end
    return nil
end

---Find all available log files
---@return table Array of {path=string, type=string} log file info
local function findLogFiles()
    local DataStorage = require('datastorage')
    local lfs = require('libs/libkoreader-lfs')
    local logs = {}

    -- Possible log locations based on KOReader's behavior
    local possible_logs = {
        -- Crash logs
        { path = DataStorage:getDataDir() .. '/crash.log', type = 'crash' },
        { path = './crash.log', type = 'crash' },
        { path = DataStorage:getSettingsDir() .. '/crash.log', type = 'crash' },
        -- Some devices might have debug.log
        { path = DataStorage:getDataDir() .. '/debug.log', type = 'debug' },
        { path = './debug.log', type = 'debug' },
    }

    for _, log_info in ipairs(possible_logs) do
        if lfs.attributes(log_info.path, 'mode') then
            table.insert(logs, log_info)
            logger.info('[Miniflux] Found log file:', log_info.path, 'type:', log_info.type)
        end
    end

    return logs
end

---Export miniflux-related logs to a file
---@return boolean success
---@return string? error_message
function ExportLogs.exportLogs()
    local logs_found = findLogFiles()
    local runtime_logs = getRuntimeLogs()

    if #logs_found == 0 and not runtime_logs then
        return false,
            _([[No log files found.

To enable debug logging:
1. Go to Tools → More tools → Developer options
2. Enable "debug logging" and "verbose debug logging"
3. Restart KOReader
4. Reproduce the issue
5. Try exporting logs again

Note: crash.log is only created after a crash.]])
    end

    -- Create export file
    local EntryEntity = require('entities/entry_entity')
    local export_path = EntryEntity.getDownloadDir()
        .. '/miniflux-logs-'
        .. os.date('%Y%m%d-%H%M%S')
        .. '.log'

    local export_file = io.open(export_path, 'w')
    if not export_file then
        return false, _('Failed to create export file.')
    end

    -- Write header
    export_file:write('Miniflux Plugin Debug Log Export\n')
    export_file:write('Generated: ' .. os.date('%Y-%m-%d %H:%M:%S') .. '\n')
    export_file:write('Device: ' .. Device:info() .. '\n')
    export_file:write('Platform: ' .. Device:getPlatformName() .. '\n')
    export_file:write('=' .. string.rep('=', 60) .. '\n\n')

    local has_content = false

    -- Process runtime logs (Android)
    if runtime_logs then
        export_file:write('=== RUNTIME LOGS (Android logcat) ===\n\n')
        export_file:write(runtime_logs)
        export_file:write('\n\n')
        has_content = true
    end

    -- Process each log file
    for _, log_info in ipairs(logs_found) do
        logger.info('[Miniflux] Processing log file:', log_info.path)

        -- Read and filter log file
        local grep_cmd = string.format('grep -i "miniflux" "%s" 2>/dev/null', log_info.path)

        local handle = io.popen(grep_cmd)
        if handle then
            local filtered_content = handle:read('*a')
            handle:close()

            if filtered_content and #filtered_content > 0 then
                export_file:write(
                    string.format(
                        '=== %s LOG: %s ===\n\n',
                        string.upper(log_info.type),
                        log_info.path
                    )
                )
                export_file:write(filtered_content)
                export_file:write('\n\n')
                has_content = true
            end
        end
    end

    export_file:close()

    if not has_content then
        os.remove(export_path)
        return false, _('No Miniflux-related logs found in any log files.')
    end

    -- Add file size info
    local lfs = require('libs/libkoreader-lfs')
    local attr = lfs.attributes(export_path)
    local size_kb = attr and math.floor(attr.size / 1024) or 0

    logger.info('[Miniflux] Exported logs to:', export_path, 'size:', size_kb .. 'KB')

    return true, export_path
end

---Get menu item for exporting logs
---@return table Menu item configuration
function ExportLogs.getMenuItem()
    return {
        text = _('Export Debug Logs'),
        callback = function()
            UIManager:show(ConfirmBox:new({
                text = _([[Export Miniflux debug logs?

This will:
• Search for crash.log and debug.log files
• Extract Miniflux-related entries
• Include Android logcat on Android devices
• Save to your Miniflux folder for easy sharing]]),
                ok_text = _('Export'),
                ok_callback = function()
                    local success, result = ExportLogs.exportLogs()

                    if success then
                        UIManager:show(ConfirmBox:new({
                            text = string.format(
                                _(
                                    'Logs exported successfully!\n\nFile: %s\n\nShare this file when reporting bugs.'
                                ),
                                result and result:match('[^/]+$') or 'miniflux-logs.log' -- Show just filename
                            ),
                            ok_text = _('OK'),
                            cancel_text = _('Open Folder'),
                            cancel_callback = function()
                                -- Open the folder containing the log file
                                local FileManager = require('apps/filemanager/filemanager')
                                local EntryEntity = require('entities/entry_entity')
                                FileManager:showFiles(EntryEntity.getDownloadDir())
                            end,
                        }))
                    else
                        Notification:error(result or _('Failed to export logs'))
                    end
                end,
            }))
        end,
        help_text = _(
            'Export debug logs filtered for Miniflux entries. Includes crash logs and Android logcat where available.'
        ),
    }
end

return ExportLogs
