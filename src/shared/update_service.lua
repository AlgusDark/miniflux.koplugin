local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')
local lfs = require('libs/libkoreader-lfs')
local _ = require('gettext')
local logger = require('logger')
local NetworkMgr = require('ui/network/manager')
local UIManager = require('ui/uimanager')
local ConfirmBox = require('ui/widget/confirmbox')
local Notification = require('shared/widgets/notification')
local Trapper = require('ui/trapper')
local util = require('util')

-- GitHub API configuration
local GITHUB_API_BASE = 'https://api.github.com'
local USER_AGENT = 'KOReader-Plugin/1.0'

---Generic UpdateService for KOReader plugins - handles GitHub releases and plugin updates
---@class UpdateService
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name
---@field plugin_path string Full path to plugin directory
---@field logger_prefix string Logger prefix for log messages
---@field releases_url string GitHub releases API URL
local UpdateService = {}
UpdateService.__index = UpdateService

---@class UpdateInfo
---@field current_version string Current plugin version
---@field latest_version string Latest available version
---@field has_update boolean Whether an update is available
---@field release_name string Human-readable release name
---@field release_notes string Release notes/changelog
---@field published_at string Release publication date
---@field download_url string|nil Download URL for the update package
---@field download_size number|nil Size of download package in bytes

---@class UpdateServiceConfig
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name
---@field plugin_path string Full path to plugin directory
---@field logger_prefix? string Logger prefix (optional, defaults to empty)

---Create a new UpdateService instance
---@param config UpdateServiceConfig Configuration options
---@return UpdateService
function UpdateService:new(config)
    local instance = setmetatable({}, self)
    instance.repo_owner = config.repo_owner
    instance.repo_name = config.repo_name
    instance.plugin_path = config.plugin_path
    instance.logger_prefix = config.logger_prefix or ''
    instance.releases_url = GITHUB_API_BASE
        .. '/repos/'
        .. config.repo_owner
        .. '/'
        .. config.repo_name
        .. '/releases'
    return instance
end

---Parse semantic version string into comparable numbers
---@param version string Version string like "1.2.3" or "1.2.3-dev"
---@return table {major, minor, patch, is_prerelease}
function UpdateService.parseVersion(version)
    -- Remove 'v' prefix if present
    local clean_version = version:gsub('^v', '')

    -- Check for pre-release suffix (e.g., "-dev", "-beta", "-alpha")
    local is_prerelease = clean_version:match('%-') ~= nil

    -- Extract base version (remove suffix)
    local base_version = clean_version:gsub('%-.*$', '')

    local major, minor, patch = base_version:match('(%d+)%.(%d+)%.(%d+)')
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
        is_prerelease = is_prerelease,
    }
end

---Compare two versions
---@param current string Current version
---@param latest string Latest version
---@return boolean True if latest > current
function UpdateService.isNewerVersion(current, latest)
    local current_parts = UpdateService.parseVersion(current)
    local latest_parts = UpdateService.parseVersion(latest)

    -- Compare major.minor.patch first
    if latest_parts.major > current_parts.major then
        return true
    elseif latest_parts.major == current_parts.major then
        if latest_parts.minor > current_parts.minor then
            return true
        elseif latest_parts.minor == current_parts.minor then
            if latest_parts.patch > current_parts.patch then
                return true
            elseif latest_parts.patch == current_parts.patch then
                -- Same base version: stable > pre-release
                if current_parts.is_prerelease and not latest_parts.is_prerelease then
                    return true -- stable version is newer than pre-release
                end
                -- Pre-release to pre-release or stable to stable: no update
                return false
            end
        end
    end

    return false
end

