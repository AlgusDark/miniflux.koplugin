local EntryPaths = require('domains/utils/entry_paths')
local Error = require('shared/error')
local _ = require('gettext')

-- **Entry Validation Utilities** - Business rules and validation logic for entries
-- Handles entry ID validation, content checks, and status operations
local EntryValidation = {}

---Check if entry ID is valid
---@param entry_id any Entry ID to validate
---@return boolean True if valid number > 0
function EntryValidation.isValidId(entry_id)
    return type(entry_id) == 'number' and entry_id > 0
end

---Check if entry has content to display
---@param entry_data table Entry data from API
---@return boolean True if has content
function EntryValidation.hasContent(entry_data)
    if entry_data.id and EntryPaths.isEntryDownloaded(entry_data.id) then
        return true
    end
    local content = entry_data.content or entry_data.summary or ''
    return content ~= ''
end

---Validate entry data for download
---@param entry_data table Entry data from API
---@return boolean|nil result, Error|nil error
function EntryValidation.validateForDownload(entry_data)
    if not entry_data or type(entry_data) ~= 'table' then
        return nil, Error.new(_('Invalid entry data'))
    end

    if not EntryValidation.isValidId(entry_data.id) then
        return nil, Error.new(_('Invalid entry ID'))
    end

    if not EntryValidation.hasContent(entry_data) then
        return nil, Error.new(_('No content available for this entry'))
    end

    return true, nil
end

---Check if entry is read
---@param status string Entry status
---@return boolean True if entry is read
function EntryValidation.isEntryRead(status)
    return status == 'read'
end

---Get the appropriate toggle button text for current status
---@param status string Entry status
---@return string Button text for marking entry
function EntryValidation.getStatusButtonText(status)
    if EntryValidation.isEntryRead(status) then
        return _('✓ Mark as unread')
    else
        return _('✓ Mark as read')
    end
end

return EntryValidation
