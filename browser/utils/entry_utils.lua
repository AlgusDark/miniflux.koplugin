--[[--
Entry Utilities for Miniflux Browser

This utility module coordinates entry downloading, processing, and integration
with KOReader. It delegates specialized tasks to focused utility modules.

@module miniflux.browser.utils.entry_utils
--]] --

---@class EntryMetadata
---@field id number Entry ID
---@field title string Entry title
---@field url? string Entry URL
---@field status string Entry status ("read" or "unread")
---@field starred boolean Whether entry is starred/bookmarked
---@field published_at? string Publication timestamp
---@field images_included boolean Whether images were downloaded
---@field images_count number Number of images processed

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local _ = require("gettext")
local T = require("ffi/util").template

-- Move frequently used requires to module level for performance
local time = require("ui/time")
-- BrowserUtils functionality moved inline to avoid dependency on deleted file
local ReaderUI = require("apps/reader/readerui")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
-- Removed NavigationUtils import to break circular dependency - functions moved inline

-- Additional imports for navigation functionality (moved from NavigationUtils)
local MinifluxAPI = require("api/api_client")
local NavigationContext = require("browser/utils/navigation_context")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")

-- Import the new specialized utility modules
local ProgressUtils = require("browser/utils/progress_utils")
local ImageUtils = require("browser/utils/image_utils")
local HtmlUtils = require("browser/utils/html_utils")

-- Load current entry metadata (moved from NavigationUtils)
local function loadCurrentEntryMetadata(entry_info)
    if not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    local entry_dir = entry_info.file_path:match("(.*)/entry%.html$")
    if not entry_dir then
        return nil
    end

    local metadata_file = entry_dir .. "/metadata.lua"
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return nil
    end

    local success, metadata = pcall(dofile, metadata_file)
    if success and metadata then
        return metadata
    end

    return nil
end

---@class EntryUtils
---@field settings MinifluxSettings The settings instance
---@field _current_miniflux_entry table|nil Current entry being processed
---@field _current_end_dialog table|nil Current end of entry dialog
local EntryUtils = {}
EntryUtils.__index = EntryUtils

---Create a new EntryUtils instance
---@param settings MinifluxSettings Settings instance
---@return EntryUtils
function EntryUtils:new(settings)
    local instance = {
        settings = settings,
        _current_miniflux_entry = nil,
        _current_end_dialog = nil,
    }
    setmetatable(instance, self)
    return instance
end

---Show an entry by downloading and opening it
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, browser?: table}
function EntryUtils:showEntry(params)
    local entry = params.entry
    local api = params.api
    local download_dir = params.download_dir
    local browser = params.browser

    if not download_dir then
        UIManager:show(InfoMessage:new {
            text = _("Download directory not configured"),
            timeout = 3,
        })
        return
    end

    -- Direct download without Trapper wrapper since we have our own progress system
    self:downloadEntry({
        entry = entry,
        api = api,
        download_dir = download_dir,
        browser = browser,
    })
end

