---@meta
---@module 'ui/widget/widget'

---@class WidgetOptions
---@field dimen? table Widget dimensions (Geom object)
---@field show_parent? any Parent widget for showing dialogs
---@field width? number Widget width
---@field height? number Widget height
---@field x? number X position
---@field y? number Y position

---Widget base class for KOReader - The foundation class for all UI widgets
---
---The Widget class is the base class for all other widgets in KOReader. It provides
---the fundamental interface that all widgets must implement, including size queries
---and painting capabilities. It extends EventListener to provide event handling.
---
---Core Functionality:
---- Widget class hierarchy and inheritance
---- Basic widget lifecycle (creation, initialization, destruction)
---- Size and dimension management
---- Paint-to-buffer interface for rendering
---- Event handling through EventListener
---- Metatable-based inheritance system
---
---All widgets in KOReader inherit from this base class and must implement:
---- getSize() - Return widget dimensions
---- paintTo() - Paint widget to a BlitBuffer
---@class Widget : EventListener
---@field dimen table Widget dimensions (Geom object with x, y, w, h)
---@field show_parent any Parent widget for showing dialogs
---@field width number Widget width
---@field height number Widget height
---@field x number X position
---@field y number Y position
---@field _init function|nil Base widget initialization function
---@field init function|nil Higher-level widget initialization function
local Widget = {}

---Create a widget subclass that inherits from this base class
---Sets up the metatable (prototype chain) without creating an instance
---@param self Widget
---@param subclass_prototype? table Subclass prototype table
---@return Widget Extended widget class
function Widget:extend(subclass_prototype) end

---Create an instance of a widget class
---This calls both _init() and init() methods if they exist
---@param self Widget
---@param o? table Options table for the new instance
---@return Widget New widget instance
function Widget:new(o) end

---Get the size of the widget
---@param self Widget
---@return table Widget dimensions (Geom object)
function Widget:getSize() end

---Paint the widget to a BlitBuffer
---This is the core rendering method that all widgets must implement
---@param self Widget
---@param bb table BlitBuffer to paint to
---@param x number X offset within the BlitBuffer
---@param y number Y offset within the BlitBuffer
function Widget:paintTo(bb, x, y) end

---Set widget dimensions
---@param self Widget
---@param dimen table New dimensions (Geom object)
function Widget:setDimen(dimen) end

---Get widget width
---@param self Widget
---@return number Widget width
function Widget:getWidth() end

---Get widget height
---@param self Widget
---@return number Widget height
function Widget:getHeight() end

---Set widget position
---@param self Widget
---@param x number New X position
---@param y number New Y position
function Widget:setPosition(x, y) end

---Get widget position
---@param self Widget
---@return number, number X and Y position
function Widget:getPosition() end

---Check if widget contains a point
---@param self Widget
---@param x number X coordinate
---@param y number Y coordinate
---@return boolean Whether point is within widget bounds
function Widget:containsPoint(x, y) end

---Move widget by offset
---@param self Widget
---@param dx number X offset
---@param dy number Y offset
function Widget:move(dx, dy) end

---Resize widget
---@param self Widget
---@param width number New width
---@param height number New height
function Widget:resize(width, height) end

---Free widget resources
---@param self Widget
function Widget:free() end

---Show widget
---@param self Widget
function Widget:show() end

---Hide widget
---@param self Widget
function Widget:hide() end

---Check if widget is visible
---@param self Widget
---@return boolean Whether widget is visible
function Widget:isVisible() end

---Refresh widget display
---@param self Widget
function Widget:refresh() end

---Update widget
---@param self Widget
function Widget:update() end

---Get widget type name
---@param self Widget
---@return string Widget type name
function Widget:getType() end

---Clone widget
---@param self Widget
---@return Widget Cloned widget
function Widget:clone() end

---Get widget bounds
---@param self Widget
---@return table Widget bounds (x, y, w, h)
function Widget:getBounds() end

---Set widget bounds
---@param self Widget
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
function Widget:setBounds(x, y, w, h) end

---Check if widget intersects with another widget
---@param self Widget
---@param other Widget Other widget to check
---@return boolean Whether widgets intersect
function Widget:intersects(other) end

---Get widget center point
---@param self Widget
---@return number, number Center X and Y coordinates
function Widget:getCenter() end

---Set widget center position
---@param self Widget
---@param x number Center X position
---@param y number Center Y position
function Widget:setCenter(x, y) end

return Widget
