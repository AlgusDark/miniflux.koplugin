local lfs = require('libs/libkoreader-lfs')
local Notification = require('shared/widgets/notification')
local _ = require('gettext')
local logger = require('logger')

-- Import dependencies
local Error = require('shared/error')
local EntryPaths = require('domains/utils/entry_paths')
local EntryCollections = require('domains/utils/entry_collections')
local EntryMetadata = require('domains/utils/entry_metadata')

-- Constants
local DIRECTION_PREVIOUS = 'previous'
local DIRECTION_NEXT = 'next'
local DIRECTION_ASC = 'asc'
local DIRECTION_DESC = 'desc'
local PUBLISHED_AFTER = 'published_after'
local PUBLISHED_BEFORE = 'published_before'
local MSG_FINDING_PREVIOUS = 'Finding previous entry...'
local MSG_FINDING_NEXT = 'Finding next entry...'

function iso8601_to_unix(iso_string)
    local Y, M, D, h, m, sec, sign, tzh, tzm =
        iso_string:match('(%d+)%-(%d+)%-(%d+)T' .. '(%d+):(%d+):(%d+)' .. '([%+%-])(%d%d):(%d%d)$')

    if not Y then
        return nil, Error.new(_('Invalid ISO-8601 timestamp format'))
    end

    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    tzh, tzm = tonumber(tzh), tonumber(tzm)

    local y = Y
    local mo = M
    if mo <= 2 then
        y = y - 1
        mo = mo + 12
    end

    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (mo - 3) + 2) / 5) + D - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468

    local utc_secs = days * 86400 + h * 3600 + m * 60 + sec

    local offs = tzh * 3600 + tzm * 60
    if sign == '+' then
        utc_secs = utc_secs - offs
    else
        utc_secs = utc_secs + offs
    end

    return utc_secs, nil
end

-- **Navigation Service** - Consolidated navigation utilities including context
-- management and entry navigation logic. Combines functionality from
-- navigation_context and navigation_utils for better organization.
local Navigation = {}

-- =============================================================================
-- ENTRY NAVIGATION LOGIC
-- =============================================================================

---Navigate to an entry in specified direction
---@param entry_info table Current entry information with file_path and entry_id
---@param miniflux Miniflux Miniflux plugin instance containing all dependencies
---@param navigation_options {direction: string} Navigation options
---@return nil
function Navigation.navigateToEntry(entry_info, miniflux, navigation_options)
    local direction = navigation_options.direction

    -- Validate input
    if not entry_info.entry_id then
        logger.err('[Miniflux:NavigationService] Navigation failed: missing entry ID')
        Notification:warning(_('Cannot navigate: missing entry ID'))
        return
    end
    if not miniflux.entries then
        logger.err('[Miniflux:NavigationService] Navigation failed: Entries domain not available')
        Notification:warning(_('Cannot navigate: Entries service not available'))
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

    -- Get navigation context from browser context
    local context = miniflux:getBrowserContext()

    if not context then
        -- Default to global context if no specific context is cached
        context = { type = 'global' }
    end

    -- Handle local navigation separately (skip API entirely)
    if context and context.type == 'local' then
        Navigation.handleLocalNavigation({
            entry_info = entry_info,
            miniflux = miniflux,
            direction = direction,
        })
        return
    end

    -- Handle API navigation with offline fallback
    Navigation.handleApiNavigation({
        entry_info = entry_info,
        miniflux = miniflux,
        direction = direction,
        metadata = metadata,
        published_unix = published_unix,
        context = context,
    })
end

---Handle API-based navigation with offline fallback
---@param options {entry_info: table, miniflux: table, direction: string, metadata: table, published_unix: number, context: table}
---@return nil
function Navigation.handleApiNavigation(options)
    local entry_info = options.entry_info
    local miniflux = options.miniflux
    local direction = options.direction
    local metadata = options.metadata
    local published_unix = options.published_unix
    local context = options.context

    -- Build navigation options
    local nav_options, options_err = Navigation.buildNavigationOptions(
        { metadata = metadata, published_unix = published_unix },
        { direction = direction, settings = miniflux.settings, context = context }
    )
    if options_err then
        Notification:warning(options_err.message)
        return
    end
    ---@cast nav_options -nil

    -- Perform search
    local success, result = Navigation.performNavigationSearch(
        { options = nav_options, direction = direction },
        { entries = miniflux.entries, current_entry_id = entry_info.entry_id }
    )

    if success and result and result.entries and #result.entries > 0 then
        local target_entry = result.entries[1]

        -- Try local file first, fallback to reading entry
        if
            not Navigation.tryLocalFileFirst({
                entry_info = entry_info,
                entry_data = target_entry,
                context = context,
            })
        then
            -- Use workflow directly for download-if-needed and open
            local EntryWorkflow = require('features/browser/download/download_entry')
            EntryWorkflow.execute({
                entry_data = target_entry,
                settings = miniflux.settings,
                context = context,
            })
        end
    else
        -- Handle different failure scenarios with appropriate messages
        local no_entry_msg

        if result == 'offline_no_entries' then
            -- Offline mode but no local entries available
            no_entry_msg = direction == DIRECTION_PREVIOUS
                    and _('No previous entry available in local files')
                or _('No next entry available in local files')
        else
            -- Online mode but server has no more entries
            no_entry_msg = direction == DIRECTION_PREVIOUS
                    and _('No previous entry available on server')
                or _('No next entry available on server')
        end

        Notification:info(no_entry_msg)
    end
