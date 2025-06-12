# Events Module

This directory contains modules responsible for event handling and dispatcher integration.

## Files

### `event_handler.lua`
Handles dispatcher action registration and event processing:
- **Dispatcher Registration**: Registers plugin actions with KOReader's dispatcher system
- **Event Processing**: Processes incoming events and delegates to appropriate handlers
- **Event Coordination**: Coordinates between KOReader events and plugin functionality
- **Clean Separation**: Separates event handling from business logic

## Architecture

Follows the single responsibility principle for event management:
- **Event Registration**: Centralized registration of all plugin events
- **Handler Delegation**: Routes events to appropriate plugin modules
- **Loose Coupling**: Events are loosely coupled to plugin functionality
- **Clean Interface**: Provides clean interface between KOReader and plugin

## Events

### Registered Events
- **`miniflux_read_entries`**: Opens the main Miniflux browser interface

### Event Flow
1. KOReader dispatcher receives action
2. EventHandler processes the event  
3. Event is routed to appropriate plugin module
4. Plugin module executes the requested functionality

## Usage

```lua
local EventHandler = require("events/event_handler")
local event_handler = EventHandler:new()

-- Initialize event system for plugin
event_handler:initializeEvents(plugin_instance)

-- Events are now ready to be dispatched
```

## Benefits

- **Centralized Event Management**: All event handling in one place
- **Clean Separation**: Events separated from business logic
- **Extensibility**: Easy to add new events and handlers
- **Testability**: Event handling can be tested independently
- **KOReader Integration**: Proper integration with KOReader's event system 