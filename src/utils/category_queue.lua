local lfs = require('libs/libkoreader-lfs')
local Files = require('utils/files')
local EntryEntity = require('entities/entry_entity')

local CategoryQueue = {}

---Get the path to the category queue file
---@return string file_path
function CategoryQueue.getQueueFilePath()
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. 'category_queue.lua'
end

---Load the category queue from disk
---@return table Queue data (category_id -> {operation, timestamp})
function CategoryQueue.load()
    local queue_file = CategoryQueue.getQueueFilePath()

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

---Save the category queue to disk
---@param queue table Queue data to save
---@return boolean success
function CategoryQueue.save(queue)
    local queue_file = CategoryQueue.getQueueFilePath()

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
    for category_id, opts in pairs(queue) do
        queue_content = queue_content
            .. string.format(
                '  [%d] = {\n    operation = %q,\n    timestamp = %d\n  },\n',
                category_id,
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

---Add a category operation to the queue
---@param category_id number Category ID
---@param operation string Operation type (e.g., "mark_all_read')
---@return boolean success
function CategoryQueue.enqueue(category_id, operation)
    local queue = CategoryQueue.load()
    queue[category_id] = {
        operation = operation,
        timestamp = os.time(),
    }
    return CategoryQueue.save(queue)
end

---Remove a category from the queue
---@param category_id number Category ID to remove
---@return boolean success
function CategoryQueue.remove(category_id)
    local queue = CategoryQueue.load()
    queue[category_id] = nil
    return CategoryQueue.save(queue)
end

---Clear the entire category queue
---@return boolean success
function CategoryQueue.clear()
    local queue_file = CategoryQueue.getQueueFilePath()

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
function CategoryQueue.count()
    local queue = CategoryQueue.load()
    local count = 0
    for i in pairs(queue) do
        count = count + 1
    end
    return count
end

return CategoryQueue
