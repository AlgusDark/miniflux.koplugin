local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")
local Error = require("utils/error")
local _ = require("gettext")
local T = require("ffi/util").template

-- **Entry Entity** - Pure utility functions for entry operations, validation,
-- and business logic. Delegates file operations to Files utilities while
-- maintaining business logic.
local EntryEntity = {}

---Get the base download directory for all entries
---@return string Download directory path
function EntryEntity.getDownloadDir()
    return ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
end

---Get the local directory path for a specific entry
---@param entry_id number Entry ID
---@return string Entry directory path
function EntryEntity.getEntryDirectory(entry_id)
    return EntryEntity.getDownloadDir() .. tostring(entry_id) .. "/"
end

---Get the local HTML file path for a specific entry
---@param entry_id number Entry ID
---@return string HTML file path
function EntryEntity.getEntryHtmlPath(entry_id)
    return EntryEntity.getEntryDirectory(entry_id) .. "entry.html"
end

-- =============================================================================
-- VALIDATION UTILITIES
-- =============================================================================

---Check if entry ID is valid
---@param entry_id any Entry ID to validate
---@return boolean True if valid number > 0
function EntryEntity.isValidId(entry_id)
    return type(entry_id) == "number" and entry_id > 0
end

---Check if entry has content to display
---@param entry_data table Entry data from API
---@return boolean True if has content
function EntryEntity.hasContent(entry_data)
    -- For local entries that are already downloaded, content is always available
    if entry_data.id and EntryEntity.isEntryDownloaded(entry_data.id) then
        return true
    end

    -- For online entries, check content/summary fields
    local content = entry_data.content or entry_data.summary or ""
    return content ~= ""
end

---Validate entry data for download (enhanced with better error handling)
---@param entry_data table Entry data from API
---@return boolean|nil result, Error|nil error
function EntryEntity.validateForDownload(entry_data)
    if not entry_data or type(entry_data) ~= "table" then
        return nil, Error.new(_("Invalid entry data"))
    end

    if not EntryEntity.isValidId(entry_data.id) then
        return nil, Error.new(_("Invalid entry ID"))
    end

    if not EntryEntity.hasContent(entry_data) then
        return nil, Error.new(_("No content available for this entry"))
    end

    return true, nil
end

-- =============================================================================
-- STATUS UTILITIES
-- =============================================================================

---Check if entry is read
---@param status string Entry status
---@return boolean True if entry is read
function EntryEntity.isEntryRead(status)
    return status == "read"
end

---Get the appropriate toggle button text for current status
---@param status string Entry status
---@return string Button text for marking entry
function EntryEntity.getStatusButtonText(status)
    if EntryEntity.isEntryRead(status) then
        return _("✓ Mark as unread")
    else
        return _("✓ Mark as read")
    end
end

-- =============================================================================
-- FILE PATH UTILITIES
-- =============================================================================

---Check if file path is a miniflux entry
---@param file_path string File path to check
---@return boolean true if miniflux entry, false otherwise
function EntryEntity.isMinifluxEntry(file_path)
    if not file_path then
        return false
    end
    return file_path:match("/miniflux/") and file_path:match("%.html$")
end

---Extract entry ID from miniflux file path
---@param file_path string File path to check
---@return number|nil entry_id Entry ID or nil if not a miniflux entry
function EntryEntity.extractEntryIdFromPath(file_path)
    if not EntryEntity.isMinifluxEntry(file_path) then
        return nil
    end

    local entry_id_str = file_path:match("/miniflux/(%d+)/")
    return entry_id_str and tonumber(entry_id_str)
end

-- =============================================================================
-- FILE OPERATIONS
-- =============================================================================

---Check if entry is already downloaded locally
---@param entry_id number Entry ID
---@return boolean True if downloaded
function EntryEntity.isEntryDownloaded(entry_id)
    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    return lfs.attributes(html_file, "mode") == "file"
end

-- =============================================================================
-- METADATA OPERATIONS
-- =============================================================================

---@class EntryMetadata
---@field id number
---@field title string
---@field url string
---@field status string
---@field published_at string
---@field feed table

