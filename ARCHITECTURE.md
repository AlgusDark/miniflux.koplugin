# Miniflux Plugin Architecture

This document describes the streamlined modular architecture of the Miniflux plugin, where `main.lua` handles both coordination and initialization while delegating specialized functionality to focused modules.

## Before: Monolithic main.lua (189 lines)

The original `main.lua` was handling too many responsibilities:
- ❌ Plugin definition + initialization + directory management
- ❌ Complex menu construction with hardcoded business logic  
- ❌ Event registration and handling
- ❌ Module coordination and dependency management
- ❌ Mixed abstraction levels (low-level file ops + high-level coordination)

## After: Streamlined Architecture (165 lines)

The new `main.lua` is a **coordinator with integrated initialization**:
- ✅ Simple plugin definition and initialization
- ✅ Delegates menu construction to `MenuManager`  
- ✅ Delegates event handling to `EventHandler`
- ✅ Clean separation of concerns
- ✅ Direct initialization without unnecessary abstraction layers

## Architecture Overview

```
main.lua (165 lines - Coordinator + Initialization)
├── menu/
│   └── menu_manager.lua          # Menu construction & management
├── events/
│   └── event_handler.lua         # Event registration & processing
├── api/                          # API operations (existing)
├── settings/                     # Settings management (existing)
└── browser/                      # Browser functionality (existing)
```

## Module Responsibilities

### 📋 main.lua - Coordinator & Initializer (165 lines)
**Single Responsibility**: Coordinate modules and handle straightforward initialization
- Creates specialized managers (`MenuManager`, `EventHandler`)
- Initializes download directory, settings, API, and browser launcher
- Provides KOReader integration points (`init`, `addToMainMenu`, `onDispatcherRegisterActions`)
- **Focused initialization logic** - no unnecessary abstraction

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
- `main.lua`: Coordination and initialization
- `menu/`: Menu construction only
- `events/`: Event handling only

### 2. **Simplified Structure**
- **Removed unnecessary abstraction**: Initialization logic is straightforward and doesn't need a separate module
- **No mixed concerns**: Low-level initialization separate from high-level coordination within main.lua
- **Clear dependencies**: Each module has clear, injected dependencies

### 3. **Maintainability**  
- **Easy to find code**: Menu changes go in `menu/`, event changes go in `events/`
- **Simplified initialization**: All setup logic in one logical place
- **Focused modules**: Each specialized module does one thing well

### 4. **Extensibility**
- **New menu items**: Add to `MenuManager` without touching main file
- **New events**: Add to `EventHandler` without affecting other code  
- **New initialization steps**: Add directly to main.lua init method

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

### After Streamlined Refactoring
- **main.lua**: 165 lines of coordination and initialization (**13% reduction**)
- **menu/**: 511 lines of focused menu construction and dialogs
- **events/**: 58 lines of focused event handling
- **Total**: Clean, focused modules with minimal abstraction overhead

### Key Improvements
- **📦 Streamlined Design**: Clear separation without unnecessary layers
- **🧪 Testable Components**: Each specialized module independently testable
- **📚 Self-Documenting**: Module names clearly indicate their purpose
- **🔧 Maintainable**: Easy to modify specific functionality
- **🎯 Single Responsibility**: Each module does one thing well
- **⚡ Simplified**: Removed abstraction layer that provided no real value

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

### New Way (Streamlined Coordination)
```lua
-- main.lua handles initialization and coordination efficiently
function Miniflux:init()
    -- Direct initialization
    local download_dir = self:initializeDownloadDirectory()
    self.settings = MinifluxSettings
    self.api = MinifluxAPI:new()
    self.browser_launcher = BrowserLauncher:new()
    
    -- Create specialized managers
    self.menu_manager = MenuManager:new()
    self.event_handler = EventHandler:new()
    
    -- Delegate specialized functionality
    self.event_handler:initializeEvents(self)
    self.ui.menu:registerToMainMenu(self)
end
```

## Future Enhancements

This streamlined architecture makes it easy to add new functionality:

1. **New Initialization Steps**: Add directly to main.lua init method with clear error handling
2. **New Menu Sections**: Add builder methods to `MenuManager`
3. **New Events**: Add to `EventHandler` with proper delegation
4. **New Modules**: Follow the same patterns established in existing modules

The plugin now follows modern software architecture principles with minimal abstraction overhead while maintaining all existing functionality and providing a solid foundation for future development. 