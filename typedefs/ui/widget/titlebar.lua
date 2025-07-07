---@meta
---@module "ui/widget/titlebar"

---@class TitleBarProps
---@field width number Default to screen width
---@field fullscreen boolean|string Larger font and adjustments if fullscreen
---@field align "center"|"left" Title & subtitle alignment inside TitleBar
---@field title string
---@field subtitle string

---@class TitleBarOptions
---@field with_bottom_line? boolean
---@field bottom_line_color? any Default to black
---@field bottom_line_h_padding? number Default to 0: full width
---@field title_face? table Font face for title
---@field title_multilines? boolean Multilines if overflow
---@field title_shrink_font_to_fit? boolean Reduce font size so single line text fits
---@field subtitle_face? table Font face for subtitle
---@field subtitle_truncate_left? boolean Default with single line is to truncate right
---@field subtitle_fullwidth? boolean True to allow subtitle to extend below buttons
---@field subtitle_multilines? boolean Multilines if overflow
---@field info_text? string Additional text displayed below bottom line
---@field info_text_face? table Font face for info text
---@field title_top_padding? number Computed if none provided
---@field title_h_padding? number Horizontal padding
---@field title_subtitle_v_padding? number Vertical padding between title and subtitle
---@field bottom_v_padding? number
---@field button_padding? number Fine to keep exit/cross icon diagonally aligned
---@field left_icon? string
---@field left_icon_size_ratio? number
---@field left_icon_rotation_angle? number
---@field left_icon_tap_callback? function|false
---@field left_icon_hold_callback? function|false
---@field left_icon_allow_flash? boolean
---@field right_icon? string
---@field right_icon_size_ratio? number
---@field right_icon_rotation_angle? number
---@field right_icon_tap_callback? function|false
---@field right_icon_hold_callback? function|false
---@field right_icon_allow_flash? boolean
---@field close_callback? function If provided, use right_icon="exit" and use this as right_icon_tap_callback
---@field close_hold_callback? function
---@field show_parent? table Parent widget for UI management

---@class TitleBar : TitleBarProps
---@field left_button IconButton|nil Left button widget
---@field right_button IconButton|nil Right button widget
---@field has_left_icon boolean
---@field has_right_icon boolean
---@field new fun(self: TitleBar, o: TitleBarOptions): TitleBar Create new TitleBar instance
---@field init fun(self: TitleBar): nil Initialize TitleBar
---@field setTitle fun(self: TitleBar, title: string, no_refresh?: boolean): nil Set title text
---@field setSubTitle fun(self: TitleBar, subtitle: string, no_refresh?: boolean): nil Set subtitle text
---@field setLeftIcon fun(self: TitleBar, icon: string): nil Set left icon
---@field setRightIcon fun(self: TitleBar, icon: string): nil Set right icon
---@field getHeight fun(self: TitleBar): number Get titlebar height
local TitleBar = {}

return TitleBar