local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')
local lfs = require('libs/libkoreader-lfs')
local _ = require('gettext')
local logger = require('logger')

local UpdateService = {}

-- GitHub repository information
local GITHUB_API_BASE = 'https://api.github.com'
local REPO_OWNER = 'AlgusDark' -- Update this to match your GitHub username
local REPO_NAME = 'miniflux.koplugin'
local RELEASES_URL = GITHUB_API_BASE
    .. '/repos/'
    .. REPO_OWNER
    .. '/'
    .. REPO_NAME
    .. '/releases/latest'

-- User agent for GitHub API (required)
local USER_AGENT = 'KOReader-Miniflux-Plugin/1.0'

---Check if network is available
---@return boolean
function UpdateService.isNetworkAvailable()
    local success, _ = pcall(function()
        local response = http.request('http://httpbin.org/get')
        return response ~= nil
    end)
    return success
end

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
---@param version string Version string like "1.2.3"
---@return table {major, minor, patch}
function UpdateService.parseVersion(version)
    -- Remove 'v' prefix if present
    local clean_version = version:gsub('^v', '')

    local major, minor, patch = clean_version:match('(%d+)%.(%d+)%.(%d+)')
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
    }
end

---Compare two versions
---@param current string Current version
---@param latest string Latest version
---@return boolean True if latest > current
function UpdateService.isNewerVersion(current, latest)
    local current_parts = UpdateService.parseVersion(current)
    local latest_parts = UpdateService.parseVersion(latest)

    if latest_parts.major > current_parts.major then
        return true
    elseif latest_parts.major == current_parts.major then
        if latest_parts.minor > current_parts.minor then
            return true
        elseif latest_parts.minor == current_parts.minor then
            return latest_parts.patch > current_parts.patch
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

    if not UpdateService.isNetworkAvailable() then
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

---Check for latest release on GitHub
---@return table|nil release_info, string|nil error
function UpdateService.checkForUpdates()
    logger.info('[Miniflux:UpdateService] Starting update check process')
    logger.info('[Miniflux:UpdateService] Target repository:', REPO_OWNER .. '/' .. REPO_NAME)

    local release_data, error = UpdateService.makeGitHubRequest(RELEASES_URL)
    if error then
        logger.warn('[Miniflux:UpdateService] GitHub API request failed:', error)
        return nil, error
    end

    if not release_data or not release_data.tag_name then
        logger.warn('[Miniflux:UpdateService] Invalid release data from GitHub')
        logger.warn('[Miniflux:UpdateService] release_data is nil:', release_data == nil)
        if release_data then
            logger.warn('[Miniflux:UpdateService] Missing tag_name field in release data')
        end
        return nil, _('Invalid release information from GitHub')
    end

    logger.info('[Miniflux:UpdateService] Getting current version...')
    local current_version = UpdateService.getCurrentVersion()
    local latest_version = release_data.tag_name

    logger.info('[Miniflux:UpdateService] Version comparison:')
    logger.info('[Miniflux:UpdateService]   Current version:', current_version)
    logger.info('[Miniflux:UpdateService]   Latest version:', latest_version)

    local has_update = UpdateService.isNewerVersion(current_version, latest_version)
    logger.info('[Miniflux:UpdateService] Update available:', has_update)

    local update_info = {
        current_version = current_version,
        latest_version = latest_version,
        has_update = has_update,
        release_name = release_data.name or latest_version,
        release_notes = release_data.body or _('No release notes available'),
        published_at = release_data.published_at,
        download_url = nil,
        download_size = nil,
    }

    logger.info('[Miniflux:UpdateService] Release info:')
    logger.info('[Miniflux:UpdateService]   Release name:', update_info.release_name)
    logger.info('[Miniflux:UpdateService]   Published at:', update_info.published_at)

    -- Find the plugin ZIP file in assets
    logger.info('[Miniflux:UpdateService] Looking for download assets...')
    if release_data.assets then
        logger.info('[Miniflux:UpdateService] Found', #release_data.assets, 'assets')
        for i, asset in ipairs(release_data.assets) do
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
    local backup_path = plugin_path .. '.backup'

    -- Remove existing backup
    os.execute('rm -rf "' .. backup_path .. '"')

    -- Create new backup
    local cp_cmd = string.format('cp -r "%s" "%s"', plugin_path, backup_path)
    local result = os.execute(cp_cmd)

    if result ~= 0 then
        return nil, _('Failed to create backup')
    end

    return backup_path, nil
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

return UpdateService