---Make HTTP request to GitHub API
---@param url string API endpoint URL
---@return table|nil response, string|nil error
function UpdateService:makeGitHubRequest(url)
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'

    logger.info(log_prefix, 'Making GitHub API request to:', url)
    logger.info(log_prefix, 'Using User-Agent:', USER_AGENT)
    logger.info(log_prefix, 'Repository:', self.repo_owner .. '/' .. self.repo_name)

    if not NetworkMgr:isOnline() then
        logger.warn(log_prefix, 'Network not available')
        return nil, _('Network not available')
    end

    logger.info(log_prefix, 'Network connection confirmed')

    local response_body = {}
    local request_config = {
        url = url,
        method = 'GET',
        headers = {
            ['User-Agent'] = USER_AGENT,
            ['Accept'] = 'application/vnd.github.v3+json',
        },
        sink = ltn12.sink.table(response_body),
    }

    logger.info(log_prefix, 'Sending HTTP request...')
    local result, status_code, headers = http.request(request_config)

    logger.info(log_prefix, 'HTTP request completed')
    logger.info(log_prefix, 'Result:', tostring(result))
    logger.info(log_prefix, 'Status code:', tostring(status_code))

    if headers then
        logger.info(log_prefix, 'Response headers received')
        if headers['x-ratelimit-remaining'] then
            logger.info(
                log_prefix,
                'GitHub rate limit remaining:',
                headers['x-ratelimit-remaining']
            )
        end
    end

    if not result or status_code ~= 200 then
        logger.warn(log_prefix, 'GitHub API request failed with status:', status_code)
        if status_code == 404 then
            logger.warn(log_prefix, '404 - Repository not found or private (no access)')
        elseif status_code == 403 then
            logger.warn(log_prefix, '403 - Rate limited or authentication required')
        elseif status_code == 401 then
            logger.warn(log_prefix, '401 - Authentication required for private repository')
        end
        return nil, _('Failed to check for updates: HTTP ') .. tostring(status_code)
    end

    local response_text = table.concat(response_body)
    logger.info(log_prefix, 'Response body length:', #response_text)
    logger.info(
        log_prefix,
        'Response preview:',
        response_text:sub(1, 200) .. (response_text:len() > 200 and '...' or '')
    )

    logger.info(log_prefix, 'Parsing JSON response...')
    local success, parsed_json = pcall(json.decode, response_text)

    if not success then
        logger.warn(log_prefix, 'Failed to parse JSON response:', parsed_json)
        return nil, _('Failed to parse update information')
    end

    logger.info(log_prefix, 'JSON parsing successful')
    if parsed_json and parsed_json.tag_name then
        logger.info(log_prefix, 'Found release tag:', parsed_json.tag_name)
    end

    return parsed_json, nil
end

---Filter releases based on beta setting
---@param releases table Array of release objects from GitHub API
---@param include_beta boolean Whether to include pre-releases
---@return table Filtered releases array
function UpdateService:filterReleases(releases, include_beta)
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'

    if include_beta then
        logger.info(log_prefix, 'Including beta releases in filter')
        return releases -- Include all releases
    else
        logger.info(log_prefix, 'Excluding beta releases from filter')
        local stable_releases = {}
        for _, release in ipairs(releases) do
            if not release.prerelease then
                table.insert(stable_releases, release)
            end
        end
        logger.info(
            log_prefix,
            'Found',
            #stable_releases,
            'stable releases out of',
            #releases,
            'total'
        )
        return stable_releases
    end
end

---@class UpdateCheckConfig
---@field current_version string Current plugin version
---@field include_beta boolean Whether to include beta releases

---Check for latest release on GitHub
---@param config UpdateCheckConfig Configuration with current version and beta preference
---@return UpdateInfo|nil release_info, string|nil error
function UpdateService:checkForUpdates(config)
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'
    local current_version = config.current_version
    local include_beta = config.include_beta

    logger.info(log_prefix, 'Starting update check process')
    logger.info(log_prefix, 'Target repository:', self.repo_owner .. '/' .. self.repo_name)
    logger.info(log_prefix, 'Current version:', current_version)
    logger.info(log_prefix, 'Include beta releases:', include_beta)

    local releases_data, error = self:makeGitHubRequest(self.releases_url)
    if error then
        logger.warn(log_prefix, 'GitHub API request failed:', error)
        return nil, error
    end

    if not releases_data or type(releases_data) ~= 'table' or #releases_data == 0 then
        logger.warn(log_prefix, 'Invalid releases data from GitHub')
        logger.warn(log_prefix, 'releases_data is nil:', releases_data == nil)
        if releases_data then
            logger.warn(log_prefix, 'releases_data type:', type(releases_data))
            logger.warn(log_prefix, 'releases_data length:', #releases_data)
        end
        return nil, _('No releases found on GitHub')
    end

    logger.info(log_prefix, 'Found', #releases_data, 'total releases')

    -- Filter releases based on beta setting
    local filtered_releases = self:filterReleases(releases_data, include_beta)

    if #filtered_releases == 0 then
        logger.warn(log_prefix, 'No suitable releases found after filtering')
        return nil, _('No suitable releases found')
    end

    -- Helper function to match current version (handles 'v' prefix variations)
    local function matchesCurrentVersion(tag_name)
        return tag_name:gsub('^v', '') == current_version:gsub('^v', '')
    end

    -- Single pass: find latest release by timestamp AND current release
    local latest_release = nil
    local current_release = nil
    local current_position = nil

    for i, release in ipairs(filtered_releases) do
        -- Track current version position and release info
        if matchesCurrentVersion(release.tag_name) then
            current_release = release
            current_position = i
        end

        -- Find truly latest release by published_at timestamp
        if not latest_release then
            latest_release = release
        else
            local should_update = false
            if release.published_at and latest_release.published_at then
                -- Both have timestamps - compare them
                should_update = release.published_at > latest_release.published_at
            elseif release.published_at and not latest_release.published_at then
                -- Prefer releases with timestamps over those without
                should_update = true
            end
            -- else: current latest has timestamp but this release doesn't - keep current

            if should_update then
                latest_release = release
            end
        end
    end

    if not latest_release then
        logger.warn(log_prefix, 'No valid latest release found after filtering')
        return nil, _('No valid releases found')
    end

    local latest_version = latest_release.tag_name
    local has_update = false

    if current_release then
        -- Current version found - use timestamp comparison if available
        local current_published_at = current_release.published_at
        local latest_published_at = latest_release.published_at

        if current_published_at and latest_published_at then
            -- Primary method: timestamp comparison (ISO 8601 strings compare lexicographically)
            has_update = latest_published_at > current_published_at
            logger.info(
                log_prefix,
                'Timestamp comparison: current',
                current_published_at,
                'vs latest',
                latest_published_at,
                '→',
                has_update
            )
        else
            -- Fallback: positional comparison (GitHub's API ordering)
            has_update = current_position > 1
            logger.info(
                log_prefix,
                'Position fallback: current at',
                current_position,
                '→',
                has_update
            )
        end
    else
        -- Current version not in releases - semantic version comparison
        has_update = UpdateService.isNewerVersion(current_version, latest_version)
        logger.info(
            log_prefix,
            'Semantic fallback:',
            current_version,
            'vs',
            latest_version,
            '→',
            has_update
        )
    end
    logger.info(
        log_prefix,
        'Version check:',
        current_version,
        '->',
        latest_version,
        '(update available:',
        has_update,
        ')'
    )

    local update_info = {
        current_version = current_version,
        latest_version = latest_version,
        has_update = has_update,
        release_name = latest_release.name or latest_version,
        release_notes = latest_release.body or _('No release notes available'),
        published_at = latest_release.published_at,
        download_url = nil,
        download_size = nil,
    }

    logger.info(log_prefix, 'Release info:')
    logger.info(log_prefix, '  Release name:', update_info.release_name)
    logger.info(log_prefix, '  Published at:', update_info.published_at)

    -- Find the plugin ZIP file in assets
    logger.info(log_prefix, 'Looking for download assets...')
    if latest_release.assets then
        logger.info(log_prefix, 'Found', #latest_release.assets, 'assets')
        for i, asset in ipairs(latest_release.assets) do
            logger.info(log_prefix, 'Asset', i .. ':', asset.name or 'unnamed')
            if asset.name and asset.name:match('%.koplugin%.zip$') then
                logger.info(log_prefix, 'Found plugin ZIP:', asset.name)
                update_info.download_url = asset.browser_download_url
                update_info.download_size = asset.size
                logger.info(log_prefix, 'Download URL:', asset.browser_download_url)
                logger.info(log_prefix, 'Download size:', asset.size)
                break
            end
        end
    else
        logger.warn(log_prefix, 'No assets found in release data')
    end

    if not update_info.download_url then
        logger.warn(log_prefix, 'No .koplugin.zip file found in release assets')
    end

    if update_info.has_update and not update_info.download_url then
        logger.warn(log_prefix, 'Update available but no download URL found')
        return nil, _('Update available but download not found')
    end

    return update_info, nil
end

---@class DownloadOptions
---@field url string Download URL
---@field local_path string Local file path
---@field progress_callback? function Optional progress callback

---Download file from URL to local path
---@param opts DownloadOptions Download configuration
---@return boolean success, string|nil error
function UpdateService:downloadFile(opts)
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'
    local url = opts.url
    local local_path = opts.local_path
    local progress_callback = opts.progress_callback

    logger.info(log_prefix, 'Downloading', url, 'to', local_path)

    local file = io.open(local_path, 'wb')
    if not file then
        return false, _('Cannot create download file')
    end

    local request_config = {
        url = url,
        method = 'GET',
        headers = {
            ['User-Agent'] = USER_AGENT,
        },
        sink = function(chunk)
            if chunk then
                file:write(chunk)
                if progress_callback then
                    progress_callback(#chunk)
                end
            end
            return true
        end,
    }

    local result, status_code = http.request(request_config)
    file:close()

    if not result or status_code ~= 200 then
        os.remove(local_path) -- Clean up failed download
        return false, _('Download failed: HTTP ') .. tostring(status_code)
    end

    -- Verify file was created and has content
    local file_attrs = lfs.attributes(local_path)
    if not file_attrs or file_attrs.size == 0 then
        os.remove(local_path)
        return false, _('Downloaded file is empty')
    end

    logger.info(log_prefix, 'Download complete', file_attrs.size, 'bytes')
    return true, nil
end

---Extract ZIP file to destination directory
---@param zip_path string Path to ZIP file
---@param dest_dir string Destination directory
---@return boolean success, string|nil error
function UpdateService:extractZip(zip_path, dest_dir)
    -- Create destination directory if it doesn't exist
    local success = lfs.mkdir(dest_dir)
    if not success and lfs.attributes(dest_dir, 'mode') ~= 'directory' then
        return false, _('Cannot create extraction directory')
    end

    -- Use system unzip command (available on most KOReader devices)
    local unzip_cmd = string.format('unzip -o "%s" -d "%s"', zip_path, dest_dir)
    local result = os.execute(unzip_cmd)

    if result ~= 0 then
        return false, _('Failed to extract update file')
    end

    return true, nil
end

---Create backup of current plugin
---@return string|nil backup_path, string|nil error
function UpdateService:createBackup()
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'
    local plugin_path = self.plugin_path

    -- Use KOReader's cache directory for backups with timestamp
    local DataStorage = require('datastorage')
    local cache_dir = DataStorage:getDataDir() .. '/cache'
    local backup_path = cache_dir .. '/plugin_backup'

    -- Create cache directory if it doesn't exist
    lfs.mkdir(cache_dir)

    -- Clean up old backups (keep system clean)
    self:cleanupOldBackups()

    -- Create new backup
    local cp_cmd = string.format('cp -r "%s" "%s"', plugin_path, backup_path)
    local result = os.execute(cp_cmd)

    if result ~= 0 then
        logger.warn(log_prefix, 'Failed to create backup')
        return nil, _('Failed to create backup')
    end

    logger.info(log_prefix, 'Backup created at:', backup_path)
    return backup_path, nil
end

---Clean up old backup files to prevent cache bloat
function UpdateService:cleanupOldBackups()
    local DataStorage = require('datastorage')
    local cache_dir = DataStorage:getDataDir() .. '/cache'

    -- Remove existing backup (only keep one at a time)
    local backup_path = cache_dir .. '/plugin_backup'
    os.execute('rm -rf "' .. backup_path .. '"')

    -- Clean up any old timestamped backups (from previous versions)
    os.execute('rm -rf "' .. cache_dir .. '/plugin_backup_*"')
end

---Restore from backup
---@param backup_path string Path to backup directory
---@return boolean success, string|nil error
function UpdateService:restoreBackup(backup_path)
    local log_prefix = '[' .. self.logger_prefix .. 'UpdateService]'
    local plugin_path = self.plugin_path

    -- Remove current plugin
    os.execute('rm -rf "' .. plugin_path .. '"')

    -- Restore backup
    local mv_cmd = string.format('mv "%s" "%s"', backup_path, plugin_path)
    local result = os.execute(mv_cmd)

    if result ~= 0 then
        logger.warn(log_prefix, 'Failed to restore backup')
        return false, _('Failed to restore backup')
    end

    logger.info(log_prefix, 'Backup restored from:', backup_path)
    return true, nil
end

---Clean up backup after successful update
---@param backup_path string Path to backup directory to remove
function UpdateService:cleanupBackup(backup_path)
    if backup_path and backup_path ~= '' then
        os.execute('rm -rf "' .. backup_path .. '"')
    end
end

---Download and install the update with progress tracking
---@param update_info UpdateInfo Update information with download details
function UpdateService:downloadAndInstall(update_info)
    -- Extract plugin name from plugin path (e.g., '/path/to/plugin.koplugin' -> 'plugin')
    local plugin_name = self.plugin_path:match('([^/]+)%.koplugin$')
    local temp_dir = '/tmp/' .. plugin_name .. '_update'
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
    local download_success, download_error = self:downloadFile({
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
    local backup_path, backup_error = self:createBackup()
    if not backup_path then
        Trapper:clear()
        Notification:error(_('Backup failed: ') .. (backup_error or _('Unknown error')))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Extract to temp directory
    local extract_success, extract_error = self:extractZip(zip_path, temp_dir)
    if not extract_success then
        Trapper:clear()
        Notification:error(_('Extraction failed: ') .. (extract_error or _('Unknown error')))
        os.execute('rm -rf "' .. temp_dir .. '"')
        return
    end

    -- Find extracted plugin directory
    local plugin_dir = temp_dir .. '/' .. plugin_name .. '.koplugin'
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

    local plugin_path = self.plugin_path
    local install_cmd =
        string.format('rm -rf "%s" && mv "%s" "%s"', plugin_path, plugin_dir, plugin_path)
    local install_result = os.execute(install_cmd)

    if install_result ~= 0 then
        -- Installation failed, restore backup
        local restore_success = self:restoreBackup(backup_path)
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
    self:cleanupBackup(backup_path)

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

return UpdateService
