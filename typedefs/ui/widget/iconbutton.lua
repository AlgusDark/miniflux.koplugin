---@meta
---@module 'ui/widget/iconbutton'

--[[--
Button with a big icon image! Designed for touch devices.
--]]

---@class IconButtonOptions
---@field icon? string Icon name (default: "notice-warning")
---@field icon_rotation_angle? number Icon rotation angle (default: 0)
---@field width? number Button width (default: scaled icon size)
---@field height? number Button height (default: scaled icon size)
---@field padding? number Padding around icon (default: 0)
---@field padding_top? number Top padding
---@field padding_right? number Right padding
---@field padding_bottom? number Bottom padding
---@field padding_left? number Left padding
---@field enabled? boolean Whether button is enabled (default: true)
---@field callback? function Tap callback function
---@field hold_callback? function Hold callback function
---@field allow_flash? boolean Whether to show tap flash (default: true)
---@field show_parent? table Parent widget for UI management

---@class IconButton : InputContainer
---@field icon string Current icon name
---@field icon_rotation_angle number Icon rotation angle
---@field width number Button width
---@field height number Button height
---@field enabled boolean Whether button is enabled
---@field callback function|nil Tap callback function
---@field hold_callback function|nil Hold callback function
---@field allow_flash boolean Whether to show tap flash
---@field show_parent table Parent widget reference
---@field image IconWidget The icon widget
---@field new fun(self: IconButton, o: IconButtonOptions): IconButton Create new IconButton
---@field init fun(self: IconButton): nil Initialize IconButton
---@field setIcon fun(self: IconButton, icon: string): nil Set button icon
---@field onTapIconButton fun(self: IconButton): boolean Handle tap gesture
---@field onHoldIconButton fun(self: IconButton): boolean Handle hold gesture
local IconButton = {}

return IconButton
