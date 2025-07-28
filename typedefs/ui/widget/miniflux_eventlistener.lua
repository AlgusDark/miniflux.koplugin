---@meta
---@class MinifluxEventListener
---@field [string] function Dynamic event handler methods
local MinifluxEventListener = {}

---Handle Miniflux settings changed event
---@param self MinifluxEventListener
---@param payload MinifluxSettingsChangeData # Event payload
function MinifluxEventListener:onMinifluxSettingsChange(payload) end

---Handle Miniflux cache invalidate event
---@param self MinifluxEventListener
function MinifluxEventListener:onMinifluxCacheInvalidate() end

---Handle Miniflux server config change event
---@param self MinifluxEventListener
---@param args MinifluxServerConfigChangeData # Event payload with new server configuration
function MinifluxEventListener:onMinifluxServerConfigChange(args) end

---Handle Miniflux browser close requested event
---@param self MinifluxEventListener
---@param payload? { reason?: string } # Event payload with close reason
function MinifluxEventListener:onMinifluxBrowserCloseRequest(payload) end

---Handle Miniflux browser context change event
---@param self MinifluxEventListener
---@param payload? MinifluxBrowserContextChangeData # Event payload with new context
function MinifluxEventListener:onMinifluxBrowserContextChange(payload) end

return MinifluxEventListener
