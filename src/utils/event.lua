local UIManager = require('ui/uimanager')
local Event = require('ui/event')

---Event utility wrapper for Miniflux plugin
---Provides a clean interface around KOReader's event system
local MinifluxEvent = {}

---Send event to widgets (stops at first handler returning true)
---@param event_name string Event name
---@param event_data table Event data
function MinifluxEvent.sendEvent(event_name, event_data)
    UIManager:sendEvent(Event:new(event_name, event_data))
end

---Broadcast event to all widgets (all widgets receive it)
---@param event_name string Event name
---@param event_data table Event data
function MinifluxEvent.broadcastEvent(event_name, event_data)
    UIManager:broadcastEvent(Event:new(event_name, event_data))
end

return MinifluxEvent
