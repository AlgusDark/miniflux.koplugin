--[[--
Entry Downloader Service

Handles the downloading and local creation of RSS entries with cancellation support.
Uses Trapper for progress tracking and user cancellation.

Option B Improvements:
- Unified cancellation handling with consistent cleanup logic
- Simple phase tracking for better debugging and context-aware dialogs
- Standardized return types across all phase functions
- Preserves all existing Trapper functionality and coroutine flow

@module koplugin.miniflux.services.entry_downloader
--]]

local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local UIManager = require("ui/uimanager")
local FFIUtil = require("ffi/util")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import consolidated dependencies
local EntryUtils = require("utils/entry_utils")
local Images = require("utils/images")
local Trapper = require("ui/trapper")
local HtmlUtils = require("utils/html_utils")
local Files = require("utils/files")
local Notification = require("utils/notification")

-- =============================================================================
-- OPTIMIZATION: MODULE-LEVEL TEMPLATE HELPERS
-- =============================================================================

-- Generate progress message for image downloads (avoids template creation in hot loop)
local function createImageProgressMessage(title, current, total)
    return T(_("Downloading:\n%1\n\nDownloading %2/%3 images"),
        title, current, total)
end

-- =============================================================================
-- PHASE TRACKING AND CANCELLATION HANDLING
-- =============================================================================

-- Download phases for better state tracking and cancellation handling
local PHASES = {
    IDLE = "idle",
    PREPARING = "preparing",
    DOWNLOADING = "downloading",
    PROCESSING = "processing",
    COMPLETING = "completing"
}

-- Standardized phase results for consistent return handling
local PHASE_RESULTS = {
    SUCCESS = "success",
    CANCELLED = "cancelled",
    SKIP_IMAGES = "skip_images",
    ERROR = "error"
}

-- Current phase tracking (module-level for debugging visibility)
local current_phase = PHASES.IDLE

---Unified cancellation handler for consistent cleanup and user choice handling
---@param go_on boolean Result from Trapper:info() - true means continue, false means user cancelled
---@param context table Download context with paths for cleanup
---@return string PHASE_RESULTS value indicating how to proceed
local function handleCancellation(go_on, context)
    if go_on then
        return PHASE_RESULTS.SUCCESS
    end

    -- Phase-specific cancellation dialog
    local dialog_phase = current_phase == PHASES.DOWNLOADING and "during_images" or "after_images"
    local user_choice = EntryUtils.showCancellationDialog(dialog_phase)

    if user_choice == "cancel_entry" then
        -- Unified cleanup logic - no more duplication
        Images.cleanupTempFiles(context.entry_dir)
        FFIUtil.purgeDir(context.entry_dir)
        current_phase = PHASES.IDLE
        return PHASE_RESULTS.CANCELLED
    elseif user_choice == "continue_without_images" and current_phase == PHASES.DOWNLOADING then
        -- Skip remaining images and proceed to processing
        current_phase = PHASES.PROCESSING
        return PHASE_RESULTS.SKIP_IMAGES
    else
        -- Resume current phase (continue_creation or resume_downloading)
        return PHASE_RESULTS.SUCCESS
    end
end

-- =============================================================================
-- LOCAL HELPER FUNCTIONS (defined first for Lua function ordering)
-- =============================================================================

---Check if entry is already downloaded and open it if so
---@param entry_data table Entry data from API
---@param browser MinifluxBrowser|nil Browser instance to close
---@return boolean success True if already downloaded and opened
local function handleExistingEntry(entry_data, browser)
    if EntryUtils.isEntryDownloaded(entry_data.id) then
        local html_file = EntryUtils.getEntryHtmlPath(entry_data.id)
        EntryUtils.openEntry(html_file, {
            before_open = function()
                if browser then
                    browser:close()
                end
            end
        })
        return true
    end
    return false
end

---Prepare download context and create entry directory
---@param entry_data table Entry data from API
---@return table context Download context with paths and title
local function prepareDownload(entry_data)
    local title = entry_data.title or _("Untitled Entry")
    local entry_dir = EntryUtils.getEntryDirectory(entry_data.id)
    local html_file = EntryUtils.getEntryHtmlPath(entry_data.id)

    -- Create entry directory
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end

    return {
        title = title,
        entry_dir = entry_dir,
        html_file = html_file,
    }
end

