--[[--
Entry Workflow Service

Handles the complete workflow for downloading and opening RSS entries.
Uses Trapper for progress tracking and user interaction in a fire-and-forget pattern.
Orchestrates the entire process: download, file creation, and opening.

@module koplugin.miniflux.services.entry_workflow
--]]

local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local UIManager = require("ui/uimanager")
local FFIUtil = require("ffi/util")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import consolidated dependencies
local EntryEntity = require("entities/entry_entity")
local Images = require("utils/images")
local Trapper = require("ui/trapper")
local HtmlUtils = require("utils/html_utils")
local Files = require("utils/files")
local Notification = require("utils/notification")

-- =============================================================================
-- OPTIMIZATION: MODULE-LEVEL TEMPLATE HELPERS
-- =============================================================================

-- Generate progress message for image downloads (avoids template creation in hot loop)
local function createImageProgressMessage(opts)
    return T(_("Downloading:\n%1\n\nDownloading %2/%3 images"),
        opts.title, opts.current, opts.total)
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
    local user_choice = EntryEntity.showCancellationDialog(dialog_phase)

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
-- UI-DEPENDENT WORKFLOW FUNCTIONS
-- =============================================================================

---Download images with progress tracking and cancellation support
---@param opts table Options containing images, context, settings
---@return string PHASE_RESULTS value indicating completion status
local function downloadImagesWithProgress(opts)
    -- Extract parameters from opts
    local images = opts.images
    local context = opts.context
    local settings = opts.settings

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
            go_on = Trapper:info(createImageProgressMessage({
                title = context.title,
                current = i,
                total = total_images
            }))

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
            Trapper:info(createImageProgressMessage({
                title = context.title,
                current = i,
                total = total_images
            }), true, true)
        end

        -- Download with error tracking - delegate to generic function for single image
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

---Process and generate HTML content with progress UI
---@param config table Configuration containing entry_data, context, content, seen_images, base_url, settings
---@return string PHASE_RESULTS value indicating completion status
local function generateHtmlContent(config)
    -- Extract parameters from config
    local entry_data = config.entry_data
    local context = config.context
    local content = config.content
    local seen_images = config.seen_images
    local base_url = config.base_url
    local settings = config.settings

    -- Phase 4: Processing content (with progress UI)
    local go_on = Trapper:info(T(_("Downloading:\n%1\n\nProcessing content..."), context.title))

    local cancellation_result = handleCancellation(go_on, context)
    if cancellation_result == PHASE_RESULTS.CANCELLED then
        return PHASE_RESULTS.CANCELLED
    end

    -- Generate HTML using HtmlUtils
    local html_content, err = HtmlUtils.processEntryContent(content, {
        entry_data = entry_data,
        seen_images = seen_images,
        base_url = base_url,
        include_images = settings.include_images
    })

    if err or not html_content then
        Notification:error(_("Failed to process content: ") .. (err and err.message or "No content generated"))
        return PHASE_RESULTS.ERROR
    end

    -- Save HTML file directly
    local file_success = Files.writeFile(context.html_file, html_content)
    if not file_success then
        Notification:error(_("Failed to save HTML file"))
        return PHASE_RESULTS.ERROR
    end

    return PHASE_RESULTS.SUCCESS
end

---Show completion summary with progress UI
---@param config table Configuration containing images, settings, download_summary
---@return string PHASE_RESULTS value indicating completion status
local function showCompletionSummary(config)
    -- Extract parameters from config
    local images = config.images
    local settings = config.settings
    local download_summary = config.download_summary

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
    return PHASE_RESULTS.SUCCESS
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local EntryWorkflow = {}

