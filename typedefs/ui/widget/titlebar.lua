---@meta
---@module 'ui/widget/titlebar'

---@class TitleBarOptions : WidgetContainerOptions
---@field show_parent? table Parent widget to show dialog on
---@field fullscreen? string|boolean Whether titlebar is fullscreen ("true" or boolean)
---@field align? "left"|"center"|"right" Text alignment for title
---@field title? string Title text to display
---@field left_icon? string Left icon identifier (e.g., "appbar.settings")
---@field left_icon_tap_callback? function Callback when left icon is tapped
---@field right_icon? string Right icon identifier (e.g., "check", "exit")
---@field right_icon_tap_callback? function Callback when right icon is tapped
---@field subtitle? string Subtitle text to display
---@field subtitle_multilines? boolean Enable multiline subtitle support
---@field subtitle_fullwidth? boolean Make subtitle use full width
---@field subtitle_truncate_left? boolean Control subtitle truncation

---@class TitleBar : WidgetContainer
---@field extend fun(self: TitleBar, o: TitleBarOptions): TitleBar Extend TitleBar class
---@field new fun(self: TitleBar, o: TitleBarOptions): TitleBar Create new TitleBar instance
---@field init fun(self: TitleBar): nil Initialize title bar
---@field setRightIcon fun(self: TitleBar, icon: string): nil Set the right icon
---@field setLeftIcon fun(self: TitleBar, icon: string): nil Set the left icon
---@field setTitle fun(self: TitleBar, title: string): nil Set the title text
---@field setSubTitle fun(self: TitleBar, subtitle: string): nil Set the subtitle text
---@field setRightIconTapCallback fun(self: TitleBar, callback: function): nil Set the right icon tap callback
---@field setLeftIconTapCallback fun(self: TitleBar, callback: function): nil Set the left icon tap callback
local TitleBar = {}

return TitleBar
