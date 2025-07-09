---@meta
---@module 'ui/widge/infomessage'

---@class InfoMessage
---@field text string Message text
---@field timeout? number Message timeout in seconds
---@field dismiss_callback? function Callback when dismissed
---@field new fun(self: InfoMessage, o: table): InfoMessage Create new info message
---@field init fun(self: InfoMessage) Initialize/reinitialize the widget
local InfoMessage = {}

return InfoMessage
