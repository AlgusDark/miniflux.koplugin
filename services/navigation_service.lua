--[[--
Navigation Utilities for Miniflux Entries

Consolidated navigation utilities including context management and entry navigation
logic. Combines functionality from navigation_context and navigation_utils for
better organization.

@module miniflux.utils.navigation
--]]

local lfs = require("libs/libkoreader-lfs")
local Notification = require("utils/notification")
local _ = require("gettext")

-- Import dependencies
local TimeUtils = require("utils/time_utils")
local Error = require("utils/error")

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
---@param opts table Options containing base_options, context, entry_metadata
---@return ApiOptions Context-aware options with feed_id/category_id filters
function Navigation.getContextAwareOptions(opts)
    -- Extract parameters from opts
    local base_options = opts.base_options
    local context = opts.context
    local entry_metadata = opts.entry_metadata

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
---@param config {navigation_options: {direction: string}, settings: MinifluxSettings, miniflux_api: MinifluxAPI, entry_service: EntryService, miniflux_plugin: Miniflux}
---@return nil
function Navigation.navigateToEntry(entry_info, config)
    local navigation_options = config.navigation_options
    local settings = config.settings
    local miniflux_api = config.miniflux_api
    local entry_service = config.entry_service
    local miniflux_plugin = config.miniflux_plugin
    local direction = navigation_options.direction

    -- Validate input
    local valid, err = Navigation.validateNavigationInput(entry_info, miniflux_api)
    if err then
        Notification:warning(err.message)
        return
    end

    -- Load metadata
    local metadata_result, metadata_err = Navigation.loadEntryMetadata(entry_info)
    if metadata_err then
        Notification:warning(metadata_err.message)
        return
    end
    ---@cast metadata_result -nil

    local metadata = metadata_result.metadata
    local published_unix = metadata_result.published_unix

    -- Get browser context from plugin
    local context
    if miniflux_plugin then
        context = miniflux_plugin:getBrowserContext() or { type = "global" }
    else
        context = { type = "global" }
    end

    -- Build navigation options
    local nav_options, options_err = Navigation.buildNavigationOptions({
        published_unix = published_unix,
        direction = direction,
        settings = settings,
        context = context,
        metadata = metadata
    })
    if options_err then
        Notification:warning(options_err.message)
        return
    end
    ---@cast nav_options -nil

    -- Perform search
    local success, result = Navigation.performNavigationSearch({
        options = nav_options,
        direction = direction,
        miniflux_api = miniflux_api,
        current_entry_id = entry_info.entry_id
    })

    if success and result and result.entries and #result.entries > 0 then
        local target_entry = result.entries[1]

        -- Try local file first, fallback to reading entry
        if not Navigation.tryLocalFileFirst(entry_info, target_entry) then
            entry_service:readEntry(target_entry)
        end
    else
        -- Handle different failure scenarios with appropriate messages
        local no_entry_msg

        if result == "offline_no_entries" then
            -- Offline mode but no local entries available
            no_entry_msg = direction == DIRECTION_PREVIOUS
                and _("No previous entry available in local files")
                or _("No next entry available in local files")
        else
            -- Online mode but server has no more entries
            no_entry_msg = direction == DIRECTION_PREVIOUS
                and _("No previous entry available on server")
                or _("No next entry available on server")
        end

        Notification:info(no_entry_msg)
    end
end

-- =============================================================================
-- NAVIGATION HELPER FUNCTIONS (PURE FUNCTIONS)
-- =============================================================================

---Validate navigation input parameters
---@param entry_info table Entry information with file_path and entry_id
---@param miniflux_api table Miniflux API instance
---@return boolean|nil result, Error|nil error
function Navigation.validateNavigationInput(entry_info, miniflux_api)
    if not entry_info.entry_id then
        return nil, Error.new(_("Cannot navigate: missing entry ID"))
    end

    if not miniflux_api then
        return nil, Error.new(_("Cannot navigate: Miniflux API not available"))
    end

    -- Note: Plugin can be nil (for direct file opening), context will default to global
    return true, nil
end

---Load and validate entry metadata
---@param entry_info table Entry information
---@return {metadata: EntryMetadata, published_unix: number}|nil result, Error|nil error
function Navigation.loadEntryMetadata(entry_info)
    local EntryEntity = require("entities/entry_entity")
    local metadata = EntryEntity.loadMetadata(entry_info.entry_id)
    if not metadata or not metadata.published_at then
        return nil, Error.new(_("Cannot navigate: missing timestamp information"))
    end

    local published_unix, time_err = TimeUtils.iso8601_to_unix(metadata.published_at)
    if time_err then
        return nil, Error.new(_("Cannot navigate: invalid timestamp format"))
    end
    ---@cast published_unix -nil

    return { metadata = metadata, published_unix = published_unix }, nil
