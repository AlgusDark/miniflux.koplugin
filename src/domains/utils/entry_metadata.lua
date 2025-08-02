local EntryPaths = require('domains/utils/entry_paths')
local EntryValidation = require('domains/utils/entry_validation')
local Error = require('shared/error')
local logger = require('logger')

-- **Entry Metadata Utilities** - DocSettings operations and metadata management
-- Handles saving, loading, and updating entry metadata using KOReader's DocSettings
local EntryMetadata = {}

---@class EntryMetadata
---@field id number
---@field title string
---@field url string
---@field status string
---@field published_at string
---@field feed {id: number, title: string}
---@field category {id: number, title: string}
---@field images table<string, string> Image mapping (filename -> URL)
---@field last_updated string

---Save metadata for an entry using DocSettings
---@param params table Parameters: entry_data, images_mapping
---@return nil, Error|nil error
function EntryMetadata.saveMetadata(params)
    local entry_data = params.entry_data
    if not entry_data or not entry_data.id then
        return nil, Error.new('Invalid entry data')
    end

    local images_mapping = params.images_mapping or {}

    local html_file = EntryPaths.getEntryHtmlPath(entry_data.id)
    if not html_file then
        return nil, Error.new('Could not determine HTML file path')
    end

    local DocSettings = require('docsettings')
    local doc_settings = DocSettings:open(html_file)

    local entry_metadata = {
        id = entry_data.id,
        title = entry_data.title,
        url = entry_data.url,
        status = entry_data.status,
        published_at = entry_data.published_at,
        images = images_mapping,
        last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time()),
    }

    if entry_data.feed then
        entry_metadata.feed = {
            id = entry_data.feed.id,
            title = entry_data.feed.title,
        }

        if entry_data.feed.category then
            entry_metadata.category = {
                id = entry_data.feed.category.id,
                title = entry_data.feed.category.title,
            }
        end
    end

    doc_settings:saveSetting('miniflux_entry', entry_metadata)
    doc_settings:flush()

    local MinifluxBrowser = require('features/browser/miniflux_browser')
    MinifluxBrowser.setEntryInfoCache(entry_data.id, {
        id = entry_data.id,
        status = entry_data.status,
        title = entry_data.title,
        published_at = entry_data.published_at,
        url = entry_data.url,
        feed = entry_metadata.feed,
        category = entry_metadata.category,
    })

    return nil, nil
end

---@class EntryStatusOptions
---@field new_status string New status ("read" or "unread")
---@field doc_settings? table Optional ReaderUI DocSettings instance to use

---Update local entry status using DocSettings
---@param entry_id number Entry ID
---@param opts EntryStatusOptions Options for status update
function EntryMetadata.updateEntryStatus(entry_id, opts)
    local new_status = opts.new_status
    local doc_settings = opts.doc_settings
    local timestamp = os.date('%Y-%m-%d %H:%M:%S', os.time())

    logger.dbg('[Miniflux:EntryMetadata] Updating entry', entry_id, 'status to', new_status)

    local _sdr, sdr_err = EntryMetadata.updateMetadata(entry_id, {
        status = new_status,
    })

    if sdr_err then
        logger.warn(
            '[Miniflux:EntryMetadata] File metadata update failed for entry',
            entry_id,
            '- continuing with other updates:',
            sdr_err.message or sdr_err
        )
    end

    -- Also update ReaderUI DocSettings if available (for immediate UI consistency)
    if doc_settings then
        local ui_entry_metadata = doc_settings:readSetting('miniflux_entry')
        if ui_entry_metadata then
            ui_entry_metadata.status = new_status
            ui_entry_metadata.last_updated = timestamp
            doc_settings:saveSetting('miniflux_entry', ui_entry_metadata)
            logger.dbg('[Miniflux:EntryMetadata] Updated ReaderUI DocSettings for entry', entry_id)
        else
            logger.warn(
                '[Miniflux:EntryMetadata] No miniflux_entry in ReaderUI DocSettings for entry',
                entry_id
            )
        end
    end
end

---Load metadata for an entry using DocSettings
---@param entry_id number Entry ID
---@return EntryMetadata|nil Metadata table or nil if failed
function EntryMetadata.loadMetadata(entry_id)
    if not EntryValidation.isValidId(entry_id) then
        return nil
    end

    local html_file = EntryPaths.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil
    end

    local DocSettings = require('docsettings')

    -- Use KOReader's pattern for checking sidecar existence
    if not DocSettings:hasSidecarFile(html_file) then
        return nil
    end

    local doc_settings = DocSettings:open(html_file)

    local entry_metadata = doc_settings:readSetting('miniflux_entry')
    if not entry_metadata or not entry_metadata.id then
        return nil
    end

    return entry_metadata
end

---Update metadata for an entry with flexible field updates
---@param entry_id number Entry ID
---@param updates table Key-value pairs of nested fields to update
---@return nil, Error|nil error
function EntryMetadata.updateMetadata(entry_id, updates)
    if not EntryValidation.isValidId(entry_id) then
        return nil, Error.new('Invalid entry ID')
    end

    local html_file = EntryPaths.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil, Error.new('Could not determine HTML file path')
    end

    local DocSettings = require('docsettings')
    local doc_settings = DocSettings:open(html_file)

    local entry_metadata = doc_settings:readSetting('miniflux_entry')
    if not entry_metadata or not entry_metadata.id then
        return nil, Error.new('No miniflux metadata found')
    end

    -- Update nested fields
    for key, value in pairs(updates) do
        entry_metadata[key] = value
    end

    -- Always update timestamp
    entry_metadata.last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time())

    doc_settings:saveSetting('miniflux_entry', entry_metadata)

    local MinifluxBrowser = require('features/browser/miniflux_browser')
    MinifluxBrowser.setEntryInfoCache(entry_id, {
        id = entry_id,
        status = entry_metadata.status,
        title = entry_metadata.title,
        published_at = entry_metadata.published_at,
        url = entry_metadata.url,
        feed = entry_metadata.feed,
        category = entry_metadata.category,
    })

    doc_settings:flush()
    return nil, nil
end

return EntryMetadata
