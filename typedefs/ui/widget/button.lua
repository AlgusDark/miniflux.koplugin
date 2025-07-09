---@meta
---@module 'ui/widget/button'

---@class ButtonOptions : InputContainerOptions
---@field text? string Button text to display
---@field icon? string Icon identifier for the button
---@field icon_width? number Width of the icon
---@field icon_height? number Height of the icon
---@field callback? function Callback when button is tapped
---@field hold_callback? function Callback when button is held
---@field enabled? boolean Whether button is enabled (default: true)
---@field show_parent? any Parent widget for showing dialogs
---@field width? number Fixed width for the button
---@field height? number Fixed height for the button
---@field padding? number Internal padding
---@field margin? number External margin
---@field bordersize? number Border thickness
---@field radius? number Border radius for rounded corners
---@field background? number Background color
---@field color? number Text color
---@field text_font_face? string Font face for text
---@field text_font_size? number Font size for text
---@field text_font_bold? boolean Whether text should be bold
---@field preselect? boolean Whether button starts selected
---@field vsync? boolean Whether to sync with vsync
---@field readonly? boolean Whether button is read-only
---@field align? "left"|"center"|"right" Text alignment
---@field max_width? number Maximum width
---@field button_frame_color? number Color for button frame
---@field button_frame_width? number Width of button frame
---@field text_func? function Function to generate button text
---@field icon_func? function Function to generate button icon

---Button widget for KOReader - An interactive button with text and icon support
---
---The Button widget provides an interactive button with customizable appearance,
---text, icons, and callbacks. It extends InputContainer to handle touch gestures
---and provides visual feedback for user interactions.
---
---Features:
---- Text and icon display
---- Tap and hold callbacks
---- Visual feedback (enabled/disabled states)
---- Customizable appearance (borders, colors, padding)
---- Keyboard navigation support
---- Touch gesture handling
---- Flexible sizing options
---@class Button : InputContainer
---@field text string Button text
---@field icon string Icon identifier
---@field icon_width number Icon width
---@field icon_height number Icon height
---@field callback function Tap callback
---@field hold_callback function Hold callback
---@field enabled boolean Whether button is enabled
---@field show_parent any Parent widget
---@field width number Button width
---@field height number Button height
---@field padding number Internal padding
---@field margin number External margin
---@field bordersize number Border thickness
---@field radius number Border radius
---@field background number Background color
---@field color number Text color
---@field text_font_face string Font face
---@field text_font_size number Font size
---@field text_font_bold boolean Bold text
---@field preselect boolean Initial selection state
---@field vsync boolean VSync enabled
---@field readonly boolean Read-only state
---@field align "left"|"center"|"right" Text alignment
---@field max_width number Maximum width
---@field button_frame_color number Frame color
---@field button_frame_width number Frame width
---@field text_func function Text generation function
---@field icon_func function Icon generation function
---@field image any Button image widget
---@field label_widget any Button label widget
---@field frame any Button frame widget
---@field dimen table Button dimensions
---@field _text_rendered boolean Whether text has been rendered
---@field _enabled_state boolean Current enabled state
local Button = {}

---Initialize Button with options
---@param self Button
---@param options ButtonOptions
function Button:init(options) end

---Set button text
---@param self Button
---@param text string New text for the button
function Button:setText(text) end

---Get current button text
---@param self Button
---@return string Current button text
function Button:getText() end

---Set button icon
---@param self Button
---@param icon string Icon identifier
function Button:setIcon(icon) end

---Get current button icon
---@param self Button
---@return string Current icon identifier
function Button:getIcon() end

---Enable or disable the button
---@param self Button
---@param enabled boolean Whether button should be enabled
function Button:setEnabled(enabled) end

---Check if button is enabled
---@param self Button
---@return boolean Whether button is enabled
function Button:isEnabled() end

---Set button callback
---@param self Button
---@param callback function New callback function
function Button:setCallback(callback) end

---Set hold callback
---@param self Button
---@param callback function New hold callback function
function Button:setHoldCallback(callback) end

---Update button appearance
---@param self Button
function Button:refresh() end

---Handle tap gesture
---@param self Button
---@param arg table Gesture arguments
---@return boolean Whether gesture was handled
function Button:onTap(arg) end

---Handle hold gesture
---@param self Button
---@param arg table Gesture arguments
---@return boolean Whether gesture was handled
function Button:onHold(arg) end

---Handle tap select event
---@param self Button
---@return boolean Whether event was handled
function Button:onTapSelect() end

---Handle hold select event
---@param self Button
---@return boolean Whether event was handled
function Button:onHoldSelect() end

---Handle focus event
---@param self Button
---@return boolean Whether event was handled
function Button:onFocus() end

---Handle unfocus event
---@param self Button
---@return boolean Whether event was handled
function Button:onUnfocus() end

---Get button dimensions
---@param self Button
---@return table Button dimensions
function Button:getSize() end

---Paint button to blitbuffer
---@param self Button
---@param bb table Blitbuffer to paint to
---@param x number X position
---@param y number Y position
function Button:paintTo(bb, x, y) end

---Free button resources
---@param self Button
function Button:free() end

---Show button (make visible)
---@param self Button
function Button:show() end

---Hide button (make invisible)
---@param self Button
function Button:hide() end

---Update button with new options
---@param self Button
---@param options ButtonOptions New options
function Button:update(options) end

---Get button state
---@param self Button
---@return table Button state information
function Button:getState() end

---Set button state
---@param self Button
---@param state table New button state
function Button:setState(state) end

---Handle button press animation
---@param self Button
function Button:onButtonPress() end

---Handle button release animation
---@param self Button
function Button:onButtonRelease() end

---Create new Button instance
---@param self Button
---@param options ButtonOptions
---@return Button New instance
function Button:new(options) end

---Extend Button class
---@param self Button
---@param options ButtonOptions
---@return Button Extended class
function Button:extend(options) end

return Button