---Download and process an entry with images
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, browser?: table}
function EntryUtils:downloadEntry(params)
    local entry = params.entry
    local download_dir = params.download_dir
    local browser = params.browser

    local entry_title = entry.title or _("Untitled Entry")
    local entry_id = tostring(entry.id)

    -- Create progress tracker using new ProgressUtils
    local progress = ProgressUtils.createEntryProgress(entry_title)

    -- Create entry directory
    local entry_dir = download_dir .. entry_id .. "/"
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end

    local html_file = entry_dir .. "entry.html"
    local metadata_file = entry_dir .. "metadata.lua"

    -- Check if already downloaded
    if lfs.attributes(html_file, "mode") == "file" then
        progress:close()

        -- Close browser FIRST even for already downloaded entries (OPDS pattern)
        if browser and browser.closeAll then
            browser:closeAll()
        end

        self:openEntryFile(html_file)
        return
    end

    progress:update(_("Preparing download…"))

    -- Get entry content
    local content = entry.content or entry.summary or ""
    if content == "" then
        progress:close()
        UIManager:show(InfoMessage:new {
            text = _("No content available for this entry"),
            timeout = 3,
        })
        return
    end

    -- Check if images should be included
    local include_images = self.settings.include_images

    progress:update(_("Scanning for images…"))

    -- Discover images using ImageUtils
    local base_url = entry.url and socket_url.parse(entry.url) or nil
    local images, seen_images = ImageUtils.discoverImages(content, base_url)

    -- Configure progress tracker with image information
    progress:setImageConfig(include_images, #images)

    -- Show what we found and what we'll do
    if include_images and #images > 0 then
        progress:update(T(_("Found %1 images - Starting download…"), #images))
    elseif include_images and #images == 0 then
        progress:update(_("No images found - Processing content…"))
    else
        progress:update(T(_("Found %1 images - Skipping (disabled in settings)"), #images))
    end

    -- Download images if enabled with proper progress reporting
    if include_images and #images > 0 then
        local time_prev = time.now()

        for i, img in ipairs(images) do
            -- Update progress for each image
            progress:update(
                T(_("Downloading image %1 of %2…"), i, #images),
                { current = i - 1, total = #images },
                true -- Allow cancellation during image downloads
            )

            -- Process can be interrupted every second between image downloads
            local go_on = true
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()
                -- Update progress with cancellation option
                go_on = progress:update(
                    T(_("Downloading image %1 of %2…"), i, #images),
                    { current = i - 1, total = #images },
                    true
                )
                if not go_on then
                    break
                end
            end

            local success = ImageUtils.downloadImage(img.src, entry_dir, img.filename)
            img.downloaded = success

            if success then
                progress:incrementDownloadedImages()
            end
        end

        -- Final image download update
        progress:update(
            _("Image downloads completed"),
            { current = progress.downloaded_images, total = #images }
        )
    end

    progress:update(_("Processing content…"))

    -- Process HTML content using ImageUtils
    local processed_content = ImageUtils.processHtmlImages(content, seen_images, include_images, base_url)

    -- Clean HTML content using HtmlUtils
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    progress:update(_("Creating HTML file…"))

    -- Create full HTML document using HtmlUtils
    local html_content = HtmlUtils.createHtmlDocument(entry, processed_content)

    -- Save HTML file
    local file = io.open(html_file, "w")
    if file then
        file:write(html_content)
        file:close()
    else
        progress:close()
        UIManager:show(InfoMessage:new {
            text = _("Failed to save HTML file"),
            timeout = 3,
        })
        return
    end

    progress:update(_("Creating metadata…"))

    -- Create metadata
    local metadata = self:createEntryMetadata({
        entry = entry,
        include_images = include_images,
        images = images
    })

    -- Save metadata file
    local metadata_content = "return " .. self:tableToString(metadata)
    file = io.open(metadata_file, "w")
    if file then
        file:write(metadata_content)
        file:close()
    end

    -- Close progress immediately and show final message
    progress:close()

    -- Show completion summary using ImageUtils
    local image_summary = ImageUtils.createDownloadSummary(include_images, images)
    UIManager:show(InfoMessage:new {
        text = _("Download completed!") .. "\n\n" .. image_summary,
        timeout = 1,
    })

    -- Close browser FIRST, then immediately open the entry (OPDS pattern - no delays)
    if browser and browser.closeAll then
        browser:closeAll()
    end

    -- Open entry immediately after browser close
    self:openEntryFile(html_file)
end

---Create entry metadata
---@param params {entry: MinifluxEntry, include_images: boolean, images: ImageInfo[]}
---@return EntryMetadata
function EntryUtils:createEntryMetadata(params)
    local entry = params.entry
    local include_images = params.include_images
    local images = params.images

    -- Essential metadata for entry display and status tracking
    local metadata = {
        -- Entry identification
        id = entry.id,
        title = entry.title or _("Untitled Entry"),
        url = entry.url,

        -- Entry status and properties
        status = entry.status,
        starred = entry.starred,
        published_at = entry.published_at,

        -- Image processing results (minimal info)
        images_included = include_images,
        images_count = include_images and #images or 0
    }

    -- Note: Navigation context is now handled globally in memory,
    -- not stored in metadata files anymore

    return metadata
end

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@return nil
function EntryUtils:openEntryFile(html_file)
    -- Close any existing EndOfBook dialog first (prevent stacking like OPDS pattern)
    self:closeEndOfEntryDialog()

    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil

    if is_miniflux_entry then
        -- Extract entry ID from path for later use
        local entry_id = html_file:match("/miniflux/(%d+)/")

        if entry_id then
            -- Update global navigation context with this entry
            -- Note: We don't have browsing context when opening existing files,
            -- so navigation will be global unless the user came from a browser session
            local NavigationContext = require("browser/utils/navigation_context")
            local entry_id_num = tonumber(entry_id)
            if entry_id_num then
                if not NavigationContext.hasValidContext() then
                    -- Set global context if no context exists
                    NavigationContext.setGlobalContext(entry_id_num)
                else
                    -- Update current entry in existing context
                    NavigationContext.updateCurrentEntry(entry_id_num)
                end
            end
        end

        -- Store the entry info for the EndOfBook event handler
        self._current_miniflux_entry = {
            file_path = html_file,
            entry_id = entry_id
        }
    end

    -- Open the file - EndOfBook event handler will detect miniflux entries automatically
    ReaderUI:showReader(html_file)
end

---Show end of entry dialog with navigation options
---@param params? table Optional parameters (kept for backward compatibility)
---@return nil
function EntryUtils:showEndOfEntryDialog(params)
    local current_entry = self._current_miniflux_entry
    if not current_entry then
        return
    end

    -- Close any existing EndOfBook dialog first (prevent stacking)
    self:closeEndOfEntryDialog()

    -- Load entry metadata to check current status with error handling
    local metadata = nil
    local metadata_success = pcall(function()
        metadata = loadCurrentEntryMetadata(current_entry)
    end)

    if not metadata_success then
        -- If metadata loading fails, assume unread status
        metadata = { status = "unread" }
    end

    local entry_status = metadata and metadata.status or "unread"

    -- Determine mark button text and action based on current status
    local mark_button_text, mark_callback
    if entry_status == "read" then
        mark_button_text = _("✓ Mark as unread")
        mark_callback = function()
            self:markEntryAsUnread(current_entry)
        end
    else
        mark_button_text = _("✓ Mark as read")
        mark_callback = function()
            self:markEntryAsRead(current_entry)
        end
    end

    -- Create dialog and store reference for later cleanup with error handling
    local dialog_success = pcall(function()
        self._current_end_dialog = ButtonDialogTitle:new {
            title = _("You've reached the end of the entry."),
            title_align = "center",
            buttons = {
                {
                    {
                        text = _("← Previous"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                self:navigateToPreviousEntry(current_entry)
                            end)
                        end,
                    },
                    {
                        text = _("Next →"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                self:navigateToNextEntry(current_entry)
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⚠ Delete local entry"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                self:deleteLocalEntry(current_entry)
                            end)
                        end,
                    },
                    {
                        text = mark_button_text,
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                mark_callback()
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⌂ Miniflux folder"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                            pcall(function()
                                self:openMinifluxFolder(current_entry)
                            end)
                        end,
                    },
                    {
                        text = _("Cancel"),
                        callback = function()
                            self:closeEndOfEntryDialog()
                        end,
                    },
                },
            },
        }

        UIManager:show(self._current_end_dialog)
    end)

    if not dialog_success then
        -- If dialog creation fails, show a simple error message
        UIManager:show(InfoMessage:new {
            text = _("Failed to create end of entry dialog"),
            timeout = 3,
        })
    end
end

---Close any existing EndOfEntry dialog
---@return nil
function EntryUtils:closeEndOfEntryDialog()
    if self._current_end_dialog then
        UIManager:close(self._current_end_dialog)
        self._current_end_dialog = nil
    end
end

-- =============================================================================
-- NAVIGATION FUNCTIONS (moved from NavigationUtils to break circular dependency)
-- =============================================================================

-- Pure-Lua ISO-8601 → Unix timestamp (UTC)
-- Handles "YYYY-MM-DDTHH:MM:SS±HH:MM"
local function iso8601_to_unix(s)
    local Y, M, D, h, m, sec, sign, tzh, tzm = s:match(
        "(%d+)%-(%d+)%-(%d+)T" ..
        "(%d+):(%d+):(%d+)" ..
        "([%+%-])(%d%d):(%d%d)$"
    )
    if not Y then
        error("Bad ISO-8601 string: " .. tostring(s))
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
    local doe = yoe * 365 + math.floor(yoe / 4)
        - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468

    local utc_secs = days * 86400 + h * 3600 + m * 60 + sec

    local offs = tzh * 3600 + tzm * 60
    if sign == "+" then
        utc_secs = utc_secs - offs
    else
        utc_secs = utc_secs + offs
    end

    return utc_secs
end

-- Get API options based on settings
---@return table API options for entries
function EntryUtils:getNavigationApiOptions()
    local options = {
        limit = self.settings.limit,
        order = self.settings.order,
        direction = self.settings.direction,
    }

    local hide_read_entries = self.settings.hide_read_entries
    if hide_read_entries then
        options.status = { "unread" }
    else
        options.status = { "unread", "read" }
    end

    return options
end

---Navigate to the previous entry
---@param entry_info table Current entry information
---@return nil
function EntryUtils:navigateToPreviousEntry(entry_info)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: API not available"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Finding previous entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local context_success, has_context = pcall(function()
        return NavigationContext.hasValidContext()
    end)

    if not context_success or not has_context then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: no browsing context available"),
            timeout = 3,
        })
        return
    end

    local metadata = loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end

    local published_unix
    local ok = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end

    local base_options = self:getNavigationApiOptions()
    local options_success, options = pcall(function()
        return NavigationContext.getContextAwareOptions(base_options)
    end)

    if not options_success or not options then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: failed to get context options"),
            timeout = 3,
        })
        return
    end

    options.direction = "asc"
    options.published_after = published_unix
    options.limit = 1
    options.order = self.settings.order

    local success, result = api.entries:getEntries(options)
    UIManager:close(loading_info)

    if success and result and result.entries and #result.entries > 0 then
        local prev_entry = result.entries[1]
        local prev_entry_id = tostring(prev_entry.id)

        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local prev_entry_dir = miniflux_dir .. "/miniflux/" .. prev_entry_id .. "/"
            local prev_html_file = prev_entry_dir .. "entry.html"

            if lfs.attributes(prev_html_file, "mode") == "file" then
                self:openEntryFile(prev_html_file)
                return
            end
        end

        self:downloadAndShowEntry(prev_entry)
    else
        local current_context_success, current_context = pcall(function()
            return NavigationContext.getCurrentContext()
        end)

        if current_context_success and current_context and current_context.type and current_context.type ~= "global" then
            local global_options = self:getNavigationApiOptions()
            global_options.direction = "asc"
            global_options.published_after = published_unix
            global_options.limit = 1
            global_options.order = self.settings.order

            success, result = api.entries:getEntries(global_options)

            if success and result and result.entries and #result.entries > 0 then
                local prev_entry = result.entries[1]
                self:downloadAndShowEntry(prev_entry)
                return
            end
        end

        UIManager:show(InfoMessage:new {
            text = _("No previous entry available"),
            timeout = 3,
        })
    end
end

---Navigate to the next entry
---@param entry_info table Current entry information
---@return nil
function EntryUtils:navigateToNextEntry(entry_info)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: API not available"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Finding next entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local context_success, has_context = pcall(function()
        return NavigationContext.hasValidContext()
    end)

    if not context_success or not has_context then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: no browsing context available"),
            timeout = 3,
        })
        return
    end

    local metadata = loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end

    local published_unix
    local ok = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end

    local base_options = self:getNavigationApiOptions()
    local options_success, options = pcall(function()
        return NavigationContext.getContextAwareOptions(base_options)
    end)

    if not options_success or not options then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: failed to get context options"),
            timeout = 3,
        })
        return
    end

    options.direction = "desc"
    options.published_before = published_unix
    options.limit = 1
    options.order = self.settings.order

    local success, result = api.entries:getEntries(options)
    UIManager:close(loading_info)

    if success and result and result.entries and #result.entries > 0 then
        local next_entry = result.entries[1]
        local next_entry_id = tostring(next_entry.id)

        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local next_entry_dir = miniflux_dir .. "/miniflux/" .. next_entry_id .. "/"
            local next_html_file = next_entry_dir .. "entry.html"

            if lfs.attributes(next_html_file, "mode") == "file" then
                self:openEntryFile(next_html_file)
                return
            end
        end

        self:downloadAndShowEntry(next_entry)
    else
        local current_context_success, current_context = pcall(function()
            return NavigationContext.getCurrentContext()
        end)

        if current_context_success and current_context and current_context.type and current_context.type ~= "global" then
            local global_options = self:getNavigationApiOptions()
            global_options.direction = "desc"
            global_options.published_before = published_unix
            global_options.limit = 1
            global_options.order = self.settings.order

            success, result = api.entries:getEntries(global_options)

            if success and result and result.entries and #result.entries > 0 then
                local next_entry = result.entries[1]
                self:downloadAndShowEntry(next_entry)
                return
            end
        end

        UIManager:show(InfoMessage:new {
            text = _("No next entry available"),
            timeout = 3,
        })
    end