end

---Handle local navigation (skip API entirely)
---@param options {entry_info: table, miniflux: table, direction: string}
---@return nil
function Navigation.handleLocalNavigation(options)
    local entry_info = options.entry_info
    local miniflux = options.miniflux
    local direction = options.direction

    local nav_entries =
        EntryCollections.getLocalEntriesForNavigation({ settings = miniflux.settings })

    -- Create enhanced context with ordered entries (same pattern as browser)
    local enhanced_context = {
        type = 'local',
        ordered_entries = nav_entries,
    }

    local target_entry_id = Navigation.navigateLocalEntries({
        current_entry_id = entry_info.entry_id,
        direction = direction,
        ordered_entries = nav_entries,
    })

    if target_entry_id then
        -- Get the full entry data for the target entry
        local target_entry_data = EntryMetadata.loadMetadata(target_entry_id)

        if target_entry_data then
            -- Open the local entry using the same method as browser
            local EntryWorkflow = require('features/browser/download/download_entry')
            EntryWorkflow.execute({
                entry_data = target_entry_data,
                settings = miniflux.settings,
                context = enhanced_context,
            })
        else
            logger.err(
                '[Miniflux:NavigationService] Failed to load metadata for entry:',
                target_entry_id
            )
            Notification:error(_('Failed to open target entry'))
        end
    else
        Notification:info(_('No ' .. direction .. ' entry available in local files'))
    end
end

-- =============================================================================
-- NAVIGATION HELPER FUNCTIONS (PURE FUNCTIONS)
-- =============================================================================

---Load and validate entry metadata
---@param entry_info table Entry information
---@return {metadata: EntryMetadata, published_unix: number}|nil result, Error|nil error
function Navigation.loadEntryMetadata(entry_info)
    local metadata = EntryMetadata.loadMetadata(entry_info.entry_id)
    if not metadata or not metadata.published_at then
        return nil, Error.new(_('Cannot navigate: missing timestamp information'))
    end

    local published_unix, time_err = iso8601_to_unix(metadata.published_at)
    if time_err then
        return nil, Error.new(_('Cannot navigate: invalid timestamp format'))
    end
    ---@cast published_unix -nil

    return { metadata = metadata, published_unix = published_unix }, nil
end

---Build navigation options based on direction
---@param entry_context {metadata: table, published_unix: number} Entry metadata and timestamp
---@param nav_request {direction: string, settings: table, context: table?} Navigation request details
---@return table|nil result, Error|nil error
function Navigation.buildNavigationOptions(entry_context, nav_request)
    local metadata = entry_context.metadata
    local published_unix = entry_context.published_unix
    local direction = nav_request.direction
    local settings = nav_request.settings
    local context = nav_request.context

    local base_options = {
        limit = settings.limit,
        order = settings.order,
        direction = settings.direction,
        status = settings.hide_read_entries and { 'unread' } or { 'unread', 'read' },
    }

    -- For unread context, always filter by unread status regardless of settings
    if context and context.type == 'unread' then
        base_options.status = { 'unread' }
    end

    local options = {}
    -- Copy base options
    for k, v in pairs(base_options) do
        options[k] = v
    end

    -- Add context-aware filtering
    if context and context.type == 'feed' then
        options.feed_id = context.id or (metadata.feed and metadata.feed.id)
    elseif context and context.type == 'category' then
        options.category_id = context.id or (metadata.category and metadata.category.id)
    end

    if direction == DIRECTION_PREVIOUS then
        options.direction = DIRECTION_ASC
        options[PUBLISHED_AFTER] = published_unix
    elseif direction == DIRECTION_NEXT then
        options.direction = DIRECTION_DESC
        options[PUBLISHED_BEFORE] = published_unix
    else
        return nil, Error.new(_('Invalid navigation direction'))
    end

    options.limit = 1
    options.order = settings.order

    return options, nil
end

---@class TryLocalFileOptions
---@field entry_info table Current entry information
---@field entry_data table Entry data from API
---@field context? MinifluxContext Navigation context to preserve

