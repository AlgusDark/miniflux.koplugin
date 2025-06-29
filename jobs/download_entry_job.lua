--[[--
Entry Download Job

Handles the downloading and local creation of RSS entries with cancellation support.
Uses Trapper for progress tracking and user cancellation.

@module koplugin.miniflux.jobs.download_entry_job
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
---@param context table Download context
---@param settings table Settings instance
---@return table images, table seen_images, string content
local function discoverImages(entry_data, context, settings)
    local content = entry_data.content or entry_data.summary or ""
    local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
    local images, seen_images = Images.discoverImages(content, base_url)

    -- Show image discovery progress
    local image_info = ""
    if settings.include_images and #images > 0 then
        image_info = T(_("\n\nImages found: %1"), #images)
    elseif not settings.include_images and #images > 0 then
        image_info = T(_("\n\nImages: %1 found (skipped)"), #images)
    end

    local go_on = Trapper:info(T(_("Downloading Article:\n%1\n\nFound images%2"), context.title, image_info))
    if not go_on then
        return nil, nil, nil -- Signal cancellation
    end

    return images, seen_images, content, base_url
end

---Download images with progress tracking and cancellation support
---@param images table Array of image info
---@param context table Download context
---@param settings table Settings instance
---@return string "success" | "cancelled"
local function downloadImagesWithProgress(images, context, settings)
    if not settings.include_images or #images == 0 then
        return "success"
    end

    local images_downloaded = 0
    local time_prev = time.now()

    for i, img in ipairs(images) do
        -- Performance optimization for eink devices downloading many images:
        -- 1. Throttle cancellation checks to every 1000ms to avoid UI sluggishness
        -- 2. Use fast_refresh (3rd parameter = true) to update progress without
        --    full UI repaints between cancellation checks
        -- This pattern is proven in newsdownloader.koplugin for RSS feeds with 30+ images
        local go_on
        if time.to_ms(time.since(time_prev)) > 1000 then
            time_prev = time.now()
            go_on = Trapper:info(T(_("Downloading Images:\n%1\n\nDownloading: %2\n\nProgress: %3 / %4 images"),
                context.title, img.filename or T(_("image_%1"), i), i, #images))

            -- Handle pause RIGHT HERE - don't exit loop!
            if not go_on then
                local user_choice = EntryUtils.showCancellationDialog("during_images")

                if user_choice == "cancel_entry" then
                    -- Delete files and exit completely
                    Images.cleanupTempFiles(context.entry_dir)
                    FFIUtil.purgeDir(context.entry_dir)
                    return "cancelled"
                elseif user_choice == "continue_without_images" then
                    -- Stop downloading but continue with entry creation
                    break
                    -- user_choice == "resume_downloading": just continue the loop!
                end
            end
        else
            -- Fast refresh without cancellation check - updates UI without full repaint (eink optimization)
            Trapper:info(T(_("Downloading Images:\n%1\n\nDownloading: %2\n\nProgress: %3 / %4 images"),
                context.title, img.filename or T(_("image_%1"), i), i, #images), true, true)
        end

        -- Download with error tracking
        local success = Images.downloadImage({
            url = img.src,
            entry_dir = context.entry_dir,
            filename = img.filename
        })

        img.downloaded = success
        if success then
            images_downloaded = images_downloaded + 1
        else
            -- Track error reason for better user feedback
            img.error_reason = "network_or_invalid_url"
        end

        -- Yield control to allow UI updates between downloads
        UIManager:nextTick(function() end)
    end

    return "success"
end

---Handle cancellation during post-image phases with cleanup
---@param context table Download context
---@return boolean continue (false = exit, true = continue)
local function handlePostImageCancellation(context)
    local user_choice = EntryUtils.showCancellationDialog("after_images")
    if user_choice == "cancel_entry" then
        -- Delete everything including downloaded images
        Images.cleanupTempFiles(context.entry_dir)
        FFIUtil.purgeDir(context.entry_dir)
        return false
    end
    -- user_choice == "continue_creation": proceed with operation
    return true
end

---Analyze download results and return summary
---@param images table Array of image info with downloaded flags
---@return table Summary with success_count and failed_count
local function analyzeDownloadResults(images)
    local success_count = 0
    local failed_count = 0
    local error_types = {}

    for _, img in ipairs(images) do
        if img.downloaded then
            success_count = success_count + 1
        else
            failed_count = failed_count + 1
            local error_type = img.error_reason or "unknown_error"
            error_types[error_type] = (error_types[error_type] or 0) + 1
        end
    end

    return {
        success_count = success_count,
        failed_count = failed_count,
        total_count = #images,
        error_types = error_types,
        has_errors = failed_count > 0
    }
end

---Process and generate HTML content
---@param entry_data table Entry data from API
---@param context table Download context
---@param content string Entry content
---@param images table Images array
---@param seen_images table Seen images map
---@param base_url table|nil Parsed base URL
---@param settings table Settings instance
---@return boolean success
local function generateHtmlContent(entry_data, context, content, images, seen_images, base_url, settings)
    -- Phase 4: Processing content
    local go_on = Trapper:info(T(_("Creating Article:\n%1\n\nProcessing content…"), context.title))
    if not go_on then
        if not handlePostImageCancellation(context) then
            return false
        end
    end

    -- Process and clean content
    local processed_content = Images.processHtmlImages(content, seen_images, settings.include_images, base_url)
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    -- Phase 5: Creating HTML file
    go_on = Trapper:info(T(_("Creating Article:\n%1\n\nGenerating HTML file…"), context.title))
    if not go_on then
        if not handlePostImageCancellation(context) then
            return false
        end
    end

    -- Create and save HTML document
    local html_content = HtmlUtils.createHtmlDocument(entry_data, processed_content)
    local file_success = Files.writeFile(context.html_file, html_content)
    if not file_success then
        Notification:error(_("Failed to save HTML file"))
        return false
    end

    return true
end

---Save entry metadata
---@param entry_data table Entry data from API
---@param context table Download context
---@param images_count number Count of successfully downloaded images
---@param settings table Settings instance
---@return boolean success
local function saveMetadata(entry_data, context, images_count, settings)
    -- Phase 6: Creating metadata
    local go_on = Trapper:info(T(_("Creating Article:\n%1\n\nSaving metadata…"), context.title))
    if not go_on then
        if not handlePostImageCancellation(context) then
            return false
        end
    end

    -- Save metadata using DocSettings
    local metadata_saved = EntryUtils.saveMetadata({
        entry_data = entry_data,
        include_images = settings.include_images,
        images_count = images_count,
    })

    if not metadata_saved then
        Notification:error(_("Failed to save entry metadata"))
        return false
    end

    return true
end

---Open the completed entry
---@param context table Download context
---@param images table Images array
---@param settings table Settings instance
---@param browser MinifluxBrowser|nil Browser instance to close
---@return boolean success
local function openCompletedEntry(context, images, settings, browser)
    -- Show completion summary
    local image_summary = Images.createDownloadSummary(settings.include_images, images)
    Trapper:info(T(_("Article Ready:\n%1\n\nDownload completed!\n\n%2"), context.title, image_summary))

    -- Open entry with browser cleanup
    EntryUtils.openEntry(context.html_file, {
        before_open = function()
            if browser then
                browser:close()
            end
        end
    })
    return true
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local DownloadEntryJob = {}

---Start a cancellable entry download with progress tracking (uses Trapper for UI progress)
---@param deps {entry_data: table, settings: table, browser?: table}
---@return boolean success
function DownloadEntryJob.startCancellableDownload(deps)
    local entry_data = deps.entry_data
    local settings = deps.settings
    local browser = deps.browser

    -- Wrap entire download operation in Trapper for cancellation support
    return Trapper:wrap(function()
        -- Check if already downloaded
        if handleExistingEntry(entry_data, browser) then
            return true
        end

        -- Phase 1: Initial progress
        local context = prepareDownload(entry_data)
        local go_on = Trapper:info(T(_("Downloading Article:\n%1\n\nPreparing download…"), context.title))
        if not go_on then
            return false
        end

        -- Phase 2: Scanning for images
        go_on = Trapper:info(T(_("Downloading Article:\n%1\n\nScanning for images…"), context.title))
        if not go_on then
            return false
        end

        local images, seen_images, content, base_url = discoverImages(entry_data, context, settings)
        if not images then
            return false -- User cancelled
        end

        -- Phase 3: Download images if enabled
        local download_result = downloadImagesWithProgress(images, context, settings)
        if download_result == "cancelled" then
            return false -- Entry was deleted, exit completely
        end

        -- Check for network errors and report summary
        local download_summary = analyzeDownloadResults(images)
        if download_summary.has_errors then
            local error_msg = T(
                _(
                    "Image download summary:\n✓ %1 successful\n✗ %2 failed\n\nMost common causes:\n• Network connectivity issues\n• Invalid or expired image URLs\n• Server access restrictions\n• Large file size limits\n\nThe entry will be created with available images."),
                download_summary.success_count, download_summary.failed_count)
            Trapper:info(error_msg)
        end

        -- Generate HTML content
        if not generateHtmlContent(entry_data, context, content, images, seen_images, base_url, settings) then
            return false
        end

        -- Save metadata with actual download counts
        local download_summary = analyzeDownloadResults(images)
        if not saveMetadata(entry_data, context, download_summary.success_count, settings) then
            return false
        end

        -- Open completed entry
        return openCompletedEntry(context, images, settings, browser)
    end) or false
end

return DownloadEntryJob
