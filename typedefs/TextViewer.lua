--[[--
EmmyLua type definitions for TextViewer

@module koplugin.miniflux.typedefs.TextViewer
--]]--

---@class TextViewer
---@field title string Viewer title
---@field text string Text content
---@field text_face table Text font face
---@field justified boolean Whether text is justified
---@field buttons_table table[][] Viewer buttons
---@field new fun(o: table): TextViewer Create new text viewer 