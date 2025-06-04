--[[--
Miniflux debug logging module

@module koplugin.miniflux.debug
--]]--

local lfs = require("libs/libkoreader-lfs")

local MinifluxDebug = {}

function MinifluxDebug:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    return o
end

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

function MinifluxDebug:clearLog()
    local file = io.open(self.debug_file, "w")
    if file then
        file:close()
    end
end

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

function MinifluxDebug:info(message)
    self:log("INFO", message)
end

function MinifluxDebug:warn(message)
    self:log("WARN", message)
end

function MinifluxDebug:error(message)
    self:log("ERROR", message)
end

function MinifluxDebug:debug(message)
    self:log("DEBUG", message)
end

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