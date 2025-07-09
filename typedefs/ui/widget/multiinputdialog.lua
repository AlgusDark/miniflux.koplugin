---@meta
---@module 'ui/widget/multiinputdialog'

---@class MultiInputDialog
---@field title string Dialog title
---@field fields table[] Input fields
---@field buttons table[][] Dialog buttons
---@field getFields fun(self: MultiInputDialog): string[] Get field values
---@field new fun(self: MultiInputDialog, o: table): MultiInputDialog Create new multi-input dialog
local MultiInputDialog = {}

function MultiInputDialog:onShowKeyboard() end

return MultiInputDialog