---Save metadata for an entry using DocSettings
---@param params table Parameters: entry_data, include_images, images_count
---@return string|nil result, Error|nil error
function EntryEntity.saveMetadata(params)
    local entry_data = params.entry_data
    if not entry_data or not entry_data.id then
        return nil, Error.new("Invalid entry data")
    end

    local include_images = params.include_images or false
    local images_count = params.images_count or 0

    local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)
    if not html_file then
        return nil, Error.new("Could not determine HTML file path")
    end

    local DocSettings = require("docsettings")
    local doc_settings = DocSettings:open(html_file)

    -- Use server status for initial metadata save
    local status_to_use = entry_data.status

    -- Prepare all settings
    local settings = {
        miniflux_entry_id = entry_data.id,
        miniflux_title = entry_data.title,
        miniflux_url = entry_data.url,
        miniflux_status = status_to_use,
        miniflux_published_at = entry_data.published_at,
        miniflux_images_included = include_images,
        miniflux_images_count = images_count,
        miniflux_last_updated = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    }

    -- Add nested data safely
    if entry_data.feed then
        settings.miniflux_feed_id = entry_data.feed.id
        settings.miniflux_feed_title = entry_data.feed.title

        if entry_data.feed.category then
            settings.miniflux_category_id = entry_data.feed.category.id
            settings.miniflux_category_title = entry_data.feed.category.title
        end
    end

    -- Save all non-nil settings
    for key, value in pairs(settings) do
        if value ~= nil then
            doc_settings:saveSetting(key, value)
        end
    end

    -- Return original pattern: flush result (string|nil) and error
    local flush_result = doc_settings:flush()
    return flush_result, nil
end

---Update local entry status using DocSettings
---@param entry_id number Entry ID
---@param new_status string New status ("read" or "unread")
---@param doc_settings? table Optional ReaderUI DocSettings instance to use
---@return boolean success
function EntryEntity.updateEntryStatus(entry_id, new_status, doc_settings)
    local success = true
    local timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time())

    -- Always update custom metadata (SDR file) - this is our reliable fallback
    local sdr_result, sdr_err = EntryEntity.updateMetadata(entry_id, {
        miniflux_status = new_status,
        miniflux_last_updated = timestamp,
    })

    if not sdr_result or sdr_err then
        success = false
    else
    end

    -- Also update ReaderUI DocSettings if available (for immediate UI consistency)
    if doc_settings then
        doc_settings:saveSetting("miniflux_status", new_status)
        doc_settings:saveSetting("miniflux_last_updated", timestamp)
        -- Don't flush here - let ReaderUI handle it when document closes
    end

    return success
end

---Load metadata for an entry using DocSettings
---@param entry_id number Entry ID
---@return EntryMetadata|nil Metadata table or nil if failed
function EntryEntity.loadMetadata(entry_id)
    if not EntryEntity.isValidId(entry_id) then
        return nil
    end

    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil
    end

    local DocSettings = require("docsettings")

    -- Use KOReader's pattern for checking sidecar existence
    if not DocSettings:hasSidecarFile(html_file) then
        return nil
    end

    local doc_settings = DocSettings:open(html_file)

    -- Check if this is actually a miniflux entry
    local stored_entry_id = doc_settings:readSetting("miniflux_entry_id")
    if not stored_entry_id then
        return nil
    end

    -- Batch read all settings into a local table for efficiency
    local settings_keys = {
        "miniflux_title",
        "miniflux_url",
        "miniflux_status",
        "miniflux_published_at",
        "miniflux_feed_id",
        "miniflux_feed_title",
        "miniflux_category_id",
        "miniflux_category_title",
        "miniflux_images_included",
        "miniflux_images_count",
        "miniflux_last_updated",
    }

    local settings = {}
    for _, key in ipairs(settings_keys) do
        settings[key] = doc_settings:readSetting(key)
    end

    -- Return structured metadata
    return {
        id = stored_entry_id,
        title = settings.miniflux_title,
        url = settings.miniflux_url,
        status = settings.miniflux_status,
        published_at = settings.miniflux_published_at,
        feed = {
            id = settings.miniflux_feed_id,
            title = settings.miniflux_feed_title,
        },
        category = {
            id = settings.miniflux_category_id,
            title = settings.miniflux_category_title,
        },
        images_included = settings.miniflux_images_included,
        images_count = settings.miniflux_images_count,
        last_updated = settings.miniflux_last_updated,
    }
