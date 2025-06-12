--[[--
Miniflux debug logging module

@module koplugin.miniflux.debug
--]]--

local lfs = require("libs/libkoreader-lfs")

---@alias LogLevel "DEBUG"|"INFO"|"WARN"|"ERROR"

---@class MinifluxDebug
---@field settings SettingsManager Settings manager instance
---@field debug_file string Path to the debug log file
local MinifluxDebug = {}

---Create a new debug instance
---@param o? table Optional initialization table
---@return MinifluxDebug
function MinifluxDebug:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    return o
end

---Initialize the debug logging system
---@param settings SettingsManager Settings manager instance
---@param plugin_path? string Plugin path (currently unused)
---@return nil
function MinifluxDebug:init(settings, plugin_path)
    self.settings = settings
    
    -- Set up debug log file path in DataStorage directory
    local DataStorage = require("datastorage")
    self.debug_file = DataStorage:getDataDir() .. "/miniflux_debug.log"
    
    -- Clear debug log on startup
    self:clearLog()
    
    -- Log startup
    if self.settings:getDebugLogging() then
        self:log("DEBUG", "Miniflux debug logging initialized")
    end
end

---Clear the debug log file
---@return nil
function MinifluxDebug:clearLog()
    local file = io.open(self.debug_file, "w")
    if file then
        file:close()
    end
end

---Write a log entry to the debug file
---@param level LogLevel The log level
---@param message string The log message
---@return nil
function MinifluxDebug:log(level, message)
    if not self.settings or not self.settings:getDebugLogging() then
        return
    end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("[%s] %s: %s\n", timestamp, level, message)
    
    local file = io.open(self.debug_file, "a")
    if file then
        file:write(log_line)
        file:close()
    end
end

---Log an info level message
---@param message string The log message
---@return nil
function MinifluxDebug:info(message)
    self:log("INFO", message)
end

---Log a warning level message
---@param message string The log message
---@return nil
function MinifluxDebug:warn(message)
    self:log("WARN", message)
end

---Log an error level message
---@param message string The log message
---@return nil
function MinifluxDebug:error(message)
    self:log("ERROR", message)
end

---Log a debug level message
---@param message string The log message
---@return nil
function MinifluxDebug:debug(message)
    self:log("DEBUG", message)
end

---Get the contents of the debug log
---@return string The debug log content
function MinifluxDebug:getLogContent()
    local file = io.open(self.debug_file, "r")
    if not file then
        return "No debug log found"
    end
    
    local content = file:read("*all")
    file:close()
    
    if content == "" then
        return "Debug log is empty"
    end
    
    return content
end

return MinifluxDebug 