--[[--
EmmyLua type definitions for LuaSettings

@module koplugin.miniflux.typedefs.LuaSettings
--]]--

---@class LuaSettings
---@field open fun(file_path: string): LuaSettings Open settings file
---@field wrap fun(data: table<string, any>): LuaSettings Wrap data as settings
---@field extend fun(o: table<string, any>): LuaSettings Extend settings
---@field readSetting fun(self: LuaSettings, key: string): any Read a setting value
---@field saveSetting fun(self: LuaSettings, key: string, value: any): nil Save a setting value
---@field flush fun(self: LuaSettings): nil Flush settings to disk
---@field clear fun(self: LuaSettings): nil Clear all settings 