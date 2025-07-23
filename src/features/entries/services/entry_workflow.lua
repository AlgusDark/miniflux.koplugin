local socket_url = require('socket.url')
local UIManager = require('ui/uimanager')
local FFIUtil = require('ffi/util')
local time = require('ui/time')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

-- Import consolidated dependencies
local EntryEntity = require('domains/entries/entry_entity')
local Images = require('features/entries/utils/images')
local Trapper = require('ui/trapper')
local HtmlUtils = require('features/entries/utils/html_utils')
local Files = require('shared/utils/files')
local Notification = require('shared/utils/notification')

-- Centralized workflow message templates for consistency and maintainability
local WORKFLOW_MESSAGES = {
    -- Download workflow progress (all follow "Downloading:\n%1\n\n{phase}" pattern)
    DOWNLOAD_PREPARING = _('Downloading:\n%1\n\nPreparing...'),
    DOWNLOAD_IMAGES = _('Downloading:\n%1\n\nDownloading %2/%3 images'),
    DOWNLOAD_PROCESSING = _('Downloading:\n%1\n\nProcessing content...'),

    -- Error and status messages
    DOWNLOAD_ERRORS = _(
        'Some images failed to download (%1/%2 successful)\nContinuing with available images...'
    ),
    IMAGES_DOWNLOADED = _('%1 images downloaded'),
    IMAGES_SKIPPED = _('%1 images skipped'),

    -- Completion messages
    COMPLETION_WITH_SUMMARY = _('Download completed!\n\n%1'),
    COMPLETION_SIMPLE = _('Download completed!'),
}

-- Generate progress message for image downloads (avoids template creation in hot loop)
local function createImageProgressMessage(opts)
    return T(WORKFLOW_MESSAGES.DOWNLOAD_IMAGES, opts.title, opts.current, opts.total)
end

-- Download phases for better state tracking and cancellation handling
local PHASES = {
    IDLE = 'idle',
    PREPARING = 'preparing',
    DOWNLOADING = 'downloading',
    PROCESSING = 'processing',
    COMPLETING = 'completing',
}

-- Standardized phase results for consistent return handling
local PHASE_RESULTS = {
    SUCCESS = 'success',
    CANCELLED = 'cancelled',
    SKIP_IMAGES = 'skip_images',
    ERROR = 'error',
}

-- Current phase tracking (module-level for debugging visibility)
local current_phase = PHASES.IDLE