end

---Build navigation options based on direction
---@param config {published_unix: number, direction: string, settings: table, context: table, metadata: table}
---@return table|nil result, Error|nil error
function Navigation.buildNavigationOptions(config)
    local published_unix = config.published_unix
    local direction = config.direction
    local settings = config.settings
    local context = config.context
    local metadata = config.metadata

    local base_options = {
        limit = settings.limit,
        order = settings.order,
        direction = settings.direction,
        status = settings.hide_read_entries and { "unread" } or { "unread", "read" },
    }

    local options = Navigation.getContextAwareOptions({
        base_options = base_options,
        context = context,
        entry_metadata = metadata
    })
    if not options then
        return nil, Error.new(_("Cannot navigate: failed to get context options"))
    end

    if direction == DIRECTION_PREVIOUS then
        options.direction = DIRECTION_ASC
        options[PUBLISHED_AFTER] = published_unix
    elseif direction == DIRECTION_NEXT then
        options.direction = DIRECTION_DESC
        options[PUBLISHED_BEFORE] = published_unix
    else
        return nil, Error.new(_("Invalid navigation direction"))
    end

    options.limit = 1
    options.order = settings.order

    return options, nil
end

---Try to open local file if it exists
---@param entry_info table Current entry information
---@param entry_data table Entry data from API
---@return boolean success True if local file was opened
function Navigation.tryLocalFileFirst(entry_info, entry_data)
    local entry_id = tostring(entry_data.id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")

    if miniflux_dir then
        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
        local html_file = entry_dir .. "entry.html"

        if lfs.attributes(html_file, "mode") == "file" then
            local EntryEntity = require("entities/entry_entity")
            EntryEntity.openEntry(html_file)
            return true
        end
    end

    return false
end

---Perform navigation search with offline fallback
---@param config {options: ApiOptions, direction: string, miniflux_api: MinifluxAPI, current_entry_id: number}
---@return boolean success, table|string result_or_error
function Navigation.performNavigationSearch(config)
    local options = config.options
    local direction = config.direction
    local miniflux_api = config.miniflux_api
    local current_entry_id = config.current_entry_id

    local loading_message = direction == DIRECTION_PREVIOUS and MSG_FINDING_PREVIOUS or MSG_FINDING_NEXT

    -- Try API call first
    local result, err = miniflux_api:getEntries(options, {
        dialogs = {
            loading = { text = loading_message }
        }
    })

    -- If API call succeeds, return result
    if not err then
        ---@cast result -nil
        return true, result
    end

    -- API call failed - try simple offline navigation
    local target_entry_id = Navigation.findAdjacentEntryId(current_entry_id, direction)
    if target_entry_id then
        Notification:info(_("Found a local entry"))
        -- Create minimal entry data for navigation
        return true, {
            entries = { { id = target_entry_id } }
        }
    else
        -- Both API and offline failed - return special marker for offline failure
        return false, "offline_no_entries"
    end
end

---Find adjacent entry ID by scanning miniflux folder names
---@param current_entry_id number Current entry ID
---@param direction string Navigation direction ("previous" or "next")
---@return number|nil target_entry_id Adjacent entry ID, or nil if not found
function Navigation.findAdjacentEntryId(current_entry_id, direction)
    local EntryEntity = require("entities/entry_entity")
    local miniflux_dir = EntryEntity.getDownloadDir()

    if lfs.attributes(miniflux_dir, "mode") ~= "directory" then
        return nil
    end

    local target_id = nil

    for entry_dir_name in lfs.dir(miniflux_dir) do
        local entry_id = tonumber(entry_dir_name)
        if entry_id then
            local is_candidate = false
            local is_better_candidate = false

            if direction == DIRECTION_PREVIOUS then
                -- Looking for largest ID smaller than current
                is_candidate = entry_id < current_entry_id
                is_better_candidate = target_id == nil or entry_id > target_id
            else -- DIRECTION_NEXT
                -- Looking for smallest ID larger than current
                is_candidate = entry_id > current_entry_id
                is_better_candidate = target_id == nil or entry_id < target_id
            end

            if is_candidate and is_better_candidate then
                -- Only check file existence for potential candidates
                local html_file = miniflux_dir .. entry_dir_name .. "/entry.html"
                if lfs.attributes(html_file, "mode") == "file" then
                    target_id = entry_id
                end
            end
        end
    end

    return target_id
end

return Navigation
