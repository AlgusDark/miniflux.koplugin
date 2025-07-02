--[[--
EmmyLua type definitions for DocSettings

@module koplugin.miniflux.typedefs.DocSettings
--]]

---@class DocSettings
---@field open fun(file_path: string): DocSettings Open DocSettings for a file
---@field hasSidecarFile fun(file_path: string): boolean Check if sidecar file exists (static method)
---@field readSetting fun(self: DocSettings, key: string, default?: any): any Read a setting value
---@field saveSetting fun(self: DocSettings, key: string, value: any): nil Save a setting value
---@field flush fun(self: DocSettings): string|nil Flush settings to disk, returns result or nil
---@field close fun(self: DocSettings): nil Close DocSettings instance
