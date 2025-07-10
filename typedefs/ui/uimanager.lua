---@meta
---@module 'ui/uimanager'

-- This module manages widgets.
---@class UIManager
---@field show fun(self: UIManager, widget: table): nil Show a widget
---@field close fun(self: UIManager, widget: table): nil Close a widget
---@field forceRePaint fun(self: UIManager): nil Force screen repaint
---@field scheduleIn fun(self: UIManager, delay: number, callback: function): nil Schedule callback
---@field handleInput fun(self: UIManager): nil
---@field isWidgetShown fun(self: UIManager, widget: table): boolean
local UIManager = {}

return UIManager
