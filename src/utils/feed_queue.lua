local lfs = require('libs/libkoreader-lfs')
local Files = require('utils/files')
local EntryEntity = require('entities/entry_entity')

local FeedQueue = {}

---Get the path to the feed queue file
---@return string file_path
function FeedQueue.getQueueFilePath()
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. 'feed_queue.lua'
end

---Load the feed queue from disk
---@return table Queue data (feed_id -> {operation, timestamp})
function FeedQueue.load()
    local queue_file = FeedQueue.getQueueFilePath()

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

---Save the feed queue to disk
---@param queue table Queue data to save
---@return boolean success
function FeedQueue.save(queue)
    local queue_file = FeedQueue.getQueueFilePath()

    -- Count entries in queue
    local count = 0
    for _ in pairs(queue) do
        count = count + 1
    end

    -- If queue is empty, delete the file instead of writing empty table
    if count == 0 then
        local file_exists = lfs.attributes(queue_file, 'mode') == 'file'
        if file_exists then
            local success = os.remove(queue_file)
            return success ~= nil
        else
            return true -- File doesn't exist, nothing to delete
        end
    end

    -- Ensure miniflux directory exists
    local miniflux_dir = queue_file:match('(.+)/[^/]+$')
    local success, _err = Files.createDirectory(miniflux_dir)
    if not success then
        return false
    end

    -- Convert queue table to Lua code
    local queue_content = 'return {\n'
    for feed_id, opts in pairs(queue) do
        queue_content = queue_content
            .. string.format(
                '  [%d] = {\n    operation = %q,\n    timestamp = %d\n  },\n',
                feed_id,
                opts.operation,
                opts.timestamp
            )
    end
    queue_content = queue_content .. '}\n'

    -- Write to file
    local file = io.open(queue_file, 'w')
    if not file then
        return false
    end

    local write_success = file:write(queue_content)
    file:close()

    if not write_success then
        return false
    end

    return true
end

---Add a feed operation to the queue
---@param feed_id number Feed ID
---@param operation string Operation type (e.g., "mark_all_read')
---@return boolean success
function FeedQueue.enqueue(feed_id, operation)
    local queue = FeedQueue.load()
    queue[feed_id] = {
        operation = operation,
        timestamp = os.time(),
    }
    return FeedQueue.save(queue)
end

---Remove a feed from the queue
---@param feed_id number Feed ID to remove
---@return boolean success
function FeedQueue.remove(feed_id)
    local queue = FeedQueue.load()
    queue[feed_id] = nil
    return FeedQueue.save(queue)
end

---Clear the entire feed queue
---@return boolean success
function FeedQueue.clear()
    local queue_file = FeedQueue.getQueueFilePath()

    -- Check if file exists before trying to remove it
    local file_exists = lfs.attributes(queue_file, 'mode') == 'file'

    if not file_exists then
        return true -- File doesn't exist, so it's already "cleared"
    end

    -- Remove the queue file
    local success = os.remove(queue_file)
    return success ~= nil
end

---Count items in the queue
---@return number count
function FeedQueue.count()
    local queue = FeedQueue.load()
    local count = 0
    for i in pairs(queue) do
        count = count + 1
    end
    return count
end

return FeedQueue
