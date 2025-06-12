# Miniflux Plugin Architecture

This document describes the improved modular architecture of the Miniflux plugin, where `main.lua` has been transformed from a monolithic file into a simple coordinator that delegates to specialized modules.

## Before: Monolithic main.lua (189 lines)

The original `main.lua` was handling too many responsibilities:
- ❌ Plugin definition + initialization + directory management
- ❌ Complex menu construction with hardcoded business logic  
- ❌ Event registration and handling
- ❌ Module coordination and dependency management
- ❌ Mixed abstraction levels (low-level file ops + high-level coordination)

## After: Modular Architecture (52 lines)

The new `main.lua` is a **pure coordinator** that delegates to specialized modules:
- ✅ Simple plugin definition and coordination only
- ✅ Delegates initialization to `PluginInitializer`
- ✅ Delegates menu construction to `MenuManager`  
- ✅ Delegates event handling to `EventHandler`
- ✅ Clean separation of concerns

## Architecture Overview

```
main.lua (52 lines - Pure Coordinator)
├── initialization/
│   └── plugin_initializer.lua    # Bootstrap & setup logic
├── menu/
│   └── menu_manager.lua          # Menu construction & management
├── events/
│   └── event_handler.lua         # Event registration & processing
├── api/                          # API operations (existing)
├── settings/                     # Settings management (existing)
└── browser/                      # Browser functionality (existing)
```

## Module Responsibilities

### 📋 main.lua - Pure Coordinator (52 lines)
**Single Responsibility**: Coordinate between specialized modules
- Creates specialized managers (`PluginInitializer`, `MenuManager`, `EventHandler`)
- Delegates initialization, menu setup, and event handling
- Provides KOReader integration points (`init`, `addToMainMenu`, `onDispatcherRegisterActions`)
- **Zero business logic** - pure coordination

### 🚀 initialization/ - Bootstrap & Setup
**Single Responsibility**: Plugin component initialization
- **`plugin_initializer.lua`**: Handles directory setup, module initialization, dependency injection
- Robust error handling during startup
- Clean separation of initialization logic from coordination

### 📱 menu/ - Menu Construction & Management  
**Single Responsibility**: KOReader menu integration
- **`menu_manager.lua`**: Builds complete menu hierarchy with modular methods
- Dynamic menu content based on settings
- Separated menu construction from menu actions (actions still delegate to other modules)

### ⚡ events/ - Event Handling & Dispatcher Integration
**Single Responsibility**: Event processing and coordination
- **`event_handler.lua`**: Registers dispatcher actions, processes events
- Clean interface between KOReader events and plugin functionality
- Loose coupling between events and business logic

## Benefits of This Architecture

### 1. **Single Responsibility Principle**
Each module has one clear purpose:
- `main.lua`: Coordination only
- `initialization/`: Setup only  
- `menu/`: Menu construction only
- `events/`: Event handling only

### 2. **Maintainability**
- **Easy to find code**: Menu changes go in `menu/`, initialization changes go in `initialization/`
- **No mixed concerns**: No more low-level directory ops mixed with high-level coordination
- **Clear dependencies**: Each module has clear, injected dependencies

### 3. **Testability**  
- **Isolated modules**: Each module can be tested independently
- **Dependency injection**: Easy to mock dependencies for testing
- **Focused tests**: Tests can focus on specific responsibilities

### 4. **Extensibility**
- **New menu items**: Add to `MenuManager` without touching main file
- **New events**: Add to `EventHandler` without affecting other code  
- **New initialization steps**: Add to `PluginInitializer` with proper error handling

### 5. **Consistency**
Now follows the same excellent patterns used in:
- **`api/`**: Modular API client with specialized modules
- **`settings/`**: Modular settings with specialized modules  
- **`browser/`**: Modular browser with specialized modules

## Code Quality Metrics

### Before Refactoring
- **main.lua**: 189 lines with mixed responsibilities
- **Coupling**: High coupling between concerns
- **Testing**: Difficult to test individual components

### After Refactoring
- **main.lua**: 52 lines of pure coordination (**72% reduction**)
- **initialization/**: 75 lines of focused setup logic
- **menu/**: 180 lines of focused menu construction
- **events/**: 45 lines of focused event handling
- **Total**: 352 lines across 4 focused modules vs 189 lines of mixed concerns

### Key Improvements
- **📦 Modular Design**: Clear separation of concerns
- **🧪 Testable Components**: Each module independently testable
- **📚 Self-Documenting**: Module names clearly indicate their purpose
- **🔧 Maintainable**: Easy to modify specific functionality
- **🎯 Single Responsibility**: Each module does one thing well

## Usage Examples

### Old Way (Everything in main.lua)
```lua
-- main.lua had everything mixed together
function Miniflux:init()
    -- Directory setup mixed with module initialization
    -- Menu construction mixed with event handling
    -- 189 lines of mixed concerns
end
```

### New Way (Coordinated Modules)
```lua
-- main.lua is now a clean coordinator
function Miniflux:init()
    -- Create specialized managers
    self.initializer = PluginInitializer:new()
    self.menu_manager = MenuManager:new()
    self.event_handler = EventHandler:new()
    
    -- Delegate to specialists
    self.initializer:initializePlugin(self)
    self.event_handler:initializeEvents(self)
    self.ui.menu:registerToMainMenu(self)
end
```

## Future Enhancements

This modular architecture makes it easy to add new functionality:

1. **New Initialization Steps**: Add to `PluginInitializer` with proper error handling
2. **New Menu Sections**: Add builder methods to `MenuManager`
3. **New Events**: Add to `EventHandler` with proper delegation
4. **New Modules**: Follow the same patterns established in existing modules

The plugin now follows modern software architecture principles while maintaining all existing functionality and providing a solid foundation for future development. 