--[[--
EmmyLua type definitions for LuaSettings

@meta koplugin.miniflux.typedefs.LuaSettings
--]] --

---@class LuaSettings
---@field open fun(file_path: string): LuaSettings Open settings file
---@field extend fun(o: table<string, any>): LuaSettings Extend settings
---@field readSetting fun(self: LuaSettings, key: string, default?: any): any Reads a setting, optionally initializing it to a default.
---@field saveSetting fun(self: LuaSettings, key: string, value: any): nil Save a setting value
---@field toggle fun(self: LuaSettings, key: string): LuaSettings Toggles a boolean setting
---@field flush fun(self: LuaSettings): nil Flush settings to disk
---@field clear fun(self: LuaSettings): nil Clear all settings
