--[[--
EmmyLua type definitions for MultiInputDialog

@meta koplugin.miniflux.typedefs.MultiInputDialog
--]] --

---@class MultiInputDialog
---@field title string Dialog title
---@field fields table[] Input fields
---@field buttons table[][] Dialog buttons
---@field getFields fun(self: MultiInputDialog): string[] Get field values
---@field new fun(o: table): MultiInputDialog Create new multi-input dialog
