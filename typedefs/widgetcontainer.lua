--[[--
EmmyLua type definitions for WidgetContainer

@meta koplugin.miniflux.typedefs.WidgetContainer
--]] --

---@class WidgetContainerOptions
---@field name? string Widget name

---@class WidgetContainer
---@field name string Widget name
---@field ui table UI manager reference
---@field path string Plugin path
---@field extend fun(self: WidgetContainer, o: table): WidgetContainer Extend widget container
