---@meta
---@module 'ui/widget/eventlistener'

---@class EventListenerOptions
---@field init? function Initialization function called during construction

---@class Event
---@field name string Event name (e.g., "Tap", "Hold", "KeyPress")
---@field handler string Handler method name (e.g., "onTap", "onHold", "onKeyPress")
---@field args table Event arguments array with .n field for argument count

---EventListener base class for KOReader - Foundation for event handling in widgets
---
---The EventListener is the base interface that handles events in KOReader's widget system.
---It provides a rudimentary event handler/dispatcher that automatically calls methods
---named "onEventName" for events with name "EventName".
---
---This is the root base class for the entire widget hierarchy:
---EventListener -> Widget -> [All other widgets]
---
---Core Features:
---- Event method dispatch based on event handler names
---- Class inheritance system with metatable prototype chains
---- Automatic event handler resolution
---- Foundation for all widget event handling
---@class EventListener : MinifluxEventListener
---@field init function|nil Initialization function
---@field [string] function Dynamic event handler methods (onTap, onHold, etc.)
local EventListener = {}

---Create an EventListener subclass that inherits from this base class
---Sets up the metatable (prototype chain) without creating an instance
---@param self EventListener
---@param subclass_prototype? table Subclass prototype table
---@return EventListener Extended EventListener class
function EventListener:extend(subclass_prototype) end

---Create an instance of an EventListener class
---This calls the init() method if it exists
---@param self EventListener
---@param o? table Options table for the new instance
---@return EventListener New EventListener instance
function EventListener:new(o) end

---Handle an event by invoking the appropriate handler method
---Handler method name is determined by the event's handler field
---By default, it's "on" + Event.name (e.g., "onTap" for "Tap" event)
---@param self EventListener
---@param event Event Event object to handle
---@return boolean|nil True if event was consumed successfully, nil if no handler
function EventListener:handleEvent(event) end

---Common event handler methods that subclasses can implement
---These are called automatically by handleEvent() when corresponding events occur

---Handle tap gesture event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onTap(...) end

---Handle hold gesture event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onHold(...) end

---Handle swipe gesture event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onSwipe(...) end

---Handle key press event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onKeyPress(...) end

---Handle key release event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onKeyRelease(...) end

---Handle key repeat event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onKeyRepeat(...) end

---Handle focus event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onFocus(...) end

---Handle unfocus event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onUnfocus(...) end

---Handle show event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onShow(...) end

---Handle close event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onClose(...) end

---Handle resize event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onResize(...) end

---Handle flush settings event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onFlushSettings(...) end

---Handle suspend event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onSuspend(...) end

---Handle resume event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onResume(...) end

---Handle power event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onPowerEvent(...) end

---Handle network connected event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onNetworkConnected(...) end

---Handle network disconnected event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onNetworkDisconnected(...) end

---Handle USB plug in event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onUSBPlugIn(...) end

---Handle USB plug out event
---@param self EventListener
---@param ... any Event arguments
---@return boolean|nil Whether event was handled
function EventListener:onUSBPlugOut(...) end

return EventListener