---Try to open local file if it exists
---@param opts TryLocalFileOptions Options for local file attempt
---@return boolean success True if local file was opened
function Navigation.tryLocalFileFirst(opts)
    local entry_info = opts.entry_info
    local entry_data = opts.entry_data
    local context = opts.context

    local entry_id = tostring(entry_data.id)
    local miniflux_dir = entry_info.file_path:match('(.*)/miniflux/')

    if miniflux_dir then
        local entry_dir = miniflux_dir .. '/miniflux/' .. entry_id .. '/'
        local html_file = entry_dir .. 'entry.html'

        if lfs.attributes(html_file, 'mode') == 'file' then
            local EntryReader = require('features/reader/services/open_entry')
            EntryReader.openEntry(html_file, { context = context })
            return true
        end
    end

    return false
end

---Perform navigation search with offline fallback
---@param search_params {options: ApiOptions, direction: string} Search parameters
---@param api_context {entries: Entries, current_entry_id: number} Domain services and context info
---@return boolean success, table|string result_or_error
function Navigation.performNavigationSearch(search_params, api_context)
    local options = search_params.options
    local direction = search_params.direction
    local entries = api_context.entries
    local current_entry_id = api_context.current_entry_id

    local loading_message = direction == DIRECTION_PREVIOUS and MSG_FINDING_PREVIOUS
        or MSG_FINDING_NEXT

    -- Try API call first
    local result, err = entries:getEntries(options, {
        dialogs = {
            loading = { text = loading_message },
        },
    })

    -- If API call succeeds, return result
    if not err then
        ---@cast result -nil
        return true, result
    end

    logger.warn(
        '[Miniflux:NavigationService] API search failed, falling back to offline:',
        err.message or 'unknown error'
    )

    -- API call failed - try simple offline navigation
    local target_entry_id = Navigation.findAdjacentEntryId(current_entry_id, direction)
    if target_entry_id then
        logger.info('[Miniflux:NavigationService] Found offline entry:', target_entry_id)
        Notification:info(_('Found a local entry'))
        -- Create minimal entry data for navigation
        return true, {
            entries = { { id = target_entry_id } },
        }
    else
        -- Both API and offline failed - return special marker for offline failure
        return false, 'offline_no_entries'
    end
end

---Find adjacent entry ID by scanning miniflux folder names
---@param current_entry_id number Current entry ID
---@param direction string Navigation direction ("previous" or "next')
---@return number|nil target_entry_id Adjacent entry ID, or nil if not found
function Navigation.findAdjacentEntryId(current_entry_id, direction)
    local miniflux_dir = EntryPaths.getDownloadDir()

    if lfs.attributes(miniflux_dir, 'mode') ~= 'directory' then
        return nil
    end

    local target_id = nil

    for entry_dir_name in lfs.dir(miniflux_dir) do
        local entry_id = tonumber(entry_dir_name)
        if entry_id then
            -- Check if this entry is a valid candidate for navigation
            local is_valid_candidate
            if direction == DIRECTION_PREVIOUS then
                -- Looking for largest ID smaller than current
                is_valid_candidate = (entry_id < current_entry_id)
                    and (target_id == nil or entry_id > target_id)
            else -- DIRECTION_NEXT
                -- Looking for smallest ID larger than current
                is_valid_candidate = (entry_id > current_entry_id)
                    and (target_id == nil or entry_id < target_id)
            end

            if is_valid_candidate then
                -- Only check file existence for potential candidates
                local html_file = miniflux_dir .. entry_dir_name .. '/entry.html'
                if lfs.attributes(html_file, 'mode') == 'file' then
                    target_id = entry_id
                end
            end
        end
    end

    return target_id
end

---Navigate within local entries using pre-computed ordered list (optimized for performance)
---@param options {current_entry_id: number, direction: string, ordered_entries: table[]}
---@return number|nil Next entry ID or nil if no adjacent entry found
function Navigation.navigateLocalEntries(options)
    local current_entry_id = options.current_entry_id
    local direction = options.direction
    local ordered_entries = options.ordered_entries
    if not ordered_entries or #ordered_entries == 0 then
        return nil
    end

    -- Find current entry position in the ordered list
    local current_index = nil
    for i, entry in ipairs(ordered_entries) do
        if entry.id == current_entry_id then
            current_index = i
            break
        end
    end

    if not current_index then
        logger.warn(
            '[Miniflux:NavigationService] Current entry',
            current_entry_id,
            'not found in local entries'
        )
        return nil -- Current entry not found in local list
    end

    -- Calculate target index based on direction
    local target_index
    if direction == 'next' then
        target_index = current_index + 1
    else -- "previous"
        target_index = current_index - 1
    end

    -- Return target entry ID if valid position
    if target_index >= 1 and target_index <= #ordered_entries then
        return ordered_entries[target_index].id
    end

    return nil -- No adjacent entry available
end

return Navigation
