---@meta
---@module 'ui/uimanager'

-- UIManager - The central UI widget management system for KOReader
--
-- UIManager is KOReader's core UI orchestrator that handles:
---- Widget lifecycle management (show, close, stack management)
---- Screen refresh and painting coordination with e-ink optimization
---- Task scheduling and timing for background operations
---- Input event handling and gesture processing
---- Standby/wake management for power efficiency
---- Screen rotation and display mode transitions
--
-- As a singleton, UIManager coordinates all UI interactions and ensures proper
-- e-ink display handling, making it the foundation of KOReader's user interface.
---@class Screen
---@field getWidth fun(self: Screen): number Get screen width
---@field getHeight fun(self: Screen): number Get screen height

---@class UIManager
---@field screen Screen Screen interface
---@field show fun(self: UIManager, widget: table): nil Show a widget
---@field close fun(self: UIManager, widget: table): nil Close a widget
---@field forceRePaint fun(self: UIManager): nil Force screen repaint
---@field scheduleIn fun(self: UIManager, delay: number, callback: function): nil Schedule callback
---@field nextTick fun(self: UIManager, action: function, ...): nil Schedule for next UI tick
---@field unschedule fun(self: UIManager, action: function): nil Remove scheduled callback
---@field handleInput fun(self: UIManager): nil Handle input events
---@field isWidgetShown fun(self: UIManager, widget: table): boolean Check if widget is shown
---@field preventStandby fun(self: UIManager): nil Prevent device standby/sleep
---@field allowStandby fun(self: UIManager): nil Allow device standby/sleep
---@field restartKOReader fun(self: UIManager): nil Restart KOReader application
local UIManager = {}

return UIManager
