local socket_url = require('socket.url')
local time = require('ui/time')
local UIManager = require('ui/uimanager')
local _ = require('gettext')
local T = require('ffi/util').template

-- Import consolidated dependencies
local EntryEntity = require('domains/entries/entry_entity')
local Images = require('features/entries/utils/images')
local Trapper = require('ui/trapper')
local HtmlUtils = require('features/entries/utils/html_utils')
local Files = require('shared/utils/files')

-- **Batch Download Entries Workflow** - Sequential batch downloading of multiple entries
--
-- This workflow downloads multiple entries sequentially with proper progress tracking.
-- Unlike EntryWorkflow which handles individual entries, this manages the entire batch
-- operation within a single Trapper context for proper sequential processing.
local BatchDownloadEntriesWorkflow = {}

---Execute batch download workflow with sequential processing
---@param deps {entry_data_list: table, settings: table, completion_callback?: function}
function BatchDownloadEntriesWorkflow.execute(deps)
    local entry_data_list = deps.entry_data_list
    local settings = deps.settings
    local completion_callback = deps.completion_callback

    local total_entries = #entry_data_list
    if total_entries == 0 then
        if completion_callback then
            completion_callback('completed')
        end
        return
    end

    -- Execute batch workflow in single Trapper context for sequential processing
    Trapper:wrap(function()
        local completed_count = 0
        local failed_count = 0

        -- Batch state tracking for stateful cancellation dialogs
        local batch_state = {
            skip_images_for_all = false,
            should_cancel_all = false,
            current_entry_index = 1,
            total_entries = total_entries,
            current_entry_title = '',
        }

        -- Time tracking for throttled UI updates (following EntryWorkflow pattern)
        local time_prev = time.now()

        -- Process each entry sequentially
        for entry_index, entry_data in ipairs(entry_data_list) do
            local entry_title = entry_data.title or _('Untitled Entry')

            -- Update batch state for current entry
            batch_state.current_entry_index = entry_index
            batch_state.current_entry_title = entry_title

            -- Show progress for current entry
            local progress_message = total_entries == 1 and T(_('Downloading: %1'), entry_title)
                or T(_('Downloading %1/%2: %3'), entry_index, total_entries, entry_title)

            local user_wants_to_continue

            -- Throttled cancellation checks (only every 1000ms to prevent UI freezing)
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()

                -- Full progress update with cancellation check
                user_wants_to_continue = Trapper:info(progress_message)

                -- Handle batch cancellation with enhanced dialog
                if not user_wants_to_continue then
                    local user_choice =
                        EntryEntity.showBatchCancellationDialog('during_batch', batch_state)

                    if user_choice == 'cancel_all_entries' then
                        local cancelled_message = T(
                            _('Batch download cancelled. Downloaded %1/%2 entries.'),
                            completed_count,
                            total_entries
                        )
                        Trapper:info(cancelled_message)
                        if completion_callback then
                            UIManager:nextTick(function()
                                completion_callback('cancelled')
                            end)
                        end
                        return
                    elseif user_choice == 'skip_images_all' then
                        batch_state.skip_images_for_all = true
                        -- Continue with current entry
                    elseif user_choice == 'include_images_all' then
                        batch_state.skip_images_for_all = false
                        -- Continue with current entry
                    end
                end
            else
                -- Fast refresh without cancellation check (prevents UI blocking)
                Trapper:info(progress_message, true, true)
            end

            -- Download individual entry with updated batch state
            local success = BatchDownloadEntriesWorkflow.downloadSingleEntry(entry_data, {
                settings = settings,
                entry_index = entry_index,
                total_entries = total_entries,
                batch_state = batch_state,
            })

            -- Check if user chose to cancel all entries (set by downloadSingleEntry)
            if batch_state.should_cancel_all then
                local cancelled_message = T(
                    _('Batch download cancelled. Downloaded %1/%2 entries.'),
                    completed_count,
                    total_entries
                )
                Trapper:info(cancelled_message)
                if completion_callback then
                    UIManager:nextTick(function()
                        completion_callback('cancelled')
                    end)
                end
                return
            end

            if success then
                completed_count = completed_count + 1
            else
                failed_count = failed_count + 1
            end
        end

        -- Show final summary
        local summary_message
        if failed_count == 0 then
            summary_message = total_entries == 1 and _('Download completed successfully!')
                or T(_('All %1 entries downloaded successfully!'), total_entries)
        elseif completed_count == 0 then
            summary_message = total_entries == 1 and _('Download failed.')
                or T(_('All %1 entries failed to download.'), total_entries)
        else
            summary_message = T(
                _('Batch download completed: %1 successful, %2 failed.'),
                completed_count,
                failed_count
            )
        end

        Trapper:info(summary_message)

        -- Call completion callback after Trapper context ends to avoid UI conflicts
        if completion_callback then
            UIManager:nextTick(function()
                completion_callback('completed')
            end)
        end
    end)
