--[[--
Navigation Utilities for Miniflux Entries

Consolidated navigation utilities including context management and entry navigation
logic. Combines functionality from navigation_context and navigation_utils for
better organization.

@module miniflux.utils.navigation
--]]

local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Notification = require("utils/notification")
local _ = require("gettext")

-- Import dependencies
local Files = require("utils/files")
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

local Navigation = {}

-- =============================================================================
-- NAVIGATION CONTEXT UTILITIES
-- =============================================================================

---Get API options based on navigation context and entry metadata
---@param base_options ApiOptions Base API options from settings
---@param context {type: string}|nil Browser context from plugin
---@param entry_metadata table Entry metadata for deriving IDs
---@return ApiOptions Context-aware options with feed_id/category_id filters
function Navigation.getContextAwareOptions(base_options, context, entry_metadata)
    local options = {}

    -- Copy base options
    for k, v in pairs(base_options) do
        options[k] = v
    end

    -- Add context-aware filtering based on browsing context
    if context and context.type == "feed" and entry_metadata.feed then
        options.feed_id = entry_metadata.feed.id
    elseif context and context.type == "category" and entry_metadata.category then
        options.category_id = entry_metadata.category.id
    end
    -- For "global" type or nil context, no additional filtering (browse all entries)



    return options
end

-- =============================================================================
-- ENTRY NAVIGATION LOGIC
-- =============================================================================

---Navigate to an entry in specified direction
---@param entry_info table Current entry information with file_path and entry_id
---@param config table Configuration with navigation_options, settings, api, entry_service, miniflux_plugin
---@return nil
function Navigation.navigateToEntry(entry_info, config)
    local navigation_options = config.navigation_options
    local settings = config.settings
    local api = config.api
    local entry_service = config.entry_service
    local miniflux_plugin = config.miniflux_plugin
    local direction = navigation_options.direction

    -- Validate input
    local valid, error_msg = Navigation.validateNavigationInput(entry_info, api, miniflux_plugin)
    if not valid then
        Notification:warning(error_msg)
        return
    end

    -- Load metadata
    local metadata, published_unix, metadata_error = Navigation.loadEntryMetadata(entry_info)
    if not metadata then
        Notification:warning(metadata_error)
        return
    end

    -- Get browser context from plugin
    local context
    if miniflux_plugin then
        context = miniflux_plugin:getBrowserContext() or { type = "global" }
    else
        context = { type = "global" }
    end

    -- Build navigation options
    local nav_options, options_error = Navigation.buildNavigationOptions(published_unix, direction, settings, context,
        metadata)
    if not nav_options then
        Notification:warning(options_error)
        return
    end

    -- Perform search
    local success, result = Navigation.performNavigationSearch(nav_options, direction, api)

    if success and result and result.entries and #result.entries > 0 then
        local target_entry = result.entries[1]

        -- Try local file first, fallback to reading entry
        if not Navigation.tryLocalFileFirst(entry_info, target_entry, entry_service) then
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
-- NAVIGATION HELPER FUNCTIONS (PURE FUNCTIONS)
-- =============================================================================

---Validate navigation input parameters
---@param entry_info table Entry information with file_path and entry_id
---@param api table API client instance
---@param miniflux_plugin table Plugin instance for context
---@return boolean success, string? error_message
function Navigation.validateNavigationInput(entry_info, api, miniflux_plugin)
    if not entry_info.entry_id then
        return false, _("Cannot navigate: missing entry ID")
    end

    if not api then
        return false, _("Cannot navigate: API not available")
    end

    -- Note: Plugin can be nil (for direct file opening), context will default to global
    return true
end

---Load and validate entry metadata
---@param entry_info table Entry information
---@return table? metadata, number? published_unix, string? error_message
function Navigation.loadEntryMetadata(entry_info)
    local metadata = Files.loadCurrentEntryMetadata(entry_info)
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
---@param context table Browser context from plugin
---@param metadata table Entry metadata for deriving IDs
---@return table? options, string? error_message
function Navigation.buildNavigationOptions(published_unix, direction, settings, context, metadata)
    local base_options = {
        limit = settings.limit,
        order = settings.order,
        direction = settings.direction,
        status = settings.hide_read_entries and { "unread" } or { "unread", "read" },
    }

    local options = Navigation.getContextAwareOptions(base_options, context, metadata)
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
function Navigation.tryLocalFileFirst(entry_info, entry_data, entry_service)
    local entry_id = tostring(entry_data.id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")

    if miniflux_dir then
        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
        local html_file = entry_dir .. "entry.html"

        if lfs.attributes(html_file, "mode") == "file" then
            local EntryUtils = require("utils/entry_utils")
            EntryUtils.openEntry(html_file)
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
function Navigation.performNavigationSearch(options, direction, api)
    local loading_message = direction == DIRECTION_PREVIOUS and MSG_FINDING_PREVIOUS or MSG_FINDING_NEXT

    return api.entries:getEntries(options, {
        dialogs = {
            loading = { text = loading_message }
        }
    })
end

return Navigation