---Execute complete entry workflow with progress tracking (fire-and-forget)
---Downloads entry, creates files, and opens in reader with full user interaction support
---@param deps {entry_data: table, settings: table, browser?: table}
function EntryWorkflow.execute(deps)
    local entry_data = deps.entry_data
    local settings = deps.settings
    local browser = deps.browser

    -- Execute complete workflow in Trapper for user interaction support
    Trapper:wrap(function()
        -- Initialize phase tracking
        current_phase = PHASES.IDLE

        -- Check if already downloaded
        if EntryEntity.isEntryDownloaded(entry_data.id) then
            local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)
            -- Use Files.openWithReader for clean file opening
            Files.openWithReader(html_file, {
                before_open = function()
                    if browser then
                        browser:close()
                    end
                end
            })
            return -- Completed - fire and forget
        end

        -- Phase 1: Preparation (combines setup + image discovery)
        current_phase = PHASES.PREPARING

        -- Prepare download context inline
        local title = entry_data.title or _("Untitled Entry")
        local entry_dir = EntryEntity.getEntryDirectory(entry_data.id)
        local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)

        -- Create entry directory
        local success, dir_err = Files.createDirectory(entry_dir)
        if dir_err then
            Notification:error(_("Failed to prepare download: ") .. dir_err.message)
            return -- Failed - fire and forget
        end

        local context = {
            title = title,
            entry_dir = entry_dir,
            html_file = html_file,
        }

        local go_on = Trapper:info(T(_("Downloading:\n%1\n\nPreparing..."), context.title or _("Unknown Entry")))

        local cancellation_result = handleCancellation(go_on, context)
        if cancellation_result == PHASE_RESULTS.CANCELLED then
            return -- User cancelled - fire and forget
        end

        -- Discover images inline
        local content = entry_data.content or entry_data.summary or ""
        local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
        local images, seen_images = Images.discoverImages(content, base_url)

        if not images then
            Notification:error(_("Failed to discover images"))
            return -- Discovery failed - fire and forget
        end

        -- Phase 2: Download images if enabled
        current_phase = PHASES.DOWNLOADING
        local download_result = downloadImagesWithProgress({
            images = images,
            context = context,
            settings = settings
        })
        if download_result == PHASE_RESULTS.CANCELLED then
            return -- User cancelled - fire and forget
        end

        -- Analyze download results inline
        local success_count = 0
        local failed_count = 0

        for _, img in ipairs(images) do
            if img.downloaded then
                success_count = success_count + 1
            else
                failed_count = failed_count + 1
            end
        end

        local download_summary = {
            success_count = success_count,
            failed_count = failed_count,
            total_count = #images,
            has_errors = failed_count > 0
        }

        -- Check for network errors and show simple summary if needed
        if download_summary.has_errors then
            local error_msg = T(
                _("Some images failed to download (%1/%2 successful)\nContinuing with available images..."),
                download_summary.success_count, download_summary.total_count)
            Trapper:info(error_msg)
        end

        -- Phase 3: Generate HTML content and save metadata
        current_phase = PHASES.PROCESSING
        local content_result = generateHtmlContent({
            entry_data = entry_data,
            context = context,
            content = content,
            seen_images = seen_images,
            base_url = base_url,
            settings = settings
        })
        if content_result == PHASE_RESULTS.CANCELLED or content_result == PHASE_RESULTS.ERROR then
            return -- Failed or cancelled - fire and forget
        end

        -- Save metadata directly using EntryEntity
        local metadata_result, metadata_err = EntryEntity.saveMetadata({
            entry_data = entry_data,
            images_count = download_summary.success_count,
            include_images = settings.include_images
        })
        if metadata_err then
            Notification:error(_("Failed to save metadata: ") .. metadata_err.message)
            return -- Failed - fire and forget
        end

        -- Phase 4: Show completion and open entry
        current_phase = PHASES.COMPLETING
        local completion_result = showCompletionSummary({
            images = images,
            settings = settings,
            download_summary = download_summary
        })

        -- Use Files.openWithReader for clean file opening
        Files.openWithReader(context.html_file, {
            before_open = function()
                if browser then
                    browser:close()
                end
            end
        })

        -- Reset phase to idle on completion
        current_phase = PHASES.IDLE
        -- Workflow completed - fire and forget, no return values
    end)

    -- Fire-and-forget: no return values, no coordination needed
end

return EntryWorkflow
