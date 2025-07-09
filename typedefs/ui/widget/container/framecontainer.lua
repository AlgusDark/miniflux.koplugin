---@meta
---@module 'ui/widget/container/framecontainer'

---@class FrameContainerOptions : WidgetContainerOptions
---@field background? number Background color (Blitbuffer color)
---@field bordersize? number Border thickness in pixels (default: 2)
---@field padding? number Internal padding in pixels
---@field margin? number External margin in pixels
---@field radius? number Border radius for rounded corners
---@field color? number Border color (Blitbuffer color)
---@field width? number Fixed width for the container
---@field height? number Fixed height for the container
---@field show_parent? any Parent widget for showing dialogs
---@field focusable? boolean Whether container can receive focus
---@field focus_border_color? number Border color when focused
---@field focus_border_size? number Border size when focused
---@field invert? boolean Whether to invert colors
---@field dim? boolean Whether to dim the container
---@field alpha? number Alpha transparency (0.0 to 1.0)
---@field inner_bordersize? number Inner border thickness
---@field overlap_align? "left"|"center"|"right" Alignment for overlapping content
---@field allow_mirroring? boolean Whether to allow UI mirroring
---@field ignore_if_mirrored? boolean Whether to ignore if mirrored

---FrameContainer widget for KOReader - A container with frame/border styling
---
---The FrameContainer widget provides a container with customizable frame, border,
---and background styling. It's commonly used to create panels, dialog boxes, and
---other UI elements that need visual separation or emphasis.
---
---Features:
---- Customizable border size and color
---- Background color and transparency
---- Rounded corners with configurable radius
---- Padding and margin support
---- Frame styling options (solid, dashed, etc.)
---- Shadow effects
---- Automatic dimension calculation based on content
---@class FrameContainer : WidgetContainer
---@field background number Background color
---@field bordersize number Border thickness
---@field padding number Internal padding
---@field margin number External margin
---@field radius number Border radius
---@field color number Border color
---@field width number Container width
---@field height number Container height
---@field show_parent any Parent widget
---@field focusable boolean Can receive focus
---@field focus_border_color number Focused border color
---@field focus_border_size number Focused border size
---@field invert boolean Invert colors
---@field dim boolean Dim container
---@field alpha number Alpha transparency
---@field inner_bordersize number Inner border thickness
---@field overlap_align "left"|"center"|"right" Overlap alignment
---@field allow_mirroring boolean Allow UI mirroring
---@field ignore_if_mirrored boolean Ignore if mirrored
---@field dimen table Container dimensions
---@field _frame_bb table Frame blitbuffer
---@field _background_bb table Background blitbuffer
---@field _content_area table Content area dimensions
---@field _is_focused boolean Whether container is focused
local FrameContainer = {}

---Initialize FrameContainer with options
---@param self FrameContainer
---@param options? FrameContainerOptions
function FrameContainer:init(options) end

---Set background color
---@param self FrameContainer
---@param color number New background color
function FrameContainer:setBackground(color) end

---Get current background color
---@param self FrameContainer
---@return number Current background color
function FrameContainer:getBackground() end

---Set border size
---@param self FrameContainer
---@param size number New border size in pixels
function FrameContainer:setBorderSize(size) end

---Get current border size
---@param self FrameContainer
---@return number Current border size
function FrameContainer:getBorderSize() end

---Set border color
---@param self FrameContainer
---@param color number New border color
function FrameContainer:setBorderColor(color) end

---Get current border color
---@param self FrameContainer
---@return number Current border color
function FrameContainer:getBorderColor() end

---Set border radius for rounded corners
---@param self FrameContainer
---@param radius number New border radius
function FrameContainer:setRadius(radius) end

---Get current border radius
---@param self FrameContainer
---@return number Current border radius
function FrameContainer:getRadius() end

---Set padding
---@param self FrameContainer
---@param padding number New padding in pixels
function FrameContainer:setPadding(padding) end

---Get current padding
---@param self FrameContainer
---@return number Current padding
function FrameContainer:getPadding() end

---Set margin
---@param self FrameContainer
---@param margin number New margin in pixels
function FrameContainer:setMargin(margin) end

---Get current margin
---@param self FrameContainer
---@return number Current margin
function FrameContainer:getMargin() end

---Set focus state
---@param self FrameContainer
---@param focused boolean Whether container should be focused
function FrameContainer:setFocused(focused) end

---Check if container is focused
---@param self FrameContainer
---@return boolean Whether container is focused
function FrameContainer:isFocused() end

---Set alpha transparency
---@param self FrameContainer
---@param alpha number New alpha value (0.0 to 1.0)
function FrameContainer:setAlpha(alpha) end

---Get current alpha transparency
---@param self FrameContainer
---@return number Current alpha value
function FrameContainer:getAlpha() end

---Set dim state
---@param self FrameContainer
---@param dim boolean Whether container should be dimmed
function FrameContainer:setDim(dim) end

---Check if container is dimmed
---@param self FrameContainer
---@return boolean Whether container is dimmed
function FrameContainer:isDim() end

---Get content area dimensions (excluding border and padding)
---@param self FrameContainer
---@return table Content area dimensions
function FrameContainer:getContentArea() end

---Get frame dimensions (including border)
---@param self FrameContainer
---@return table Frame dimensions
function FrameContainer:getFrameSize() end

---Paint the frame container to blitbuffer
---@param self FrameContainer
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function FrameContainer:paintTo(bb, x, y) end

---Paint the frame border
---@param self FrameContainer
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function FrameContainer:paintBorder(bb, x, y) end

---Paint the background
---@param self FrameContainer
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function FrameContainer:paintBackground(bb, x, y) end

---Recalculate dimensions based on content
---@param self FrameContainer
function FrameContainer:_recalculateDimensions() end

---Handle focus event
---@param self FrameContainer
---@return boolean Whether event was handled
function FrameContainer:onFocus() end

---Handle unfocus event
---@param self FrameContainer
---@return boolean Whether event was handled
function FrameContainer:onUnfocus() end

---Free frame container resources
---@param self FrameContainer
function FrameContainer:free() end

---Update frame container appearance
---@param self FrameContainer
function FrameContainer:update() end

---Show frame container
---@param self FrameContainer
function FrameContainer:show() end

---Hide frame container
---@param self FrameContainer
function FrameContainer:hide() end

---Get container size
---@param self FrameContainer
---@return table Container dimensions
function FrameContainer:getSize() end

---Set container size
---@param self FrameContainer
---@param width number New width
---@param height number New height
function FrameContainer:setSize(width, height) end

---Refresh frame container display
---@param self FrameContainer
function FrameContainer:refresh() end

---Create new FrameContainer instance
---@param self FrameContainer
---@param options? FrameContainerOptions
---@return FrameContainer New instance
function FrameContainer:new(options) end

---Extend FrameContainer class
---@param self FrameContainer
---@param options? FrameContainerOptions
---@return FrameContainer Extended class
function FrameContainer:extend(options) end

return FrameContainer
