---@meta
---@class MinifluxEventListener
---@field [string] function Dynamic event handler methods (onMinifluxSettingsChanged, onMinifluxCacheInvalidate, etc.)
local MinifluxEventListener = {}

---Handle Miniflux settings changed event
---@param self MinifluxEventListener
---@param payload MinifluxSettingsChangeData # Event payload
function MinifluxEventListener:onMinifluxSettingsChanged(payload) end

---Handle Miniflux cache invalidate event
---@param self MinifluxEventListener
function MinifluxEventListener:onMinifluxCacheInvalidate() end

return MinifluxEventListener
