---@meta
---@module "cachesqlite"

---@class CacheSQLiteConfig
---@field size number Max storage space in bytes
---@field slots? number LRU slot count (used by newsdownloader pattern)
---@field db_path string Database file path (use ":memory:" for in-memory database)
---@field codec? string Compression codec from Persist (default: "zstd")
---@field auto_close? boolean Auto-close DB connections (default: true)
---@field init? boolean Whether to call init() automatically (default: false)

---SQLite-based cache implementation for KOReader
---
---Provides an interface similar to the Cache module but uses SQLite for persistence.
---Features compression, LRU eviction, and automatic size management.
---
---Example usage:
---    local CacheSQLite = require("cachesqlite")
---    local cache = CacheSQLite:new{
---        size = 1024 * 1024 * 10, -- 10 MB
---        slots = 500,             -- LRU slot count
---        db_path = "/path/to/cache.db",
---    }
---    cache:insert("key", {value = "data"})
---    local data = cache:check("key")
---@class CacheSQLite
---@field size number Max storage space in bytes
---@field slots number LRU slot count
---@field db_path string Database file path (use ":memory:" for in-memory database)
---@field codec string Compression codec from Persist (default: "zstd")
---@field auto_close boolean Whether to automatically close DB connection after each operation (default: true)
---@field current_size number Current cache size in bytes (tracked automatically)
---@field db any SQLite database connection
---@field _persist table Persist codec instance
local CacheSQLite = {}

---Create a new CacheSQLite instance
---@param config CacheSQLiteConfig Configuration options
---@return CacheSQLite
function CacheSQLite:new(config) end

---Initialize the cache database and tables
---Called automatically if init is set in config
function CacheSQLite:init() end

---Open the SQLite database connection
---This is normally done internally, but can be called manually if needed
function CacheSQLite:openDB() end

---Close the SQLite database connection
---This is normally done internally, but can be called manually if needed
---@param explicit? boolean When auto_close is false, this must be set to true to close the DB
function CacheSQLite:closeDB(explicit) end

---Check if cache is connected to database
---@return boolean connected True if database connection is open
function CacheSQLite:isConnected() end

---Insert an object into the cache
---Automatically handles LRU eviction if cache is full
---@param key string Cache key
---@param object any Object to cache (will be serialized and compressed)
---@return boolean success True if insertion succeeded
---@return number size Size of stored object in bytes
function CacheSQLite:insert(key, object) end

---Retrieve an object and update its access time (for LRU)
---@param key string Cache key
---@return any|nil object Retrieved object or nil if not found
function CacheSQLite:check(key) end

---Retrieve an object without updating access time
---@param key string Cache key
---@return any|nil object Retrieved object or nil if not found
function CacheSQLite:get(key) end

---Remove an object from cache
---@param key string Cache key
function CacheSQLite:remove(key) end

---Clear all objects from cache
function CacheSQLite:clear() end

---Check if the cache will accept an object of given size
---Only allows a single object to fill 50% of the cache
---@param size number Object size in bytes
---@return boolean will_accept True if object size is acceptable
function CacheSQLite:willAccept(size) end

return CacheSQLite
