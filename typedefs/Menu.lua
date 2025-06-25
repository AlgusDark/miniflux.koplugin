--[[--
EmmyLua type definitions for Menu

@module koplugin.miniflux.typedefs.Menu
--]] --

---@class MenuOptions
---@field title? string Menu title
---@field subtitle? string Menu subtitle
---@field item_table? table[] Initial menu items
---@field perpage? number Items per page
---@field is_popout? boolean Whether menu is a popout
---@field covers_fullscreen? boolean Whether menu covers fullscreen
---@field is_borderless? boolean Whether menu is borderless
---@field title_bar_fm_style? boolean Whether to use file manager title bar style
---@field title_bar_left_icon? string Left icon in title bar
---@field title_shrink_font_to_fit? boolean Whether to shrink title font to fit

---@class Menu
---@field title string Menu title
---@field subtitle string Menu subtitle
---@field item_table table[] Menu items
---@field page number Current page number
---@field selected table Selected items
---@field itemnumber number Current item number
---@field perpage number Items per page
---@field paths table[] Navigation paths
---@field onReturn function|nil Back navigation callback
---@field onLeftButtonTap function Left button callback
---@field init fun(self: Menu): nil Initialize menu
---@field switchItemTable fun(self: Menu, title: string, items: table[], select_number?: number, menu_title?: string, subtitle?: string): nil Switch menu content
---@field updatePageInfo fun(self: Menu): nil Update page information
---@field extend fun(self: Menu, o: MenuOptions): Menu Extend menu class
---@field new fun(self: Menu, o: MenuOptions): Menu Create new menu instance
