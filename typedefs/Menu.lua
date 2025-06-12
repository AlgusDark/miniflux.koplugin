--[[--
EmmyLua type definitions for Menu

@module koplugin.miniflux.typedefs.Menu
--]]--

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
---@field extend fun(self: Menu, o: table): Menu Extend menu class 