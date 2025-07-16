local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')
local lfs = require('libs/libkoreader-lfs')
local _ = require('gettext')
local logger = require('logger')
local NetworkMgr = require('ui/network/manager')

local UpdateService = {}

-- GitHub repository information
local GITHUB_API_BASE = 'https://api.github.com'
local REPO_OWNER = 'AlgusDark' -- Update this to match your GitHub username
local REPO_NAME = 'miniflux.koplugin'
local RELEASES_URL = GITHUB_API_BASE .. '/repos/' .. REPO_OWNER .. '/' .. REPO_NAME .. '/releases'

-- User agent for GitHub API (required)
local USER_AGENT = 'KOReader-Miniflux-Plugin/1.0'

---Get current plugin version from _meta.lua
---@return string Current version
function UpdateService.getCurrentVersion()
    logger.info('[Miniflux:UpdateService] Attempting to get current version from _meta.lua')

    local meta = nil
    local success, err = pcall(function()
        meta = require('_meta')
    end)

    if not success then
        logger.warn('[Miniflux:UpdateService] Failed to require _meta.lua:', err)
        logger.info('[Miniflux:UpdateService] Using fallback version: 0.0.1')
        return '0.0.1'
    end

    if not meta then
        logger.warn('[Miniflux:UpdateService] _meta.lua returned nil')
        logger.info('[Miniflux:UpdateService] Using fallback version: 0.0.1')
        return '0.0.1'
    end

    local version = meta.version
    if not version then
        logger.warn('[Miniflux:UpdateService] _meta.lua has no version field')
        logger.info('[Miniflux:UpdateService] Using fallback version: 0.0.1')
        return '0.0.1'
    end

    logger.info('[Miniflux:UpdateService] Found version in _meta.lua:', version)
    return version
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
function UpdateService.makeGitHubRequest(url)
    logger.info('[Miniflux:UpdateService] Making GitHub API request to:', url)
    logger.info('[Miniflux:UpdateService] Using User-Agent:', USER_AGENT)
    logger.info('[Miniflux:UpdateService] Repository:', REPO_OWNER .. '/' .. REPO_NAME)

    if not NetworkMgr:isOnline() then
        logger.warn('[Miniflux:UpdateService] Network not available')
        return nil, _('Network not available')
    end

    logger.info('[Miniflux:UpdateService] Network connection confirmed')

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

    logger.info('[Miniflux:UpdateService] Sending HTTP request...')
    local result, status_code, headers = http.request(request_config)

    logger.info('[Miniflux:UpdateService] HTTP request completed')
    logger.info('[Miniflux:UpdateService] Result:', tostring(result))
    logger.info('[Miniflux:UpdateService] Status code:', tostring(status_code))

    if headers then
        logger.info('[Miniflux:UpdateService] Response headers received')
        if headers['x-ratelimit-remaining'] then
            logger.info(
                '[Miniflux:UpdateService] GitHub rate limit remaining:',
                headers['x-ratelimit-remaining']
            )
        end
    end

    if not result or status_code ~= 200 then
        logger.warn('[Miniflux:UpdateService] GitHub API request failed with status:', status_code)
        if status_code == 404 then
            logger.warn(
                '[Miniflux:UpdateService] 404 - Repository not found or private (no access)'
            )
        elseif status_code == 403 then
            logger.warn('[Miniflux:UpdateService] 403 - Rate limited or authentication required')
        elseif status_code == 401 then
            logger.warn(
                '[Miniflux:UpdateService] 401 - Authentication required for private repository'
            )
        end
        return nil, _('Failed to check for updates: HTTP ') .. tostring(status_code)
    end

    local response_text = table.concat(response_body)
    logger.info('[Miniflux:UpdateService] Response body length:', #response_text)
    logger.info(
        '[Miniflux:UpdateService] Response preview:',
        response_text:sub(1, 200) .. (response_text:len() > 200 and '...' or '')
    )

    logger.info('[Miniflux:UpdateService] Parsing JSON response...')
    local success, parsed_json = pcall(json.decode, response_text)

    if not success then
        logger.warn('[Miniflux:UpdateService] Failed to parse JSON response:', parsed_json)
        return nil, _('Failed to parse update information')
    end

    logger.info('[Miniflux:UpdateService] JSON parsing successful')
    if parsed_json and parsed_json.tag_name then
        logger.info('[Miniflux:UpdateService] Found release tag:', parsed_json.tag_name)
    end

    return parsed_json, nil
end

---Filter releases based on beta setting
---@param releases table Array of release objects from GitHub API
---@param include_beta boolean Whether to include pre-releases
---@return table Filtered releases array
function UpdateService.filterReleases(releases, include_beta)
    if include_beta then
        logger.info('[Miniflux:UpdateService] Including beta releases in filter')
        return releases -- Include all releases
    else
        logger.info('[Miniflux:UpdateService] Excluding beta releases from filter')
        local stable_releases = {}
        for _, release in ipairs(releases) do
            if not release.prerelease then
                table.insert(stable_releases, release)
            end
        end
        logger.info(
            '[Miniflux:UpdateService] Found',
            #stable_releases,
            'stable releases out of',
            #releases,
            'total'
        )
        return stable_releases
    end
end

---Check for latest release on GitHub
---@return table|nil release_info, string|nil error
function UpdateService.checkForUpdates()
    logger.info('[Miniflux:UpdateService] Starting update check process')
    logger.info('[Miniflux:UpdateService] Target repository:', REPO_OWNER .. '/' .. REPO_NAME)

    local releases_data, error = UpdateService.makeGitHubRequest(RELEASES_URL)
    if error then
        logger.warn('[Miniflux:UpdateService] GitHub API request failed:', error)
        return nil, error
    end

    if not releases_data or type(releases_data) ~= 'table' or #releases_data == 0 then
        logger.warn('[Miniflux:UpdateService] Invalid releases data from GitHub')
        logger.warn('[Miniflux:UpdateService] releases_data is nil:', releases_data == nil)
        if releases_data then
            logger.warn('[Miniflux:UpdateService] releases_data type:', type(releases_data))
            logger.warn('[Miniflux:UpdateService] releases_data length:', #releases_data)
        end
        return nil, _('No releases found on GitHub')
    end

    logger.info('[Miniflux:UpdateService] Found', #releases_data, 'total releases')

    -- Get beta setting from settings
    local Settings = require('settings/settings')
    local settings = Settings:new()
    local include_beta = settings.auto_update_include_beta
    logger.info('[Miniflux:UpdateService] Include beta releases:', include_beta)

    -- Filter releases based on beta setting
    local filtered_releases = UpdateService.filterReleases(releases_data, include_beta)

    if #filtered_releases == 0 then
        logger.warn('[Miniflux:UpdateService] No suitable releases found after filtering')
        return nil, _('No suitable releases found')
    end

    -- Get the latest release (first in filtered list, GitHub returns newest first)
    local latest_release = filtered_releases[1]

    logger.info('[Miniflux:UpdateService] Getting current version...')
    local current_version = UpdateService.getCurrentVersion()
    local latest_version = latest_release.tag_name

    logger.info('[Miniflux:UpdateService] Version comparison:')
    logger.info('[Miniflux:UpdateService]   Current version:', current_version)
    logger.info('[Miniflux:UpdateService]   Latest version:', latest_version)
    logger.info('[Miniflux:UpdateService]   Latest is prerelease:', latest_release.prerelease)

    local has_update = UpdateService.isNewerVersion(current_version, latest_version)
    logger.info('[Miniflux:UpdateService] Update available:', has_update)

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

    logger.info('[Miniflux:UpdateService] Release info:')
    logger.info('[Miniflux:UpdateService]   Release name:', update_info.release_name)
    logger.info('[Miniflux:UpdateService]   Published at:', update_info.published_at)

    -- Find the plugin ZIP file in assets
    logger.info('[Miniflux:UpdateService] Looking for download assets...')
    if latest_release.assets then
        logger.info('[Miniflux:UpdateService] Found', #latest_release.assets, 'assets')
        for i, asset in ipairs(latest_release.assets) do
            logger.info('[Miniflux:UpdateService] Asset', i .. ':', asset.name or 'unnamed')
            if asset.name and asset.name:match('%.koplugin%.zip$') then
                logger.info('[Miniflux:UpdateService] Found plugin ZIP:', asset.name)
                update_info.download_url = asset.browser_download_url
                update_info.download_size = asset.size
                logger.info('[Miniflux:UpdateService] Download URL:', asset.browser_download_url)
                logger.info('[Miniflux:UpdateService] Download size:', asset.size)
                break
            end
        end
    else
        logger.warn('[Miniflux:UpdateService] No assets found in release data')
    end

    if not update_info.download_url then
        logger.warn('[Miniflux:UpdateService] No .koplugin.zip file found in release assets')
    end

    if update_info.has_update and not update_info.download_url then
        logger.warn('[Miniflux:UpdateService] Update available but no download URL found')
        return nil, _('Update available but download not found')
    end

    logger.info('[Miniflux:UpdateService] Update check completed successfully')
    logger.info('[Miniflux:UpdateService] Summary:')
    logger.info('[Miniflux:UpdateService]   Current version:', current_version)
    logger.info('[Miniflux:UpdateService]   Latest version:', latest_version)
    logger.info('[Miniflux:UpdateService]   Update available:', tostring(update_info.has_update))
    logger.info(
        '[Miniflux:UpdateService]   Download available:',
        tostring(update_info.download_url ~= nil)
    )

    return update_info, nil
end

---@class DownloadOptions
---@field url string Download URL
---@field local_path string Local file path
---@field progress_callback? function Optional progress callback

---Download file from URL to local path
---@param opts DownloadOptions Download configuration
---@return boolean success, string|nil error
function UpdateService.downloadFile(opts)
    local url = opts.url
    local local_path = opts.local_path
    local progress_callback = opts.progress_callback

    logger.info('[Miniflux:UpdateService] Downloading', url, 'to', local_path)

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

    logger.info('[Miniflux:UpdateService] Download complete', file_attrs.size, 'bytes')
    return true, nil
end

---Extract ZIP file to destination directory
---@param zip_path string Path to ZIP file
---@param dest_dir string Destination directory
---@return boolean success, string|nil error
function UpdateService.extractZip(zip_path, dest_dir)
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

---Get plugin directory path
---@return string Plugin directory path
function UpdateService.getPluginPath()
    -- KOReader plugins are typically in koreader/plugins/pluginname.koplugin
    local plugin_path = debug.getinfo(1, 'S').source:match('@(.*/)')
    if plugin_path then
        -- Remove /src/ from the path to get plugin root
        plugin_path = plugin_path:gsub('/src/$', '')
        return plugin_path
    end

    -- Fallback: try to determine from current working directory
    local cwd = lfs.currentdir()
    if cwd and cwd:match('miniflux%.koplugin') then
        return cwd
    end

    -- Last resort fallback
    return '/tmp/miniflux.koplugin'
end

---Create backup of current plugin
---@return string|nil backup_path, string|nil error
function UpdateService.createBackup()
    local plugin_path = UpdateService.getPluginPath()

    -- Use KOReader's cache directory for backups with timestamp
    local DataStorage = require('datastorage')
    local cache_dir = DataStorage:getDataDir() .. '/cache'
    local backup_path = cache_dir .. '/miniflux_plugin_backup'

    -- Create cache directory if it doesn't exist
    lfs.mkdir(cache_dir)

    -- Clean up old backups (keep system clean)
    UpdateService.cleanupOldBackups()

    -- Create new backup
    local cp_cmd = string.format('cp -r "%s" "%s"', plugin_path, backup_path)
    local result = os.execute(cp_cmd)

    if result ~= 0 then
        return nil, _('Failed to create backup')
    end

    return backup_path, nil
end

---Clean up old backup files to prevent cache bloat
function UpdateService.cleanupOldBackups()
    local DataStorage = require('datastorage')
    local cache_dir = DataStorage:getDataDir() .. '/cache'

    -- Remove existing backup (only keep one at a time)
    local backup_path = cache_dir .. '/miniflux_plugin_backup'
    os.execute('rm -rf "' .. backup_path .. '"')

    -- Clean up any old timestamped backups (from previous versions)
    os.execute('rm -rf "' .. cache_dir .. '/miniflux_plugin_backup_*"')
end

---Restore from backup
---@param backup_path string Path to backup directory
---@return boolean success, string|nil error
function UpdateService.restoreBackup(backup_path)
    local plugin_path = UpdateService.getPluginPath()

    -- Remove current plugin
    os.execute('rm -rf "' .. plugin_path .. '"')

    -- Restore backup
    local mv_cmd = string.format('mv "%s" "%s"', backup_path, plugin_path)
    local result = os.execute(mv_cmd)

    if result ~= 0 then
        return false, _('Failed to restore backup')
    end

    return true, nil
end

---Clean up backup after successful update
---@param backup_path string Path to backup directory to remove
function UpdateService.cleanupBackup(backup_path)
    if backup_path and backup_path ~= '' then
        os.execute('rm -rf "' .. backup_path .. '"')
    end
end

return UpdateService