end

---Update metadata for an entry with flexible field updates
---@param entry_id number Entry ID
---@param updates table Key-value pairs of fields to update (must be miniflux_ prefixed)
---@return DocSettings|nil doc_settings, Error|nil error
function EntryEntity.updateMetadata(entry_id, updates)
    if not EntryEntity.isValidId(entry_id) then
        return nil, Error.new("Invalid entry ID")
    end

    local html_file = EntryEntity.getEntryHtmlPath(entry_id)
    if not html_file then
        return nil, Error.new("Could not determine HTML file path")
    end

    local DocSettings = require("docsettings")

    -- Force fresh load to avoid stale cache issues
    local doc_settings = DocSettings:open(html_file)

    -- Check if this is actually a miniflux entry
    local stored_entry_id = doc_settings:readSetting("miniflux_entry_id")
    if not stored_entry_id then
        return nil, Error.new("No miniflux metadata found")
    end

    -- Update only the specified fields
    for key, value in pairs(updates) do
        if key:match("^miniflux_") then -- Safety check for miniflux fields
            doc_settings:saveSetting(key, value)
        end
    end

    -- Add timestamp
    doc_settings:saveSetting("miniflux_last_updated", os.date("%Y-%m-%d %H:%M:%S", os.time()))

    local flush_result = doc_settings:flush()
    if flush_result then
        return doc_settings, nil
    else
        return nil, Error.new("Failed to flush DocSettings")
    end
end

-- =============================================================================
-- UI UTILITIES
-- =============================================================================

---Show cancellation choice dialog with context-aware options
---@param context "during_images" | "after_images"
---@return string|nil User choice based on context (nil if dialog fails)
function EntryEntity.showCancellationDialog(context)
    local user_choice = nil
    local choice_dialog = nil --[[@type ButtonDialog]]

    -- Context-specific dialog configuration
    local dialog_config = {}

    if context == "during_images" then
        dialog_config = {
            title = _("Image download was cancelled.\nWhat would you like to do?"),
            buttons = {
                {
                    text = _("Cancel entry creation"),
                    choice = "cancel_entry",
                },
                {
                    text = _("Continue without images"),
                    choice = "continue_without_images",
                },
                {
                    text = _("Resume downloading"),
                    choice = "resume_downloading",
                },
            },
        }
    else -- "after_images"
        dialog_config = {
            title = _(
                "Entry creation was interrupted.\nImages have been downloaded successfully.\n\nWhat would you like to do?"
            ),
            buttons = {
                {
                    text = _("Cancel entry creation"),
                    choice = "cancel_entry",
                },
                {
                    text = _("Continue with entry creation"),
                    choice = "continue_creation",
                },
            },
        }
    end

    -- Build button table for ButtonDialog
    local dialog_buttons = { {} }
    for _, btn in ipairs(dialog_config.buttons) do
        table.insert(dialog_buttons[1], {
            text = btn.text,
            callback = function()
                user_choice = btn.choice
                UIManager:close(choice_dialog)
            end,
        })
    end

    -- Create dialog with context-specific configuration
    choice_dialog = ButtonDialog:new({
        title = dialog_config.title,
        title_align = "center",
        dismissable = false,
        buttons = dialog_buttons,
        -- Handle tap outside dialog - behave like "Cancel entry creation"
        -- tap_close_callback = function()
        --     user_choice = "cancel_entry"
        -- end,
    })

    UIManager:show(choice_dialog)

    -- Use proper modal dialog pattern
    repeat
        UIManager:handleInput()
    until user_choice ~= nil

    return user_choice
end

