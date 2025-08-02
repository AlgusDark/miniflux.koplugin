local EntryPaths = require('domains/utils/entry_paths')
local lfs = require('libs/libkoreader-lfs')

-- **Entry Collections Utilities** - Local entry scanning, management, and sorting
-- Handles scanning miniflux directory for local entries and sorting operations
local EntryCollections = {}

---Get all locally downloaded entries by scanning the miniflux directory
---@param opts? {settings?: MinifluxSettings} Optional settings for sorting configuration
---@return table[] Array of entry metadata objects (same format as API entries)
function EntryCollections.getLocalEntries(opts)
    local entries = {}
    local miniflux_dir = EntryPaths.getDownloadDir()

    -- Check if miniflux directory exists
    if not lfs.attributes(miniflux_dir, 'mode') then
        return entries -- Return empty array if directory doesn't exist
    end

    -- Scan directory for entry folders
    for item in lfs.dir(miniflux_dir) do
        -- Skip . and .. entries, only process numeric folders (entry IDs)
        if item:match('^%d+$') then
            local entry_id = tonumber(item) --[[@as number]] -- Safe cast: regex ensures valid number

            -- Check if entry.html exists in this folder
            local html_file = EntryPaths.getEntryHtmlPath(entry_id)
            if lfs.attributes(html_file, 'mode') == 'file' then
                -- Try cache first, fallback to DocSettings loading
                local MinifluxBrowser = require('features/browser/miniflux_browser')
                local metadata = MinifluxBrowser.getCachedEntryOrLoad(entry_id)
                if metadata then
                    table.insert(entries, metadata)
                end
            end
        end
    end

    -- Extract sort criteria from settings and apply sorting
    local sort_opts = nil
    if opts and opts.settings then
        sort_opts = {
            order = opts.settings.order,
            direction = opts.settings.direction,
        }
    end

    -- Sort entries using configurable sorting (defaults to published_at desc)
    return EntryCollections.sortEntries(entries, sort_opts)
end

---Get lightweight local entries metadata optimized for navigation only
---Loads minimal data (id, published_at, title) for fast navigation context
---@param opts {settings?: MinifluxSettings} Options containing user settings for order and direction
---@return table[] Array of minimal entry metadata for navigation
function EntryCollections.getLocalEntriesForNavigation(opts)
    local entries = {}
    local miniflux_dir = EntryPaths.getDownloadDir()

    -- Check if miniflux directory exists
    if not lfs.attributes(miniflux_dir, 'mode') then
        return entries -- Return empty array if directory doesn't exist
    end

    local DocSettings = require('docsettings')

    -- Scan directory for entry folders
    for item in lfs.dir(miniflux_dir) do
        -- Skip . and .. entries, only process numeric folders (entry IDs)
        if item:match('^%d+$') then
            local entry_id = tonumber(item) --[[@as number]] -- Safe cast: regex ensures valid number
            local html_file = EntryPaths.getEntryHtmlPath(entry_id)

            if lfs.attributes(html_file, 'mode') == 'file' then
                -- Try cache first for navigation data
                local MinifluxBrowser = require('features/browser/miniflux_browser')
                local cached_entry = MinifluxBrowser.getEntryInfoCache(entry_id)

                if cached_entry then
                    -- Use cached data - only extract minimal fields needed for navigation
                    local nav_entry = {
                        id = entry_id,
                        published_at = cached_entry.published_at,
                        title = cached_entry.title,
                    }
                    table.insert(entries, nav_entry)
                else
                    -- Fallback to DocSettings loading
                    if DocSettings:hasSidecarFile(html_file) then
                        local doc_settings = DocSettings:open(html_file)
                        local entry_metadata = doc_settings:readSetting('miniflux_entry')
                        if entry_metadata and entry_metadata.id then
                            -- Load ONLY minimal data needed for navigation
                            local nav_entry = {
                                id = entry_id,
                                published_at = entry_metadata.published_at,
                                title = entry_metadata.title,
                            }
                            table.insert(entries, nav_entry)
                        end
                    end
                end
            end
        end
    end

    -- Extract sort criteria from settings and apply sorting
    local sort_opts = nil
    if opts and opts.settings then
        sort_opts = {
            order = opts.settings.order,
            direction = opts.settings.direction,
        }
    end

    -- Sort entries in-place and return sorted array
    return EntryCollections.sortEntries(entries, sort_opts)
end

---Sort entries array in-place for optimal performance
---@param entries table[] Array of entry metadata to sort (mutated in-place)
---@param opts {order?: string, direction?: string}|nil Sort options with defaults
---@return table[] The same array reference, now sorted (for chaining convenience)
function EntryCollections.sortEntries(entries, opts)
    if not entries or #entries == 0 then
        return entries
    end

    -- Apply defaults for sort criteria
    local order = (opts and opts.order) or 'published_at'
    local direction = (opts and opts.direction) or 'desc'

    table.sort(entries, function(a, b)
        local a_val, b_val

        -- Extract comparison values based on order setting
        if order == 'id' then
            a_val = a.id or 0
            b_val = b.id or 0
        elseif order == 'title' then
            a_val = (a.title or ''):lower() -- Case-insensitive title sort
            b_val = (b.title or ''):lower()
        else
            -- Default to published_at for unknown order values
            a_val = a.published_at or ''
            b_val = b.published_at or ''
        end

        -- Apply direction
        if direction == 'asc' then
            return a_val < b_val
        else
            return a_val > b_val
        end
    end)

    return entries -- Return same array reference for chaining
end

---Get adjacent local entry ID using cache-optimized navigation
---@param current_entry_id number Current entry ID
---@param direction string Direction: "next" or "previous"
---@param settings MinifluxSettings User settings for sorting
---@return number|nil adjacent_entry_id Adjacent entry ID or nil if not found
function EntryCollections.getAdjacentLocalEntry(current_entry_id, direction, settings)
    -- Get all local entry IDs in sorted order (lightweight operation)
    local entries = EntryCollections.getLocalEntriesForNavigation({ settings = settings })

    if not entries or #entries == 0 then
        return nil
    end

    -- Find current entry position in the ordered list
    local current_index = nil
    for i, entry in ipairs(entries) do
        if entry.id == current_entry_id then
            current_index = i
            break
        end
    end

    if not current_index then
        return nil -- Current entry not found in local entries
    end

    -- Calculate target index based on direction
    local target_index
    if direction == 'next' then
        target_index = current_index + 1
    else -- "previous"
        target_index = current_index - 1
    end

    -- Return target entry ID if valid position
    if target_index >= 1 and target_index <= #entries then
        return entries[target_index].id
    end

    return nil -- No adjacent entry available
end

return EntryCollections
