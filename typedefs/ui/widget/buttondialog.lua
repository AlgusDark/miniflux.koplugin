---@meta
---@module "ui/widget/buttondialog"

---@class ButtonDialog
---@field title string|nil # Dialog title text
---@field title_align string|nil # Title alignment ("left", "center", "right")
---@field buttons table[][]|nil # Grid of buttons, array of rows, each row is array of button definitions
local ButtonDialog = {}

return ButtonDialog