local UIManager = require('ui/uimanager')
local Event = require('ui/event')

---Event utility wrapper for Miniflux plugin
---Provides a clean interface around KOReader's event system
---@class MinifluxEvent
local MinifluxEvent = {}

---@enum MinifluxEventName
---| 'MinifluxSettingsChange'
---| 'MinifluxCacheInvalidate'
---| 'MinifluxServerConfigChange'
---| 'MinifluxBrowserCloseRequested'
local MinifluxEventName = {
    MinifluxSettingsChange = 'MinifluxSettingsChange',
    MinifluxCacheInvalidate = 'MinifluxCacheInvalidate',
    MinifluxServerConfigChange = 'MinifluxServerConfigChange',
    MinifluxBrowserCloseRequested = 'MinifluxBrowserCloseRequested',
}

---Broadcast event to all widgets (all widgets receive it)
---@param event_name string # The name of the event
---@param payload? table # The payload data of the event
function broadcastEvent(event_name, payload)
    UIManager:broadcastEvent(Event:new(event_name, payload))
end

---@alias MinifluxSettingsChangeData { key: MinifluxSettingsKeys, old_value: any, new_value: any }

---@param payload MinifluxSettingsChangeData
function MinifluxEvent:broadcastMinifluxSettingsChange(payload)
    broadcastEvent(MinifluxEventName.MinifluxSettingsChange, payload)
end

function MinifluxEvent:broadcastMinifluxInvalidateCache()
    broadcastEvent(MinifluxEventName.MinifluxCacheInvalidate)
end

---@alias MinifluxServerConfigChangeData { api_token: string, server_address: string }

---@param payload MinifluxServerConfigChangeData
function MinifluxEvent:broadcastMinifluxServerConfigChange(payload)
    broadcastEvent(MinifluxEventName.MinifluxServerConfigChange, payload)
end

---@alias MinifluxBrowserCloseRequestedData { reason?: string }

---@param payload? MinifluxBrowserCloseRequestedData
function MinifluxEvent:broadcastMinifluxBrowserCloseRequested(payload)
    broadcastEvent(MinifluxEventName.MinifluxBrowserCloseRequested, payload)
end

return MinifluxEvent
