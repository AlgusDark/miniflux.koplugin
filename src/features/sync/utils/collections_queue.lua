local lfs = require('libs/libkoreader-lfs')
local Files = require('shared/files')
local EntryEntity = require('domains/entries/entry_entity')

-- **Collections Queue** - Unified queue utility for feeds and categories
--
-- Replaces duplicate feed_queue.lua and category_queue.lua with single
-- parameterized implementation. Feeds and categories are both collections
-- of entries that need identical queue management for offline operations.
--
-- Usage:
--   local feed_queue = CollectionsQueue:new('feed')
--   local category_queue = CollectionsQueue:new('category')
--   feed_queue:enqueue(feed_id, 'mark_all_read')
--   category_queue:enqueue(category_id, 'mark_all_read')
---@class CollectionsQueue
---@field collection_type string Type of collection ('feed' or 'category')
local CollectionsQueue = {}

---Create a new CollectionsQueue instance
---@param collection_type string Type of collection ('feed' or 'category')
---@return CollectionsQueue
function CollectionsQueue:new(collection_type)
    if collection_type ~= 'feed' and collection_type ~= 'category' then
        error('Invalid collection_type: must be "feed" or "category"')
    end

    local instance = {
        collection_type = collection_type,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Get the path to the collection queue file
---@return string file_path
function CollectionsQueue:getQueueFilePath()
    local miniflux_dir = EntryEntity.getDownloadDir()
    return miniflux_dir .. self.collection_type .. '_queue.lua'
end

---Load the collection queue from disk
---@return table Queue data (collection_id -> {operation, timestamp})
function CollectionsQueue:load()
    local queue_file = self:getQueueFilePath()

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

---Save the collection queue to disk
---@param queue table Queue data to save
---@return boolean success
function CollectionsQueue:save(queue)
    local queue_file = self:getQueueFilePath()

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
    for collection_id, opts in pairs(queue) do
        queue_content = queue_content
            .. string.format(
                '  [%d] = {\n    operation = %q,\n    timestamp = %d\n  },\n',
                collection_id,
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

---Add a collection operation to the queue
---@param collection_id number Collection ID (feed_id or category_id)
---@param operation string Operation type (e.g., "mark_all_read")
---@return boolean success
function CollectionsQueue:enqueue(collection_id, operation)
    local queue = self:load()
    queue[collection_id] = {
        operation = operation,
        timestamp = os.time(),
    }
    return self:save(queue)
end

---Remove a collection from the queue
---@param collection_id number Collection ID to remove
---@return boolean success
function CollectionsQueue:remove(collection_id)
    local queue = self:load()
    queue[collection_id] = nil
    return self:save(queue)
end

---Clear the entire collection queue
---@return boolean success
function CollectionsQueue:clear()
    local queue_file = self:getQueueFilePath()

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
function CollectionsQueue:count()
    local queue = self:load()
    local count = 0
    for _ in pairs(queue) do
        count = count + 1
    end
    return count
end

-- =============================================================================
-- STATIC INTERFACE COMPATIBILITY (for existing code patterns)
-- =============================================================================

-- Some existing code might use static methods. Provide compatibility layer.

---Create a feed queue instance
---@return CollectionsQueue
function CollectionsQueue.createFeedQueue()
    return CollectionsQueue:new('feed')
end

---Create a category queue instance
---@return CollectionsQueue
function CollectionsQueue.createCategoryQueue()
    return CollectionsQueue:new('category')
end

return CollectionsQueue