---Unified cancellation handler for consistent cleanup and user choice handling
---@param user_wants_to_continue boolean Result from Trapper:info() - true means continue, false means user cancelled
---@param context table Download context with paths for cleanup
---@return string PHASE_RESULTS value indicating how to proceed
local function handleCancellation(user_wants_to_continue, context)
    -- Fast path: User wants to continue, no cancellation handling needed
    if user_wants_to_continue then
        return PHASE_RESULTS.SUCCESS
    end

    --[[
    PHASE-BASED CANCELLATION STRATEGY:

    The cancellation dialog options depend on workflow phase to provide
    contextually appropriate choices:

    DOWNLOADING phase: "cancel entry", "continue without images", "resume downloading"
    OTHER phases: "cancel entry", "continue with entry creation"

    This gives users granular control over workflow cancellation.
    --]]
    local dialog_phase = current_phase == PHASES.DOWNLOADING and 'during_images' or 'after_images'
    local user_choice = EntryEntity.showCancellationDialog(dialog_phase)

    --[[
    USER CHOICE HANDLING:
    Process user's cancellation choice and determine workflow action.
    --]]
    if user_choice == 'cancel_entry' then
        --[[
        COMPLETE CANCELLATION WITH CLEANUP:
        User wants to abandon the entire workflow.
        Clean up any partial downloads and temporary files.
        --]]
        logger.info('[Miniflux:EntryWorkflow] User cancelled workflow, cleaning up')
        Images.cleanupTempFiles(context.entry_dir)
        FFIUtil.purgeDir(context.entry_dir) -- Remove entire entry directory
        current_phase = PHASES.IDLE -- Reset phase state
        return PHASE_RESULTS.CANCELLED
    elseif user_choice == 'continue_without_images' and current_phase == PHASES.DOWNLOADING then
        --[[
        SKIP IMAGES WORKFLOW:
        Only available during download phase. User wants to continue
        with entry creation but skip remaining image downloads.
        Advance phase to processing to change available cancellation options.
        --]]
        current_phase = PHASES.PROCESSING
        return PHASE_RESULTS.SKIP_IMAGES
    else
        --[[
        RESUME WORKFLOW:
        User chose to continue current operation:
        - "resume_downloading" during download phase
        - "continue_creation" during other phases
        Return to the interrupted operation.
        --]]
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

    -- Early exit: Skip download loop if images disabled or no images found
    if not settings.include_images or #images == 0 then
        return PHASE_RESULTS.SUCCESS
    end

    --[[
    EINK PERFORMANCE OPTIMIZATION STRATEGY:

    Problem: eink displays are slow to refresh. Updating progress every image
    causes sluggish UI and poor user experience on devices like Kobo/Kindle.

    Solution: Throttled progress updates with fast refresh between checks.

    Pattern proven in newsdownloader.koplugin for RSS feeds with 30+ images.
    See: https://github.com/koreader/koreader/blob/master/plugins/newsdownloader.koplugin/
    --]]
    local time_prev = time.now()
    local total_images = #images -- Cache array length to avoid repeated calculation

    for i, img in ipairs(images) do
        local user_wants_to_continue

        --[[
        THROTTLED CANCELLATION CHECKS:
        Only check for user cancellation every 1000ms to avoid UI sluggishness.
        Between checks, use fast_refresh to update progress without full repaints.
        --]]
        if time.to_ms(time.since(time_prev)) > 1000 then
            time_prev = time.now()

            -- Full progress update with cancellation check (slow but necessary)
            user_wants_to_continue = Trapper:info(createImageProgressMessage({
                title = context.title,
                current = i,
                total = total_images,
            }))

            -- Handle cancellation using unified handler
            local cancellation_result = handleCancellation(user_wants_to_continue, context)
            if cancellation_result == PHASE_RESULTS.CANCELLED then
                return PHASE_RESULTS.CANCELLED
            elseif cancellation_result == PHASE_RESULTS.SKIP_IMAGES then
                -- User chose "continue without images" - stop downloading but continue workflow
                break
            end
            -- SUCCESS: continue downloading
        else
            --[[
            FAST REFRESH OPTIMIZATION:
            Updates progress UI without full repaint (eink optimization).
            Parameters: (message, dismissable=true, fast_refresh=true)
            No cancellation check here to maintain performance.
            --]]
            Trapper:info(
                createImageProgressMessage({
                    title = context.title,
                    current = i,
                    total = total_images,
                }),
                true,
                true
            )
        end

        -- Download individual image (delegates to Images utility)
        local success = Images.downloadImage({
            url = img.src,
            url2x = img.src2x,
            entry_dir = context.entry_dir,
            filename = img.filename,
            settings = settings,
        })

        -- Track download results for later analysis and user feedback
        img.downloaded = success
        if not success then
            -- Track error reason for better user feedback (used in completion summary)
            img.error_reason = 'network_or_invalid_url'
            logger.dbg(
                '[Miniflux:EntryWorkflow] Failed to download image:',
                img.filename,
                'from',
                img.src
            )
        end

        -- Yield control to allow UI updates between downloads (prevents blocking)
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

    --[[
    CONTENT PROCESSING PHASE UI:
    Show progress to user during HTML generation and file operations.
    This is typically fast but shown for workflow consistency.
    --]]
    local user_wants_to_continue =
        Trapper:info(T(WORKFLOW_MESSAGES.DOWNLOAD_PROCESSING, context.title))

    -- Handle cancellation (cleanup will be handled by entry deletion if cancelled)
    local cancellation_result = handleCancellation(user_wants_to_continue, context)
    if cancellation_result == PHASE_RESULTS.CANCELLED then
        return PHASE_RESULTS.CANCELLED
    end

    --[[
    HTML CONTENT TRANSFORMATION:
    Process raw content through HTML utilities:
    1. Process images (update src paths to local files)
    2. Clean HTML (remove scripts, iframes, etc.)
    3. Create complete HTML document with metadata
    --]]
    local html_content, html_error = HtmlUtils.processEntryContent(content, {
        entry_data = entry_data,
        seen_images = seen_images,
        base_url = base_url,
        include_images = settings.include_images,
    })

    -- Error handling: Fail gracefully with descriptive error message
    if html_error then
        logger.err('[Miniflux:EntryWorkflow] Failed to process HTML:', html_error.message)
        Notification:error(_('Failed to process content: ') .. html_error.message)
        return PHASE_RESULTS.ERROR
    end

    if not html_content then
        Notification:error(_('Failed to process content: No content generated'))
        return PHASE_RESULTS.ERROR
    end

    --[[
    FILE PERSISTENCE:
    Save processed HTML to entry directory for offline reading.
    File operations are synchronous and typically fast.
    --]]
    local _file_written, file_error = Files.writeFile(context.html_file, html_content)
    if file_error then
        Notification:error(_('Failed to save HTML file: ') .. file_error.message)
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

    --[[
    COMPLETION SUMMARY GENERATION:
    Build user-friendly summary of what was accomplished.
    Only show meaningful counts (skip zero values for cleaner UI).
    --]]
    local summary_lines = {}

    if #images > 0 then
        if settings.include_images then
            --[[
            IMAGES ENABLED SUMMARY:
            Show actual download results using pre-computed analysis.
            Helps users understand what worked vs what failed.
            --]]
            if download_summary.success_count > 0 then
                table.insert(
                    summary_lines,
                    T(WORKFLOW_MESSAGES.IMAGES_DOWNLOADED, download_summary.success_count)
                )
            end
            if download_summary.failed_count > 0 then
                table.insert(
                    summary_lines,
                    T(WORKFLOW_MESSAGES.IMAGES_SKIPPED, download_summary.failed_count)
                )
            end
        else
            --[[
            IMAGES DISABLED SUMMARY:
            All discovered images are skipped due to user settings.
            Show total discovered count for user awareness.
            --]]
            table.insert(summary_lines, T(WORKFLOW_MESSAGES.IMAGES_SKIPPED, #images))
        end
    end

    --[[
    COMPLETION MESSAGE DISPLAY:
    Show final summary to user with Trapper.
    This is the final user interaction before opening the entry.
    --]]
    local summary = #summary_lines > 0 and table.concat(summary_lines, '\n') or ''
    local message = summary ~= '' and T(WORKFLOW_MESSAGES.COMPLETION_WITH_SUMMARY, summary)
        or WORKFLOW_MESSAGES.COMPLETION_SIMPLE

    Trapper:info(message) -- Final progress message (user typically dismisses quickly)
    return PHASE_RESULTS.SUCCESS
end

-- **Entry Workflow** - Handles the complete workflow for downloading and opening
-- RSS entries. Uses Trapper for progress tracking and user interaction in a
-- fire-and-forget pattern. Orchestrates the entire process: download, file
-- creation, and opening.
local EntryWorkflow = {}

---Execute complete entry workflow with progress tracking (fire-and-forget)
---Downloads entry, creates files, and opens in reader with full user interaction support
---@param deps {entry_data: table, settings: table, browser?: table, context?: MinifluxContext}
function EntryWorkflow.execute(deps)
    local entry_data = deps.entry_data
    local settings = deps.settings
    local browser = deps.browser
    local browser_context = deps.context

    --[[
    TRAPPER WORKFLOW PATTERN EXPLANATION:

    Trapper is KOReader's UI system for long-running operations with user interaction.
    Docs: https://github.com/koreader/koreader/tree/master/frontend/ui

    Key concepts:
    1. Trapper:wrap() - Creates a UI context where Trapper:info() calls work
    2. Trapper:info(message) - Shows progress dialog, returns boolean:
       - true: user wants to continue (didn't press back/cancel)
       - false: user cancelled (pressed back or cancel button)
    3. All UI interactions must happen inside Trapper:wrap()
    4. The wrapped function should be fire-and-forget (no return values)
    5. Cancellation can happen at any Trapper:info() call

    Our workflow uses phases to control what cancellation options are shown
    to the user based on how far through the process we are.
    --]]

    -- Execute complete workflow in Trapper for user interaction support
    Trapper:wrap(function()
        -- Phase management: Tracks workflow state to show appropriate cancellation dialogs
        current_phase = PHASES.IDLE

        --[[
        EARLY EXIT OPTIMIZATION:
        Check if entry is already downloaded to avoid unnecessary work.
        This is common when users re-open the same entry.
        --]]
        if EntryEntity.isEntryDownloaded(entry_data.id) then
            local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)
            -- Use Files.openWithReader for clean file opening
            Files.openWithReader(html_file, {
                before_open = function()
                    if browser then
                        browser:close()
                    end
                end,
                context = browser_context,
            })
            return -- Completed - fire and forget
        end

        --[[
        PHASE 1: PREPARATION
        - Create download directories
        - Extract content and discover images
        - Show initial progress to user
        Phase state affects cancellation: only "cancel entry" option available
        --]]
        current_phase = PHASES.PREPARING

        -- Prepare download context inline
        local title = entry_data.title or _('Untitled Entry')
        local entry_dir = EntryEntity.getEntryDirectory(entry_data.id)
        local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)

        -- Create entry directory (using Files utility for reusability)
        local _dir_created, dir_error = Files.createDirectory(entry_dir)
        if dir_error then
            Notification:error(_('Failed to prepare download: ') .. dir_error.message)
            return -- Failed - fire and forget
        end

        local context = {
            title = title,
            entry_dir = entry_dir,
            html_file = html_file,
        }

        -- First user interaction: Show preparation progress
        -- Trapper:info() returns true if user wants to continue, false if cancelled
        logger.info(
            '[Miniflux:EntryWorkflow] Starting download for entry',
            entry_data.id,
            ':',
            title
        )
        local user_wants_to_continue = Trapper:info(
            T(WORKFLOW_MESSAGES.DOWNLOAD_PREPARING, context.title or _('Unknown Entry'))
        )

        -- Handle cancellation using unified handler (checks current phase for appropriate options)
        local cancellation_result = handleCancellation(user_wants_to_continue, context)
        if cancellation_result == PHASE_RESULTS.CANCELLED then
            return -- User cancelled - fire and forget
        end

        -- Always discover images to build mapping (regardless of download setting)
        local content = entry_data.content or entry_data.summary or ''
        local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
        local images, seen_images = Images.discoverImages(content, base_url)

        if not images then
            Notification:error(_('Failed to discover images'))
            return -- Discovery failed - fire and forget
        end

        -- Build image mapping from discovered images (always needed for metadata)
        local images_mapping = {}
        for _, img in ipairs(images) do
            images_mapping[img.filename] = img.src
        end

        --[[
        PHASE 2: IMAGE DOWNLOADING
        - Downloads images with progress tracking
        - User can cancel, skip images, or continue
        Phase state affects cancellation: "cancel", "skip images", or "continue" options
        --]]
        current_phase = PHASES.DOWNLOADING
        local download_phase_status = downloadImagesWithProgress({
            images = images,
            context = context,
            settings = settings,
        })
        if download_phase_status == PHASE_RESULTS.CANCELLED then
            return -- User cancelled - fire and forget
        end

        --[[
        DOWNLOAD RESULT ANALYSIS:
        Count successful vs failed downloads for user feedback.
        Inlined per YAGNI - simple counting logic doesn't justify separate function.
        --]]
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
            has_errors = failed_count > 0,
        }

        --[[
        ERROR TOLERANCE STRATEGY:
        Show network error summary but continue with available images.
        UX decision: Partial content is better than no content for RSS entries.
        --]]
        if download_summary.has_errors then
            logger.warn(
                '[Miniflux:EntryWorkflow] Image download errors:',
                failed_count,
                'of',
                #images,
                'failed'
            )
            local error_msg = T(
                WORKFLOW_MESSAGES.DOWNLOAD_ERRORS,
                download_summary.success_count,
                download_summary.total_count
            )
            Trapper:info(error_msg) -- Show error summary, then continue
        end

        --[[
        PHASE 3: CONTENT PROCESSING
        - Generate HTML with downloaded images
        - Save file and metadata
        Phase state affects cancellation: only "cancel" available (images already downloaded)
        --]]
        current_phase = PHASES.PROCESSING
        local html_generation_status = generateHtmlContent({
            entry_data = entry_data,
            context = context,
            content = content,
            seen_images = seen_images,
            base_url = base_url,
            settings = settings,
        })
        if
            html_generation_status == PHASE_RESULTS.CANCELLED
            or html_generation_status == PHASE_RESULTS.ERROR
        then
            return -- Failed or cancelled - fire and forget
        end

        -- Save metadata directly using EntryEntity (no abstraction needed per YAGNI)
        local _metadata_result, metadata_error = EntryEntity.saveMetadata({
            entry_data = entry_data,
            images_mapping = images_mapping,
        })
        if metadata_error then
            Notification:error(_('Failed to save metadata: ') .. metadata_error.message)
            return -- Failed - fire and forget
        end

        --[[
        PHASE 4: COMPLETION
        - Show final summary with image statistics
        - Open completed entry in reader
        Phase state: Final phase, no cancellation needed
        --]]
        current_phase = PHASES.COMPLETING
        local _completion_status = showCompletionSummary({
            images = images,
            settings = settings,
            download_summary = download_summary,
        })

        -- Open completed entry (clean file opening with browser cleanup)
        logger.info(
            '[Miniflux:EntryWorkflow] Successfully downloaded entry',
            entry_data.id,
            'with',
            success_count,
            'images'
        )
        Files.openWithReader(context.html_file, {
            before_open = function()
                if browser then
                    browser:close() -- Close browser before opening reader
                end
            end,
            context = browser_context,
        })

        -- Reset phase to idle on completion (important for module-level state)
        current_phase = PHASES.IDLE
        -- Workflow completed - fire and forget, no return values
    end)

    -- Fire-and-forget: no return values, no coordination needed
end

return EntryWorkflow