---Discover images in entry content
---@param entry_data table Entry data from API
---@return table images, table seen_images, string content, table|nil base_url
local function discoverImages(entry_data)
    local content = entry_data.content or entry_data.summary or ""
    local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
    local images, seen_images = Images.discoverImages(content, base_url)

    -- No separate image discovery message - combined with preparation phase

    return images, seen_images, content, base_url
end

---Download images with progress tracking and cancellation support
---@param images table Array of image info
---@param context table Download context
---@param settings table Settings instance
---@return string PHASE_RESULTS value indicating completion status
local function downloadImagesWithProgress(images, context, settings)
    if not settings.include_images or #images == 0 then
        return PHASE_RESULTS.SUCCESS
    end

    local time_prev = time.now()
    local total_images = #images -- Cache array length to avoid repeated calculation

    for i, img in ipairs(images) do
        -- Performance optimization for eink devices downloading many images:
        -- 1. Throttle cancellation checks to every 1000ms to avoid UI sluggishness
        -- 2. Use fast_refresh (3rd parameter = true) to update progress without
        --    full UI repaints between cancellation checks
        -- This pattern is proven in newsdownloader.koplugin for RSS feeds with 30+ images
        local go_on
        if time.to_ms(time.since(time_prev)) > 1000 then
            time_prev = time.now()
            go_on = Trapper:info(createImageProgressMessage(context.title, i, total_images))

            -- Handle cancellation using unified handler
            local cancellation_result = handleCancellation(go_on, context)
            if cancellation_result == PHASE_RESULTS.CANCELLED then
                return PHASE_RESULTS.CANCELLED
            elseif cancellation_result == PHASE_RESULTS.SKIP_IMAGES then
                -- Stop downloading but continue with entry creation
                break
            end
            -- SUCCESS: continue downloading
        else
            -- Fast refresh without cancellation check - updates UI without full repaint (eink optimization)
            Trapper:info(createImageProgressMessage(context.title, i, total_images), true, true)
        end

        -- Download with error tracking
        local success = Images.downloadImage({
            url = img.src,
            entry_dir = context.entry_dir,
            filename = img.filename
        })

        img.downloaded = success
        if not success then
            -- Track error reason for better user feedback
            img.error_reason = "network_or_invalid_url"
        end

        -- Yield control to allow UI updates between downloads
        UIManager:nextTick(function() end)
    end

    return PHASE_RESULTS.SUCCESS
end



---Analyze download results and return summary
---@param images table Array of image info with downloaded flags
---@return table Summary with success_count and failed_count
local function analyzeDownloadResults(images)
    local success_count = 0
    local failed_count = 0

    for _, img in ipairs(images) do
        if img.downloaded then
            success_count = success_count + 1
        else
            failed_count = failed_count + 1
            local error_type = img.error_reason or "unknown_error"
        end
    end

    return {
        success_count = success_count,
        failed_count = failed_count,
        total_count = #images,
        has_errors = failed_count > 0
    }
end

---Process and generate HTML content
---@param entry_data table Entry data from API
---@param context table Download context
---@param content string Entry content
---@param seen_images table Seen images map
---@param base_url table|nil Parsed base URL
---@param settings table Settings instance
---@return string PHASE_RESULTS value indicating completion status
local function generateHtmlContent(entry_data, context, content, seen_images, base_url, settings)
    -- Phase 4: Processing content (silent HTML generation and file operations)
    local go_on = Trapper:info(T(_("Downloading:\n%1\n\nProcessing content..."), context.title))

    local cancellation_result = handleCancellation(go_on, context)
    if cancellation_result == PHASE_RESULTS.CANCELLED then
        return PHASE_RESULTS.CANCELLED
    end

    -- Process and clean content
    local processed_content = Images.processHtmlImages(content, seen_images, settings.include_images, base_url)
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    -- Create and save HTML document
    local html_content = HtmlUtils.createHtmlDocument(entry_data, processed_content)
    local file_success = Files.writeFile(context.html_file, html_content)
    if not file_success then
        Notification:error(_("Failed to save HTML file"))
        return PHASE_RESULTS.ERROR
    end

    return PHASE_RESULTS.SUCCESS
end

---Save entry metadata
---@param entry_data table Entry data from API
---@param images_count number Count of successfully downloaded images
---@param settings table Settings instance
---@return string PHASE_RESULTS value indicating completion status
local function saveMetadata(entry_data, images_count, settings)
    -- Phase 6: Creating metadata (silent operation)
    -- Save metadata using DocSettings
    local metadata_saved = EntryUtils.saveMetadata({
        entry_data = entry_data,
        include_images = settings.include_images,
        images_count = images_count,
    })

    if not metadata_saved then
        Notification:error(_("Failed to save entry metadata"))
        return PHASE_RESULTS.ERROR
    end

    return PHASE_RESULTS.SUCCESS
