--[[--
**Browser Context Store**

Holds the most recent browser navigation context (feed, category, unread,
local, ...) at module scope so it survives plugin instance teardown.

Plugin instances come and go: opening an entry tears down the file-manager
Miniflux plugin and creates a reader-context one; closing the reader tears
that down too. Any state stored on the plugin class via an event handler is
only updated while at least one Miniflux instance is registered with
UIManager. The "Return to Miniflux" flow needs the context to survive across
those gaps, so we keep it here instead of relying on the broadcast handler.
--]]

---@class BrowserContextStore
local BrowserContext = {
    ---@type MinifluxContext|nil
    current = nil,
}

---@param context MinifluxContext|nil
function BrowserContext.set(context)
    BrowserContext.current = context
end

---@return MinifluxContext|nil
function BrowserContext.get()
    return BrowserContext.current
end

return BrowserContext