---Show batch cancellation choice dialog with stateful options
---@param context "during_entry_images" | "during_batch"
---@param batch_state table Batch state containing skip_images_for_all, current_entry_index, total_entries
---@return string|nil User choice based on context and state (nil if dialog fails)
function EntryEntity.showBatchCancellationDialog(context, batch_state)
    local user_choice = nil
    local choice_dialog = nil --[[@type ButtonDialog]]

    -- Extract state information
    local skip_images_for_all = batch_state.skip_images_for_all or false
    local current_entry_index = batch_state.current_entry_index or 1
    local total_entries = batch_state.total_entries or 1
    local current_entry_title = batch_state.current_entry_title or _("Current Entry")

    -- Context-specific dialog configuration
    local dialog_config = {}

    if context == "during_entry_images" then
        -- User cancelled during image download for a specific entry
        local title = total_entries == 1
                and T(_("Image download was cancelled for:\n%1\n\nWhat would you like to do?"), current_entry_title)
            or T(
                _("Image download was cancelled for entry %1/%2:\n%3\n\nWhat would you like to do?"),
                current_entry_index,
                total_entries,
                current_entry_title
            )

        local buttons = {
            {
                text = _("Cancel entry creation"),
                choice = "cancel_current_entry",
            },
            {
                text = _("Cancel all entries creation"),
                choice = "cancel_all_entries",
            },
            {
                text = _("Continue without images"),
                choice = "skip_images_current",
            },
            {
                text = _("Resume downloading"),
                choice = "resume_downloading",
            },
        }

        -- Add stateful image option based on current batch state
        if skip_images_for_all then
            -- User previously chose to skip images for all, now offer to include them
            table.insert(buttons, 3, {
                text = _("Include images for all entries"),
                choice = "include_images_all",
            })
        else
            -- User hasn't disabled images globally, offer to skip for all remaining
            table.insert(buttons, 3, {
                text = _("Skip images for all entries"),
                choice = "skip_images_all",
            })
        end

        dialog_config = {
            title = title,
            buttons = buttons,
        }
    else -- "during_batch"
        -- User cancelled during batch progress (between entries)
        local title = total_entries == 1 and T(_("Batch download was cancelled.\n\nWhat would you like to do?"))
            or T(
                _("Batch download was cancelled.\nProgress: %1/%2 entries completed.\n\nWhat would you like to do?"),
                current_entry_index - 1,
                total_entries
            )

        local buttons = {
            {
                text = _("Cancel all entries creation"),
                choice = "cancel_all_entries",
            },
            {
                text = _("Resume downloading"),
                choice = "resume_downloading",
            },
        }

        -- Add stateful image option for remaining entries
        if skip_images_for_all then
            table.insert(buttons, 2, {
                text = _("Include images for remaining entries"),
                choice = "include_images_all",
            })
        else
            table.insert(buttons, 2, {
                text = _("Skip images for remaining entries"),
                choice = "skip_images_all",
            })
        end

        dialog_config = {
            title = title,
            buttons = buttons,
        }
    end

    -- Build button grid for ButtonDialog (2 buttons per row for better layout)
    local dialog_buttons = {}

    -- Split buttons into rows of 2 for grid layout
    for i = 1, #dialog_config.buttons, 2 do
        local row = {}

        -- Add first button of the row
        table.insert(row, {
            text = dialog_config.buttons[i].text,
            callback = function()
                user_choice = dialog_config.buttons[i].choice
                UIManager:close(choice_dialog)
            end,
        })

        -- Add second button if it exists
        if dialog_config.buttons[i + 1] then
            table.insert(row, {
                text = dialog_config.buttons[i + 1].text,
                callback = function()
                    user_choice = dialog_config.buttons[i + 1].choice
                    UIManager:close(choice_dialog)
                end,
            })
        end

        table.insert(dialog_buttons, row)
    end

    -- Create dialog with context-specific configuration
    choice_dialog = ButtonDialog:new({
        title = dialog_config.title,
        title_align = "center",
        dismissable = false,
        buttons = dialog_buttons,
    })

    UIManager:show(choice_dialog)

    -- Use proper modal dialog pattern
    repeat
        UIManager:handleInput()
    until user_choice ~= nil

    return user_choice
end

---Open the Miniflux folder in file manager
---@return nil
function EntryEntity.openMinifluxFolder()
    local download_dir = EntryEntity.getDownloadDir()

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(download_dir)
    else
        FileManager:showFiles(download_dir)
    end
end

