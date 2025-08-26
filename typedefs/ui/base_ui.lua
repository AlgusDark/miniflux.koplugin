---@meta
---@module 'ui/base_ui'

---Base UI interface capturing common functionality needed from ReaderUI/FileManager
---@class BaseUI
---@field menu table
---@field active_widgets table[]
local BaseUI

---@param name string
---@param module table
---@param always_active? boolean
function BaseUI:registerModule(name, module, always_active) end

return BaseUI
