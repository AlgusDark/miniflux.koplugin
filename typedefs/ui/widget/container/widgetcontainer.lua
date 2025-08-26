---@meta
---@module 'ui/widget/container/widgetcontainer'

---@class WidgetContainerOptions
---@field name? string Widget name

--[[--
WidgetContainer is a container for one or multiple Widgets. It is the base
class for all the container widgets.

Child widgets are stored in WidgetContainer as conventional array items:

    WidgetContainer:new{
        ChildWidgetFoo:new{},
        ChildWidgetBar:new{},
        ...
    }

It handles event propagation and painting (with different alignments) for its children.
]]
---@class WidgetContainer
---@field name string Widget name
---@field ui table UI manager reference
---@field path string Plugin path
local WidgetContainer = {}

---@param o table
function WidgetContainer:extend(o) end

---@param o table
function WidgetContainer:new(o) end

return WidgetContainer
