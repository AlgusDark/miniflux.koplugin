---@meta
---@module 'ui/widget/textwidget'

---@class TextWidgetOptions
---@field text string Text to display
---@field face? table Font face object (from Font:getFace())
---@field font? string Font name (e.g., "cfont", "smallinfofont")
---@field size? number Font size in points
---@field bold? boolean Whether text should be bold
---@field italic? boolean Whether text should be italic
---@field underline? boolean Whether text should be underlined
---@field color? number Text color (Blitbuffer color)
---@field fgcolor? number Foreground color (alias for color)
---@field bgcolor? number Background color
---@field alpha? number Alpha transparency (0.0 to 1.0)
---@field padding? number Padding around text
---@field max_width? number Maximum width for text wrapping
---@field height? number Fixed height for the widget
---@field valign? "top"|"center"|"bottom" Vertical alignment
---@field halign? "left"|"center"|"right" Horizontal alignment
---@field para_direction_rtl? boolean Whether text direction is right-to-left
---@field auto_para_direction? boolean Whether to auto-detect paragraph direction
---@field lang? string Language code for text rendering
---@field hold_callback? function Callback for hold gesture
---@field tap_callback? function Callback for tap gesture

---TextWidget for KOReader - A widget for displaying text with font and color options
---
---The TextWidget is a fundamental widget for displaying text in KOReader. It supports
---various font faces, sizes, colors, and text formatting options. It's used extensively
---throughout the UI for labels, titles, and text content.
---
---Features:
---- Font face and size selection
---- Text color and formatting
---- Bold and italic text support
---- Text alignment and positioning
---- Automatic dimension calculation
---- UTF-8 text support
---- Baseline alignment capabilities
---@class TextWidget : Widget
---@field text string Display text
---@field face table Font face object
---@field font string Font name
---@field size number Font size
---@field bold boolean Whether text is bold
---@field italic boolean Whether text is italic
---@field underline boolean Whether text is underlined
---@field color number Text color
---@field fgcolor number Foreground color
---@field bgcolor number Background color
---@field alpha number Alpha transparency
---@field padding number Padding around text
---@field max_width number Maximum width
---@field height number Fixed height
---@field valign "top"|"center"|"bottom" Vertical alignment
---@field halign "left"|"center"|"right" Horizontal alignment
---@field para_direction_rtl boolean RTL text direction
---@field auto_para_direction boolean Auto-detect direction
---@field lang string Language code
---@field hold_callback function Hold gesture callback
---@field tap_callback function Tap gesture callback
---@field dimen table Widget dimensions
---@field baseline number Text baseline position
---@field _bb table Blitbuffer for text rendering
---@field _text_rendered boolean Whether text has been rendered
---@field _height number Calculated height
---@field _width number Calculated width
local TextWidget = {}

---Initialize TextWidget with text and options
---@param self TextWidget
---@param options TextWidgetOptions
function TextWidget:init(options) end

---Get the width of the text
---@param self TextWidget
---@return number Text width in pixels
function TextWidget:getWidth() end

---Get the height of the text
---@param self TextWidget
---@return number Text height in pixels
function TextWidget:getHeight() end

---Get the text size (width and height)
---@param self TextWidget
---@return number, number Width and height in pixels
function TextWidget:getSize() end

---Get the baseline position of the text
---@param self TextWidget
---@return number Baseline position from top
function TextWidget:getBaseline() end

---Set the text content
---@param self TextWidget
---@param text string New text to display
function TextWidget:setText(text) end

---Get the current text content
---@param self TextWidget
---@return string Current text
function TextWidget:getText() end

---Set the font face
---@param self TextWidget
---@param face table Font face object
function TextWidget:setFace(face) end

---Update the widget with new text and options
---@param self TextWidget
---@param text string New text
---@param face? table New font face
---@param color? number New text color
function TextWidget:update(text, face, color) end

---Paint the text widget to a blitbuffer
---@param self TextWidget
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function TextWidget:paintTo(bb, x, y) end

---Free the widget's resources
---@param self TextWidget
function TextWidget:free() end

---Handle tap gesture
---@param self TextWidget
---@param arg table Gesture arguments
---@return boolean Whether gesture was handled
function TextWidget:onTap(arg) end

---Handle hold gesture
---@param self TextWidget
---@param arg table Gesture arguments
---@return boolean Whether gesture was handled
function TextWidget:onHold(arg) end

---Get text dimensions for given text and font
---@param text string Text to measure
---@param face table Font face
---@return number, number Width and height
function TextWidget.getTextSize(text, face) end

---Split text into lines for given width
---@param text string Text to split
---@param face table Font face
---@param width number Maximum width
---@return string[] Array of text lines
function TextWidget.splitText(text, face, width) end

---Check if text fits in given dimensions
---@param text string Text to check
---@param face table Font face
---@param width number Available width
---@param height number Available height
---@return boolean Whether text fits
function TextWidget.textFits(text, face, width, height) end

---Get font height for given font face
---@param face table Font face
---@return number Font height
function TextWidget.getFontHeight(face) end

---Truncate text to fit in given width
---@param text string Text to truncate
---@param face table Font face
---@param width number Available width
---@param ellipsis? string Ellipsis string (default: "…")
---@return string Truncated text
function TextWidget.truncateText(text, face, width, ellipsis) end

---Create new TextWidget instance
---@param self TextWidget
---@param options TextWidgetOptions
---@return TextWidget New instance
function TextWidget:new(options) end

---Extend TextWidget class
---@param self TextWidget
---@param options TextWidgetOptions
---@return TextWidget Extended class
function TextWidget:extend(options) end

return TextWidget
