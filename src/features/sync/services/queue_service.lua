local logger = require('logger')
local lfs = require('libs/libkoreader-lfs')

local EntryPaths = require('domains/utils/entry_paths')
local EntryValidation = require('domains/utils/entry_validation')
local Files = require('shared/files')

---@class QueueService
---Pure queue utility functions for managing entry status queues
local QueueService = {}

-- =============================================================================
-- ENTRY STATUS QUEUE MANAGEMENT
-- =============================================================================

---Get the path to the status queue file
---@return string Queue file path
function QueueService.getEntryStatusQueueFilePath()
    -- Use the same directory as entries for consistency
    local miniflux_dir = EntryPaths.getDownloadDir()
    return miniflux_dir .. 'status_queue.lua'
end

---Load the entry status queue from disk (static/pure function)
---@return table Queue data (entry_id -> {new_status, original_status, timestamp})
function QueueService.loadEntryStatusQueue()
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Check if queue file exists
    if not lfs.attributes(queue_file, 'mode') then
        return {} -- Empty queue if file doesn't exist
    end

    -- Load and execute the Lua file
    local success, queue_data = pcall(dofile, queue_file)
    if success and type(queue_data) == 'table' then
        return queue_data
    else
        return {}
    end
end

---Save the entry status queue to disk (static/pure function)
---@param queue table Queue data to save
---@return boolean success
function QueueService.saveEntryStatusQueue(queue)
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Ensure miniflux directory exists
    local miniflux_dir = queue_file:match('(.+)/[^/]+$')
    local success, _err = Files.createDirectory(miniflux_dir)
    if not success then
        return false
    end

    -- Convert queue table to Lua code
    local queue_content = 'return {\n'
    for entry_id, opts in pairs(queue) do
        queue_content = queue_content
            .. string.format(
                '  [%d] = {\n    new_status = %q,\n    original_status = %q,\n    timestamp = %d\n  },\n',
                entry_id,
                opts.new_status,
                opts.original_status,
                opts.timestamp
            )
    end
    queue_content = queue_content .. '}\n'

    -- Write to file
    local write_success, _write_err = Files.writeFile(queue_file, queue_content)
    if not write_success then
        return false
    end

    return true
end

---Add a status change to the entry status queue (static/pure function)
---@param entry_id number Entry ID
---@param opts table Options {new_status: string, original_status: string}
---@return boolean success
function QueueService.enqueueStatusChange(entry_id, opts)
    if not EntryValidation.isValidId(entry_id) then
        return false
    end

    local queue = QueueService.loadEntryStatusQueue()

    -- Add/update entry in queue (automatic deduplication via entry_id key)
    queue[entry_id] = {
        new_status = opts.new_status,
        original_status = opts.original_status,
        timestamp = os.time(),
    }

    local success = QueueService.saveEntryStatusQueue(queue)

    if success then
        logger.dbg(
            '[Miniflux:QueueService] Enqueued status change for entry',
            entry_id,
            'from',
            opts.original_status,
            'to',
            opts.new_status
        )
    else
        logger.err('[Miniflux:QueueService] Failed to save queue after enqueuing entry', entry_id)
    end

    return success
end

---Remove a specific entry from the status queue (static/pure function)
---@param entry_id number Entry ID to remove
---@return boolean success
function QueueService.removeFromEntryStatusQueue(entry_id)
    if not EntryValidation.isValidId(entry_id) then
        return false
    end

    local queue = QueueService.loadEntryStatusQueue()

    -- Check if entry exists in queue
    if not queue[entry_id] then
        return true -- Entry not in queue, nothing to do
    end

    -- Remove entry from queue
    queue[entry_id] = nil

    -- Save updated queue
    return QueueService.saveEntryStatusQueue(queue)
end

---Clear the entry status queue (static/pure function)
---@return boolean success
function QueueService.clearEntryStatusQueue()
    local queue_file = QueueService.getEntryStatusQueueFilePath()

    -- Check if file exists before trying to remove it
    local file_exists = lfs.attributes(queue_file, 'mode') == 'file'

    if not file_exists then
        return true -- File doesn't exist, so it's already "cleared"
    end

    -- Remove the queue file
    local success = os.remove(queue_file)
    return success ~= nil
end

---Get total count across all queue types (static/pure function)
---@return number total_count, number status_count, number feed_count, number category_count
function QueueService.getTotalQueueCount()
    local CollectionsQueue = require('features/sync/utils/collections_queue')
    local feed_queue = CollectionsQueue:new('feed')
    local category_queue = CollectionsQueue:new('category')

    -- Count entry status queue
    local status_queue = QueueService.loadEntryStatusQueue()
    local status_count = 0
    for _ in pairs(status_queue) do
        status_count = status_count + 1
    end

    -- Count feed and category queues
    local feed_count = feed_queue:count()
    local category_count = category_queue:count()

    local total_count = status_count + feed_count + category_count
    return total_count, status_count, feed_count, category_count
end

return QueueService
