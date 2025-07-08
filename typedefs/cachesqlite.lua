---@meta
---@module "cachesqlite"

---@class CacheSQLite
---@field size number Max storage space in bytes
---@field db_path string Database file path (use ":memory:" for in-memory database)
---@field codec string Compression codec from Persist (default: "zstd")
---@field auto_close boolean Whether to automatically close DB connection after each operation (default: true)
---@field current_size number Current cache size in bytes (tracked automatically)
local CacheSQLite = {}

---@class CacheSQLiteConfig
---@field size number Max storage space in bytes
---@field db_path string Database file path
---@field codec? string Compression codec (default: "zstd")
---@field auto_close? boolean Auto-close DB connections (default: true)

---Create a new CacheSQLite instance
---@param config CacheSQLiteConfig Configuration options
---@return CacheSQLite
function CacheSQLite:new(config) end

---Initialize the cache (called automatically on creation if init is set)
---@return nil
function CacheSQLite:init() end

---Check if cache is connected to database
---@return boolean connected
function CacheSQLite:isConnected() end

---Insert an object into the cache
---@param key string Cache key
---@param object any Object to cache (will be serialized)
---@return boolean success, number size Size of stored object in bytes
function CacheSQLite:insert(key, object) end

---Retrieve an object and update its access time (for LRU)
---@param key string Cache key
---@return any|nil object Retrieved object or nil if not found
function CacheSQLite:check(key) end

---Retrieve an object without updating access time
---@param key string Cache key  
---@return any|nil object Retrieved object or nil if not found
function CacheSQLite:get(key) end

---Delete an object from cache
---@param key string Cache key
---@return boolean success
function CacheSQLite:delete(key) end

---Clear all objects from cache
---@return boolean success
function CacheSQLite:clear() end

---Check if the cache will accept an object of given size
---@param size number Object size in bytes
---@return boolean will_accept
function CacheSQLite:willAccept(size) end

---Serialize an object using the configured codec
---@param object any Object to serialize
---@return string serialized_data, number size
function CacheSQLite:serialize(object) end

---Deserialize data using the configured codec
---@param data string Serialized data
---@return any object Deserialized object
function CacheSQLite:deserialize(data) end

return CacheSQLite