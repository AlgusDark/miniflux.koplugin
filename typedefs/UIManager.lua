--[[--
EmmyLua type definitions for UIManager

@module koplugin.miniflux.typedefs.UIManager
--]]--

---@class UIManager
---@field show fun(widget: table): nil Show a widget
---@field close fun(widget: table): nil Close a widget
---@field forceRePaint fun(): nil Force screen repaint
---@field scheduleIn fun(delay: number, callback: function): nil Schedule callback 