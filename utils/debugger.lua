local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

-- **Debugger** - Simple logging utility for debugging issues in KOReader
-- environment. Logs are written to debug.log in the miniflux data directory.
local Debugger = {}

-- Initialize log directory and file path
local MINIFLUX_DATA_DIR = DataStorage:getDataDir() .. "/miniflux"
local LOG_FILE_PATH = MINIFLUX_DATA_DIR .. "/debug.log"
local MAX_LOG_SIZE = 1024 * 1024 -- 1MB max log size

-- Ensure miniflux data directory exists
local function ensureDataDir()
    if lfs.attributes(MINIFLUX_DATA_DIR, "mode") ~= "directory" then
        lfs.mkdir(MINIFLUX_DATA_DIR)
    end
end

-- Get current timestamp for log entries
local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Write log entry to file
local function writeLog(level, message)
    ensureDataDir()

    -- Check log file size and rotate if needed
    local file_size = lfs.attributes(LOG_FILE_PATH, "size") or 0
    if file_size > MAX_LOG_SIZE then
        -- Simple rotation: rename current to .old
        local old_log = LOG_FILE_PATH .. ".old"
        os.remove(old_log)                -- Remove old backup
        os.rename(LOG_FILE_PATH, old_log) -- Move current to backup
    end

    local file = io.open(LOG_FILE_PATH, "a")
    if file then
        file:write(string.format("[%s] [%s] %s\n", getTimestamp(), level, tostring(message)))
        file:close()
    end
end

---Log an info message
---@param message string|any Message to log
function Debugger.info(message)
    writeLog("INFO", message)
end

---Log an error message
---@param message string|any Message to log
function Debugger.error(message)
    writeLog("ERROR", message)
end

---Log a debug message
---@param message string|any Message to log
function Debugger.debug(message)
    writeLog("DEBUG", message)
end

---Log a warning message
---@param message string|any Message to log
function Debugger.warn(message)
    writeLog("WARN", message)
end

---Log function entry with optional parameters
---@param func_name string Function name
---@param params string|nil Optional parameters info
function Debugger.enter(func_name, params)
    local msg = "ENTER " .. func_name
    if params then
        msg = msg .. " - " .. tostring(params)
    end
    writeLog("TRACE", msg)
end

---Log function exit with optional result info
---@param func_name string Function name
---@param result string|nil Optional result info
function Debugger.exit(func_name, result)
    local msg = "EXIT " .. func_name
    if result then
        msg = msg .. " - " .. tostring(result)
    end
    writeLog("TRACE", msg)
end

---Clear the debug log file
function Debugger.clear()
    ensureDataDir()
    local file = io.open(LOG_FILE_PATH, "w")
    if file then
        file:close()
    end
end

---Get the path to the debug log file
---@return string Log file path
function Debugger.getLogPath()
    return LOG_FILE_PATH
end

return Debugger