---Get all locally downloaded entries by scanning the miniflux directory
---@return table[] Array of entry metadata objects (same format as API entries)
function EntryEntity.getLocalEntries()
    local entries = {}
    local miniflux_dir = EntryEntity.getDownloadDir()

    -- Check if miniflux directory exists
    if not lfs.attributes(miniflux_dir, "mode") then
        return entries -- Return empty array if directory doesn't exist
    end

    -- Scan directory for entry folders
    for item in lfs.dir(miniflux_dir) do
        -- Skip . and .. entries, only process numeric folders (entry IDs)
        if item:match("^%d+$") then
            local entry_id = tonumber(item)

            -- Check if entry.html exists in this folder
            local html_file = EntryEntity.getEntryHtmlPath(entry_id)
            if lfs.attributes(html_file, "mode") == "file" then
                -- Load metadata for this entry
                local metadata = EntryEntity.loadMetadata(entry_id)
                if metadata then
                    table.insert(entries, metadata)
                else
                end
            end
        end
    end

    -- Sort entries by published_at descending (newest first)
    -- Use empty string as fallback for missing published_at to ensure consistent sorting
    table.sort(entries, function(a, b)
        local a_date = a.published_at or ""
        local b_date = b.published_at or ""
        return a_date > b_date
    end)

    return entries
end

---Get lightweight local entries metadata optimized for navigation only
---Loads minimal data (id, published_at, title) for fast navigation context
---@param opts {settings?: MinifluxSettings} Options containing user settings for order and direction
---@return table[] Array of minimal entry metadata for navigation
function EntryEntity.getLocalEntriesForNavigation(opts)
    local entries = {}
    local miniflux_dir = EntryEntity.getDownloadDir()

    -- Check if miniflux directory exists
    if not lfs.attributes(miniflux_dir, "mode") then
        return entries -- Return empty array if directory doesn't exist
    end

    local DocSettings = require("docsettings")

    -- Scan directory for entry folders
    for item in lfs.dir(miniflux_dir) do
        -- Skip . and .. entries, only process numeric folders (entry IDs)
        if item:match("^%d+$") then
            local entry_id = tonumber(item)
            local html_file = EntryEntity.getEntryHtmlPath(entry_id)
            
            if lfs.attributes(html_file, "mode") == "file" then
                if DocSettings:hasSidecarFile(html_file) then
                    local doc_settings = DocSettings:open(html_file)
                    
                    -- Load ONLY minimal data needed for navigation (5x less memory)
                    local nav_entry = {
                        id = entry_id,
                        published_at = doc_settings:readSetting("miniflux_published_at"),
                        title = doc_settings:readSetting("miniflux_title")
                    }
                    
                    table.insert(entries, nav_entry)
                end
            end
        end
    end

    -- Extract sort criteria from settings and apply sorting
    local sort_opts = nil
    if opts and opts.settings then
        sort_opts = {
            order = opts.settings.order,
            direction = opts.settings.direction
        }
    end
    
    -- Sort entries in-place and return sorted array
    return EntryEntity.sortEntries(entries, sort_opts)
end

---Sort entries array in-place for optimal performance
---@param entries table[] Array of entry metadata to sort (mutated in-place)
---@param opts {order?: string, direction?: string}|nil Sort options with defaults
---@return table[] The same array reference, now sorted (for chaining convenience)
local function sortEntries(entries, opts)
    if not entries or #entries == 0 then
        return entries
    end
    
    -- Apply defaults for sort criteria
    local order = (opts and opts.order) or "published_at"
    local direction = (opts and opts.direction) or "desc"

    table.sort(entries, function(a, b)
        local a_val, b_val

        -- Extract comparison values based on order setting
        if order == "published_at" then
            a_val = a.published_at or ""
            b_val = b.published_at or ""
        elseif order == "id" then
            a_val = a.id or 0
            b_val = b.id or 0
        elseif order == "title" then
            a_val = (a.title or ""):lower()  -- Case-insensitive title sort
            b_val = (b.title or ""):lower()
        else
            -- Default to published_at for unknown order values
            a_val = a.published_at or ""
            b_val = b.published_at or ""
        end

        -- Apply direction
        if direction == "asc" then
            return a_val < b_val
        else
            return a_val > b_val
        end
    end)
    
    return entries  -- Return same array reference for chaining
end

-- Make sortEntries available as module function
EntryEntity.sortEntries = sortEntries

return EntryEntity