end

---Download and show an entry
---@param entry MinifluxEntry Entry to download and show
---@return nil
function EntryUtils:downloadAndShowEntry(entry)
    if not entry or not entry.id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot download: invalid entry data"),
            timeout = 3,
        })
        return
    end

    local context_success = pcall(function()
        NavigationContext.updateCurrentEntry(entry.id)
    end)

    if not context_success then
        -- Continue without context update if it fails
    end

    local download_success = pcall(function()
        local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")

        local api = MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })

        self:downloadEntry({
            entry = entry,
            api = api,
            download_dir = download_dir
        })
    end)

    if not download_success then
        UIManager:show(InfoMessage:new {
            text = _("Failed to download and show entry"),
            timeout = 3,
        })
    end
end

---Mark an entry as read
---@param entry_info table Current entry information
---@return nil
function EntryUtils:markEntryAsRead(entry_info)
    local entry_id = entry_info.entry_id
    if not entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as read: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Marking entry as read..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as read: API not available"),
            timeout = 3,
        })
        return
    end

    local entry_id_num = tonumber(entry_id)
    if not entry_id_num then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as read: invalid entry ID format"),
            timeout = 3,
        })
        return
    end

    local success, result = api.entries:markAsRead(entry_id_num)
    UIManager:close(loading_info)

    if success then
        UIManager:show(InfoMessage:new {
            text = _("Entry marked as read"),
            timeout = 2,
        })

        pcall(function()
            self:updateLocalEntryStatus(entry_info, "read")
        end)

        UIManager:scheduleIn(0.5, function()
            pcall(function()
                self:deleteLocalEntry(entry_info)
            end)
        end)
    else
        UIManager:show(InfoMessage:new {
            text = _("Failed to mark entry as read: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Mark an entry as unread
---@param entry_info table Current entry information
---@return nil
function EntryUtils:markEntryAsUnread(entry_info)
    local entry_id = entry_info.entry_id
    if not entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as unread: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Marking entry as unread..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as unread: API not available"),
            timeout = 3,
        })
        return
    end

    local entry_id_num = tonumber(entry_id)
    if not entry_id_num then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot mark as unread: invalid entry ID format"),
            timeout = 3,
        })
        return
    end

    local success, result = api.entries:markAsUnread(entry_id_num)
    UIManager:close(loading_info)

    if success then
        UIManager:show(InfoMessage:new {
            text = _("Entry marked as unread"),
            timeout = 2,
        })

        pcall(function()
            self:updateLocalEntryStatus(entry_info, "unread")
        end)
    else
        UIManager:show(InfoMessage:new {
            text = _("Failed to mark entry as unread: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Update local entry metadata status
---@param entry_info table Current entry information
---@param new_status string New status to set
---@return boolean True if successfully updated
function EntryUtils:updateLocalEntryStatus(entry_info, new_status)
    local entry_id = entry_info.entry_id
    if not entry_id then
        return false
    end

    local success = pcall(function()
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if not miniflux_dir then
            return false
        end

        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
        local metadata_file = entry_dir .. "metadata.lua"

        if lfs.attributes(metadata_file, "mode") ~= "file" then
            return false
        end

        local metadata_success, metadata = pcall(dofile, metadata_file)
        if not metadata_success or not metadata then
            return false
        end

        metadata.status = new_status

        local metadata_content = "return " .. self:tableToString(metadata)

        local file = io.open(metadata_file, "w")
        if file then
            file:write(metadata_content)
            file:close()
            return true
        end

        return false
    end)

    return success or false
end

---Delete a local entry
---@param entry_info table Current entry information
---@return nil
function EntryUtils:deleteLocalEntry(entry_info)
    local entry_id = entry_info.entry_id
    if not entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot delete: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local delete_success = pcall(function()
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if not miniflux_dir then
            return false
        end

        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"

        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end

        FFIUtil.purgeDir(entry_dir)
        return true
    end)

    if delete_success then
        UIManager:show(InfoMessage:new {
            text = _("Local entry deleted successfully"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new {
            text = _("Failed to delete local entry"),
            timeout = 3,
        })
    end

    pcall(function()
        self:openMinifluxFolder(entry_info)
    end)
end

---Open the Miniflux folder in file manager
---@param entry_info table Current entry information
---@return nil
function EntryUtils:openMinifluxFolder(entry_info)
    local folder_success = pcall(function()
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if not miniflux_dir then
            return false
        end

        local full_miniflux_dir = miniflux_dir .. "/miniflux/"

        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end

        if FileManager.instance then
            FileManager.instance:reinit(full_miniflux_dir)
        else
            FileManager:showFiles(full_miniflux_dir)
        end

        return true
    end)

    if not folder_success then
        UIManager:show(InfoMessage:new {
            text = _("Failed to open Miniflux folder"),
            timeout = 3,
        })
    end
end

---Fetch and show entry by ID
---@param entry_id number Entry ID to fetch and show
---@return nil
function EntryUtils:fetchAndShowEntry(entry_id)
    if not entry_id or type(entry_id) ~= "number" then
        UIManager:show(InfoMessage:new {
            text = _("Cannot fetch: invalid entry ID"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Fetching entry from server..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local fetch_success = pcall(function()
        local api = MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })

        local success, result = api.entries:getEntry(entry_id)
        UIManager:close(loading_info)

        if success and result and type(result) == "table" and result.id then
            self:downloadAndShowEntry(result)
        else
            UIManager:show(InfoMessage:new {
                text = _("Failed to fetch entry: ") .. tostring(result),
                timeout = 5,
            })
        end
    end)

    if not fetch_success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Failed to fetch entry from server"),
            timeout = 3,
        })
    end
end

-- =============================================================================
-- UTILITY METHODS (moved from deleted BrowserUtils)
-- =============================================================================

---Convert table to Lua string representation
---@param tbl table Table to convert
---@param indent? number Current indentation level
---@return string Lua code representation of table
function EntryUtils:tableToString(tbl, indent)
    indent = indent or 0
    local result = {}
    local spaces = string.rep("  ", indent)

    table.insert(result, "{\n")
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
        local value
        if type(v) == "string" then
            value = string.format('"%s"', v:gsub('"', '\\"'))
        elseif type(v) == "table" then
            value = self:tableToString(v, indent + 1)
        else
            value = tostring(v)
        end
        table.insert(result, string.format("%s  [%s] = %s,\n", spaces, key, value))
    end
    table.insert(result, spaces .. "}")

    return table.concat(result)
end

return EntryUtils
