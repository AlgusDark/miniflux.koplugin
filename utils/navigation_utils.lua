--[[--
Navigation Utilities for Miniflux Entries

This utility module handles entry navigation logic including timestamp-based
previous/next navigation, API coordination, and context-aware filtering.
Pure functions with no state - memory efficient for low-powered devices.

@module miniflux.utils.navigation_utils
--]]

local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Notification = require("utils/notification")
local _ = require("gettext")

-- Import dependencies
local NavigationContext = require("utils/navigation_context")
local MetadataLoader = require("utils/metadata_loader")
local TimeUtils = require("utils/time_utils")

-- Constants
local DIRECTION_PREVIOUS = "previous"
local DIRECTION_NEXT = "next"
local DIRECTION_ASC = "asc"
local DIRECTION_DESC = "desc"
local PUBLISHED_AFTER = "published_after"
local PUBLISHED_BEFORE = "published_before"
local MSG_FINDING_PREVIOUS = "Finding previous entry..."
local MSG_FINDING_NEXT = "Finding next entry..."

local NavigationUtils = {}

-- =============================================================================
-- MAIN NAVIGATION FUNCTION
-- =============================================================================

---Navigate to an entry in specified direction
---@param entry_info table Current entry information with file_path and entry_id
---@param config table Configuration with navigation_options, settings, api, entry_service
---@return nil
function NavigationUtils.navigateToEntry(entry_info, config)
    local navigation_options = config.navigation_options
    local settings = config.settings
    local api = config.api
    local entry_service = config.entry_service
    local direction = navigation_options.direction

    -- Validate input
    local valid, error_msg = NavigationUtils.validateNavigationInput(entry_info, api)
    if not valid then
        Notification:warning(error_msg)
        return
    end

    -- Load metadata
    local metadata, published_unix, metadata_error = NavigationUtils.loadEntryMetadata(entry_info)
    if not metadata then
        Notification:warning(metadata_error)
        return
    end

    -- Build navigation options
    local nav_options, options_error = NavigationUtils.buildNavigationOptions(published_unix, direction, settings)
    if not nav_options then
        Notification:warning(options_error)
        return
    end

    -- Perform search
    local success, result = NavigationUtils.performNavigationSearch(nav_options, direction, api)

    if success and result and result.entries and #result.entries > 0 then
        local target_entry = result.entries[1]

        -- Try local file first, fallback to reading entry
        if not NavigationUtils.tryLocalFileFirst(entry_info, target_entry, entry_service) then
            entry_service:readEntry(target_entry)
        end
    else
        local no_entry_msg = direction == DIRECTION_PREVIOUS
            and _("No previous entry available")
            or _("No next entry available")

        Notification:info(no_entry_msg)
    end
end

-- =============================================================================
-- HELPER FUNCTIONS (PURE FUNCTIONS)
-- =============================================================================

---Validate navigation input parameters
---@param entry_info table Entry information with file_path and entry_id
---@param api table API client instance
---@return boolean success, string? error_message
function NavigationUtils.validateNavigationInput(entry_info, api)
    if not entry_info.entry_id then
        return false, _("Cannot navigate: missing entry ID")
    end

    if not api then
        return false, _("Cannot navigate: API not available")
    end

    if not NavigationContext.hasValidContext() then
        return false, _("Cannot navigate: no browsing context available")
    end

    return true
end

---Load and validate entry metadata
---@param entry_info table Entry information
---@return table? metadata, number? published_unix, string? error_message
function NavigationUtils.loadEntryMetadata(entry_info)
    local metadata = MetadataLoader.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        return nil, nil, _("Cannot navigate: missing timestamp information")
    end

    local published_unix
    local ok = pcall(function()
        published_unix = TimeUtils.iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        return nil, nil, _("Cannot navigate: invalid timestamp format")
    end

    return metadata, published_unix
end

---Build navigation options based on direction
---@param published_unix number Unix timestamp of current entry
---@param direction string Navigation direction ("previous" or "next")
---@param settings table Settings instance
---@return table? options, string? error_message
function NavigationUtils.buildNavigationOptions(published_unix, direction, settings)
    local base_options = {
        limit = settings.limit,
        order = settings.order,
        direction = settings.direction,
        status = settings.hide_read_entries and { "unread" } or { "unread", "read" },
    }

    local options = NavigationContext.getContextAwareOptions(base_options)
    if not options then
        return nil, _("Cannot navigate: failed to get context options")
    end

    if direction == DIRECTION_PREVIOUS then
        options.direction = DIRECTION_ASC
        options[PUBLISHED_AFTER] = published_unix
    elseif direction == DIRECTION_NEXT then
        options.direction = DIRECTION_DESC
        options[PUBLISHED_BEFORE] = published_unix
    else
        return nil, _("Invalid navigation direction")
    end

    options.limit = 1
    options.order = settings.order

    return options
end

---Try to open local file if it exists
---@param entry_info table Current entry information
---@param entry_data table Entry data from API
---@param entry_service table Entry service instance
---@return boolean success True if local file was opened
function NavigationUtils.tryLocalFileFirst(entry_info, entry_data, entry_service)
    local entry_id = tostring(entry_data.id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")

    if miniflux_dir then
        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
        local html_file = entry_dir .. "entry.html"

        if lfs.attributes(html_file, "mode") == "file" then
            entry_service:openEntryFile(html_file)
            return true
        end
    end

    return false
end

---Perform navigation search
---@param options table API options for search
---@param direction string Navigation direction for loading message
---@param api table API client instance
---@return boolean success, table|string result_or_error
function NavigationUtils.performNavigationSearch(options, direction, api)
    local loading_message = direction == DIRECTION_PREVIOUS and MSG_FINDING_PREVIOUS or MSG_FINDING_NEXT

    return api.entries:getEntries(options, {
        dialogs = {
            loading = { text = loading_message }
        }
    })
end

return NavigationUtils