end

---Open the completed entry
---@param context table Download context
---@param images table Images array
---@param settings table Settings instance
---@param browser MinifluxBrowser|nil Browser instance to close
---@param download_summary table Pre-computed download analysis results
---@return string PHASE_RESULTS value indicating completion status
local function openCompletedEntry(context, images, settings, browser, download_summary)
    -- Show completion message with image summary
    local summary_lines = {}

    if #images > 0 then
        if settings.include_images then
            -- Images were enabled: use pre-computed download analysis
            -- Only show non-zero counts
            if download_summary.success_count > 0 then
                table.insert(summary_lines, T(_("%1 images downloaded"), download_summary.success_count))
            end
            if download_summary.failed_count > 0 then
                table.insert(summary_lines, T(_("%1 images skipped"), download_summary.failed_count))
            end
        else
            -- Images were disabled: all discovered images are skipped
            table.insert(summary_lines, T(_("%1 images skipped"), #images))
        end
    end

    local summary = #summary_lines > 0 and table.concat(summary_lines, "\n") or ""
    local message = summary ~= "" and T(_("Download completed!\n\n%1"), summary) or _("Download completed!")

    Trapper:info(message)

    -- Open entry with browser cleanup
    EntryUtils.openEntry(context.html_file, {
        before_open = function()
            if browser then
                browser:close()
            end
        end
    })
    return PHASE_RESULTS.SUCCESS
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local EntryDownloader = {}

---Start a cancellable entry download with progress tracking (uses Trapper for UI progress)
---@param deps {entry_data: table, settings: table, browser?: table}
---@return boolean success
function EntryDownloader.startCancellableDownload(deps)
    local entry_data = deps.entry_data
    local settings = deps.settings
    local browser = deps.browser

    -- Wrap entire download operation in Trapper for cancellation support
    return Trapper:wrap(function()
        -- Initialize phase tracking
        current_phase = PHASES.IDLE

        -- Check if already downloaded
        if handleExistingEntry(entry_data, browser) then
            return true
        end

        -- Phase 1: Preparation (combines setup + image discovery)
        current_phase = PHASES.PREPARING
        local context = prepareDownload(entry_data)
        local go_on = Trapper:info(T(_("Downloading:\n%1\n\nPreparing..."), context.title))

        local cancellation_result = handleCancellation(go_on, context)
        if cancellation_result == PHASE_RESULTS.CANCELLED then
            return false
        end

        local images, seen_images, content, base_url = discoverImages(entry_data)
        if not images then
            return false -- Discovery failed
        end

        -- Phase 2: Download images if enabled
        current_phase = PHASES.DOWNLOADING
        local download_result = downloadImagesWithProgress(images, context, settings)
        if download_result == PHASE_RESULTS.CANCELLED then
            return false -- Entry was deleted, exit completely
        end

        -- Analyze download results once for all subsequent operations
        local download_summary = analyzeDownloadResults(images)

        -- Check for network errors and show simple summary if needed
        if download_summary.has_errors then
            local error_msg = T(
                _("Some images failed to download (%1/%2 successful)\nContinuing with available images..."),
                download_summary.success_count, download_summary.total_count)
            Trapper:info(error_msg)
        end

        -- Phase 3: Generate HTML content and save metadata
        current_phase = PHASES.PROCESSING
        local content_result = generateHtmlContent(entry_data, context, content, seen_images, base_url, settings)
        if content_result == PHASE_RESULTS.CANCELLED or content_result == PHASE_RESULTS.ERROR then
            return false
        end

        -- Save metadata with actual download counts (reusing analysis)
        local metadata_result = saveMetadata(entry_data, download_summary.success_count, settings)
        if metadata_result == PHASE_RESULTS.CANCELLED or metadata_result == PHASE_RESULTS.ERROR then
            return false
        end

        -- Phase 4: Show completion and open entry
        current_phase = PHASES.COMPLETING
        local completion_result = openCompletedEntry(context, images, settings, browser, download_summary)

        -- Reset phase to idle on completion
        current_phase = PHASES.IDLE
        return completion_result == PHASE_RESULTS.SUCCESS
    end) or false
end

return EntryDownloader
