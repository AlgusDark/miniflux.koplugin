local EntryEntity = require('domains/entries/entry_entity')
local logger = require('logger')

-- **Metadata Preserver** - Utility to preserve miniflux metadata during ReaderUI close
--
-- This solves a race condition where ReaderUI's onClose saves its cached metadata,
-- potentially overwriting our updates. We wrap onClose to restore our metadata after
-- ReaderUI's save completes.
local MetadataPreserver = {}

---Wrap ReaderUI's onClose to preserve miniflux metadata
---@param reader_ui ReaderUI The ReaderUI instance to wrap
---@return table|nil wrapped The wrapped method handle, or nil if not applicable
function MetadataPreserver.wrapReaderClose(reader_ui)
    local util = require('util')

    -- Validate input
    if not reader_ui or not reader_ui.document then
        return nil
    end

    -- Check if this is a miniflux entry
    local file_path = reader_ui.document.file
    if not EntryEntity.isMinifluxEntry(file_path) then
        return nil
    end

    local entry_id = EntryEntity.extractEntryIdFromPath(file_path)
    if not entry_id then
        logger.warn('[Miniflux:MetadataPreserver] Could not extract entry ID from path:', file_path)
        return nil
    end

    -- Store the original onClose method before wrapping
    local original_onClose = reader_ui.onClose

    -- Create wrapper function
    local wrapper_func = function(this, ...)
        -- Step 1: Load current miniflux metadata from SDR before ReaderUI saves
        local preserved_metadata = EntryEntity.loadMetadata(entry_id)

        if preserved_metadata then
            logger.info('[Miniflux:MetadataPreserver] Preserved miniflux metadata before close:', {
                entry_id = entry_id,
                status = preserved_metadata.status,
                title = preserved_metadata.title,
                feed = preserved_metadata.feed and preserved_metadata.feed.title,
                category = preserved_metadata.category and preserved_metadata.category.title,
                last_updated = preserved_metadata.last_updated,
            })
        else
            logger.warn(
                '[Miniflux:MetadataPreserver] No miniflux metadata found to preserve for entry:',
                entry_id
            )
        end

        -- Step 2: Call original onClose (this saves ReaderUI's in-memory state)
        local result = original_onClose(this, ...)

        -- Step 3: Intelligently merge miniflux metadata based on source of truth
        if preserved_metadata then
            -- Load what ReaderUI just saved to compare
            local DocSettings = require('docsettings')
            local html_file = EntryEntity.getEntryHtmlPath(entry_id)
            local doc_settings = DocSettings:open(html_file)
            local after_close_metadata = doc_settings:readSetting('miniflux_entry')

            logger.info(
                '[Miniflux:MetadataPreserver] After ReaderUI close, miniflux metadata is:',
                {
                    entry_id = entry_id,
                    status = after_close_metadata and after_close_metadata.status,
                    title = after_close_metadata and after_close_metadata.title,
                    feed = after_close_metadata
                        and after_close_metadata.feed
                        and after_close_metadata.feed.title,
                    category = after_close_metadata
                        and after_close_metadata.category
                        and after_close_metadata.category.title,
                    last_updated = after_close_metadata and after_close_metadata.last_updated,
                }
            )

            -- Intelligent merge: Determine source of truth
            local metadata_to_save = preserved_metadata

            -- If ReaderUI has miniflux metadata, check timestamps to determine which is newer
            if
                after_close_metadata
                and after_close_metadata.last_updated
                and preserved_metadata.last_updated
            then
                -- Parse timestamps to compare (format: "YYYY-MM-DD HH:MM:SS")
                local function parseTimestamp(ts)
                    local year, month, day, hour, min, sec =
                        ts:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
                    if year then
                        return os.time({
                            year = tonumber(year) or 0,
                            month = tonumber(month) or 1,
                            day = tonumber(day) or 1,
                            hour = tonumber(hour) or 0,
                            min = tonumber(min) or 0,
                            sec = tonumber(sec) or 0,
                        })
                    end
                    return 0
                end

                local preserved_time = parseTimestamp(preserved_metadata.last_updated)
                local after_close_time = parseTimestamp(after_close_metadata.last_updated)

                -- If ReaderUI's metadata is newer, it might have user's manual changes
                if after_close_time > preserved_time then
                    logger.info(
                        '[Miniflux:MetadataPreserver] ReaderUI metadata is newer, checking for changes...'
                    )

                    -- Check if this is a subprocess update (auto-mark-as-read)
                    if after_close_metadata.subprocess_update then
                        -- Check if subprocess update is very recent (within 5 seconds)
                        local current_time = os.time()
                        local subprocess_age = current_time
                            - (after_close_metadata.subprocess_timestamp or 0)

                        if subprocess_age < 5 then
                            logger.info(
                                '[Miniflux:MetadataPreserver] Recent subprocess update detected, keeping it'
                            )
                            metadata_to_save = after_close_metadata
                        else
                            logger.dbg(
                                '[Miniflux:MetadataPreserver] Old subprocess update, using preserved metadata'
                            )
                        end
                    elseif after_close_metadata.status ~= preserved_metadata.status then
                        -- Status changed and it's not from subprocess - this is user action
                        logger.info(
                            '[Miniflux:MetadataPreserver] User changed status from',
                            preserved_metadata.status,
                            'to',
                            after_close_metadata.status,
                            '- keeping user change'
                        )
                        metadata_to_save = after_close_metadata
                    else
                        -- Same status but newer timestamp - keep preserved for consistency
                        logger.dbg(
                            '[Miniflux:MetadataPreserver] Same status, keeping preserved metadata'
                        )
                    end
                else
                    logger.dbg(
                        '[Miniflux:MetadataPreserver] Preserved metadata is newer or same age'
                    )
                end
            end

            -- Check if there's a pending queue entry that might indicate recent user action
            local miniflux_dir = EntryEntity.getDownloadDir()
            local queue_file = miniflux_dir .. 'status_queue.lua'
            local lfs = require('libs/libkoreader-lfs')

            if lfs.attributes(queue_file, 'mode') then
                local success, queue_result = pcall(dofile, queue_file)
                if success and type(queue_result) == 'table' then
                    local queue_data = queue_result
                    if queue_data[entry_id] then
                        -- There's a pending status change in queue - this is the most recent intent
                        logger.info(
                            '[Miniflux:MetadataPreserver] Found pending queue entry, using queued status:',
                            queue_data[entry_id].new_status
                        )
                        metadata_to_save.status = queue_data[entry_id].new_status
                        metadata_to_save.last_updated =
                            os.date('%Y-%m-%d %H:%M:%S', queue_data[entry_id].timestamp) --[[@as string]]
                    end
                end
            end

            -- Save the determined metadata
            logger.dbg(
                '[Miniflux:MetadataPreserver] Saving miniflux_entry metadata with status:',
                metadata_to_save.status
            )
            doc_settings:saveSetting('miniflux_entry', metadata_to_save)
            local flush_result = doc_settings:flush()

            if flush_result then
                logger.info(
                    '[Miniflux:MetadataPreserver] Successfully saved miniflux metadata for entry:',
                    entry_id
                )
            else
                logger.err(
                    '[Miniflux:MetadataPreserver] Failed to flush metadata for entry:',
                    entry_id
                )
            end
        end

        return result
    end

    -- Wrap the onClose method
    local wrapped = util.wrapMethod(reader_ui, 'onClose', wrapper_func)

    logger.dbg('[Miniflux:MetadataPreserver] Wrapped ReaderUI onClose for entry:', entry_id)
    return wrapped
end

return MetadataPreserver