end

---Download a single entry with progress tracking (extracted from EntryWorkflow for reuse)
---@param entry_data table Entry data from API
---@param opts table Options table with settings, entry_index, total_entries, batch_state
---@return boolean success
function BatchDownloadEntriesWorkflow.downloadSingleEntry(entry_data, opts)
    -- Extract options
    local settings = opts.settings
    local entry_index = opts.entry_index
    local total_entries = opts.total_entries
    local batch_state = opts.batch_state

    -- Validate entry data
    local _valid, err = EntryEntity.validateForDownload(entry_data)
    if err then
        return false
    end

    -- Check if already downloaded
    if EntryEntity.isEntryDownloaded(entry_data.id) then
        return true -- Consider already downloaded as success
    end

    -- Prepare download context
    local title = entry_data.title or _('Untitled Entry')
    local entry_dir = EntryEntity.getEntryDirectory(entry_data.id)
    local html_file = EntryEntity.getEntryHtmlPath(entry_data.id)

    -- Create entry directory
    local _dir_created, dir_error = Files.createDirectory(entry_dir)
    if dir_error then
        return false
    end

    local context = {
        title = title,
        entry_dir = entry_dir,
        html_file = html_file,
    }

    -- Discover images
    local content = entry_data.content or entry_data.summary or ''
    local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
    local images, seen_images = Images.discoverImages(content, base_url)

    if not images then
        return false
    end

    -- Download images with detailed progress tracking and batch state awareness
    if settings.include_images and #images > 0 and not batch_state.skip_images_for_all then
        local total_images = #images
        local time_prev = time.now()

        for img_idx, img in ipairs(images) do
            -- Show detailed image progress with throttling (same pattern as EntryWorkflow)
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()

                -- Build progress message showing entry and image progress
                local image_progress = total_entries == 1
                        and T(
                            _('Downloading:\n%1\n\nDownloading %2/%3 images'),
                            context.title,
                            img_idx,
                            total_images
                        )
                    or T(
                        _('Downloading %1/%2:\n%3\n\nDownloading %4/%5 images'),
                        entry_index,
                        total_entries,
                        context.title,
                        img_idx,
                        total_images
                    )

                local user_wants_to_continue = Trapper:info(image_progress)
                if not user_wants_to_continue then
                    -- User cancelled during image download - show enhanced dialog
                    local user_choice =
                        EntryEntity.showBatchCancellationDialog('during_entry_images', batch_state)

                    if user_choice == 'cancel_current_entry' then
                        return false -- Skip this entire entry
                    elseif user_choice == 'cancel_all_entries' then
                        batch_state.should_cancel_all = true
                        return false -- Signal to cancel all entries via batch_state
                    elseif user_choice == 'skip_images_current' then
                        break -- Skip remaining images for this entry only
                    elseif user_choice == 'skip_images_all' then
                        batch_state.skip_images_for_all = true
                        break -- Skip remaining images for this entry and all future entries
                    elseif user_choice == 'include_images_all' then
                        batch_state.skip_images_for_all = false
                        -- Continue downloading images
                    end
                end
            else
                -- Fast refresh for image progress
                local image_progress = total_entries == 1
                        and T(
                            _('Downloading:\n%1\n\nDownloading %2/%3 images'),
                            context.title,
                            img_idx,
                            total_images
                        )
                    or T(
                        _('Downloading %1/%2:\n%3\n\nDownloading %4/%5 images'),
                        entry_index,
                        total_entries,
                        context.title,
                        img_idx,
                        total_images
                    )

                Trapper:info(image_progress, true, true)
            end

            -- Download individual image (delegates to Images utility with proxy support)
            local success = Images.downloadImage({
                url = img.src,
                url2x = img.src2x,
                entry_dir = context.entry_dir,
                filename = img.filename,
                settings = settings,
            })
            img.downloaded = success
            if not success then
                img.error_reason = 'network_or_invalid_url'
            end
        end
    end

    -- Generate HTML content (respect batch state for images)
    local effective_include_images = settings.include_images and not batch_state.skip_images_for_all
    local html_content, html_error = HtmlUtils.processEntryContent(content, {
        entry_data = entry_data,
        seen_images = seen_images,
        base_url = base_url,
        include_images = effective_include_images,
    })

    if html_error or not html_content then
        return false
    end

    -- Save HTML file
    local _file_written, file_error = Files.writeFile(context.html_file, html_content)
    if file_error then
        return false
    end

    -- Count successful images for metadata
    local success_count = 0
    for _, img in ipairs(images) do
        if img.downloaded then
            success_count = success_count + 1
        end
    end

    -- Save metadata (respect batch state for images)
    local _metadata_result, metadata_error = EntryEntity.saveMetadata({
        entry_data = entry_data,
        images_count = success_count,
        include_images = effective_include_images,
    })

    return metadata_error == nil
end

return BatchDownloadEntriesWorkflow
