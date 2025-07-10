---@meta
---@module 'ui/widget/verticalgroup'

---@class VerticalGroupOptions
---@field align? "top"|"center"|"bottom" Vertical alignment of children (default: "top")
---@field spacing? number Spacing between child widgets in pixels
---@field width? number Fixed width for the group
---@field height? number Fixed height for the group
---@field padding? number Internal padding
---@field margin? number External margin
---@field background? number Background color
---@field bordersize? number Border thickness
---@field radius? number Border radius
---@field allow_mirroring? boolean Whether to allow UI mirroring
---@field ignore_if_mirrored? boolean Whether to ignore this widget if mirrored

---VerticalGroup widget for KOReader - A layout container that arranges widgets vertically
---
---The VerticalGroup widget is a fundamental layout container that stacks child widgets
---vertically. It automatically calculates the total height based on its children and
---provides vertical alignment options.
---
---Features:
---- Automatic height calculation based on children
---- Vertical alignment options (top, center, bottom)
---- Spacing between child widgets
---- Support for flexible and fixed sizing
---- Proper child widget management
---- Dimension recalculation on content changes
---@class VerticalGroup : WidgetContainer
---@field align "top"|"center"|"bottom" Vertical alignment
---@field spacing number Spacing between children
---@field width number Group width
---@field height number Group height
---@field padding number Internal padding
---@field margin number External margin
---@field background number Background color
---@field bordersize number Border thickness
---@field radius number Border radius
---@field allow_mirroring boolean Allow UI mirroring
---@field ignore_if_mirrored boolean Ignore if mirrored
---@field dimen table Widget dimensions
---@field _children_heights number[] Heights of child widgets
---@field _total_height number Total calculated height
---@field _max_width number Maximum width among children
local VerticalGroup = {}

---Initialize VerticalGroup with options
---@param self VerticalGroup
---@param options? VerticalGroupOptions
function VerticalGroup:init(options) end

---Add a widget to the group
---@param self VerticalGroup
---@param widget any Widget to add
---@param index? number Position to insert at (default: end)
function VerticalGroup:addWidget(widget, index) end

---Remove a widget from the group
---@param self VerticalGroup
---@param widget any Widget to remove
---@return boolean Whether widget was found and removed
function VerticalGroup:removeWidget(widget) end

---Remove widget at specific index
---@param self VerticalGroup
---@param index number Index of widget to remove (1-based)
---@return any|nil Removed widget or nil if index invalid
function VerticalGroup:removeWidgetAt(index) end

---Clear all widgets from the group
---@param self VerticalGroup
function VerticalGroup:clear() end

---Get number of child widgets
---@param self VerticalGroup
---@return number Number of children
function VerticalGroup:getChildCount() end

---Get child widget at index
---@param self VerticalGroup
---@param index number Index of child (1-based)
---@return any|nil Child widget or nil if index invalid
function VerticalGroup:getChildAt(index) end

---Get all child widgets
---@param self VerticalGroup
---@return any[] Array of child widgets
function VerticalGroup:getChildren() end

---Set vertical alignment for children
---@param self VerticalGroup
---@param align "top"|"center"|"bottom" New alignment
function VerticalGroup:setAlignment(align) end

---Get current vertical alignment
---@param self VerticalGroup
---@return "top"|"center"|"bottom" Current alignment
function VerticalGroup:getAlignment() end

---Set spacing between children
---@param self VerticalGroup
---@param spacing number New spacing in pixels
function VerticalGroup:setSpacing(spacing) end

---Get current spacing
---@param self VerticalGroup
---@return number Current spacing in pixels
function VerticalGroup:getSpacing() end

---Recalculate dimensions based on children
---@param self VerticalGroup
function VerticalGroup:_recalculateDimensions() end

---Get total height of all children plus spacing
---@param self VerticalGroup
---@return number Total height
function VerticalGroup:getContentHeight() end

---Get maximum width among all children
---@param self VerticalGroup
---@return number Maximum width
function VerticalGroup:getContentWidth() end

---Paint the group and its children to blitbuffer
---@param self VerticalGroup
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function VerticalGroup:paintTo(bb, x, y) end

---Free all child widgets and resources
---@param self VerticalGroup
function VerticalGroup:free() end

---Update group layout
---@param self VerticalGroup
function VerticalGroup:update() end

---Get size of the group
---@param self VerticalGroup
---@return table Group dimensions
function VerticalGroup:getSize() end

---Set size of the group
---@param self VerticalGroup
---@param width number New width
---@param height number New height
function VerticalGroup:setSize(width, height) end

---Check if group is empty
---@param self VerticalGroup
---@return boolean Whether group has no children
function VerticalGroup:isEmpty() end

---Insert widget at specific position
---@param self VerticalGroup
---@param widget any Widget to insert
---@param index number Position to insert at (1-based)
function VerticalGroup:insertWidget(widget, index) end

---Replace widget at specific position
---@param self VerticalGroup
---@param index number Position to replace (1-based)
---@param widget any New widget
---@return any|nil Previous widget or nil if index invalid
function VerticalGroup:replaceWidget(index, widget) end

---Move widget to new position
---@param self VerticalGroup
---@param from_index number Current position (1-based)
---@param to_index number New position (1-based)
---@return boolean Whether move was successful
function VerticalGroup:moveWidget(from_index, to_index) end

---Find index of widget
---@param self VerticalGroup
---@param widget any Widget to find
---@return number|nil Index of widget or nil if not found
function VerticalGroup:findWidget(widget) end

---Show all child widgets
---@param self VerticalGroup
function VerticalGroup:show() end

---Hide all child widgets
---@param self VerticalGroup
function VerticalGroup:hide() end

---Create new VerticalGroup instance
---@param self VerticalGroup
---@param options? VerticalGroupOptions
---@return VerticalGroup New instance
function VerticalGroup:new(options) end

---Extend VerticalGroup class
---@param self VerticalGroup
---@param options? VerticalGroupOptions
---@return VerticalGroup Extended class
function VerticalGroup:extend(options) end

return VerticalGroup
