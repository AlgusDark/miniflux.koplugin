# Miniflux Plugin Architecture

This document describes the streamlined modular architecture of the Miniflux plugin, where `main.lua` handles coordination, initialization, and event handling while delegating specialized functionality to focused modules.

## Before: Monolithic main.lua (189 lines)

The original `main.lua` was handling too many responsibilities:
- ❌ Plugin definition + initialization + directory management
- ❌ Complex menu construction with hardcoded business logic  
- ❌ Event registration and handling
- ❌ Module coordination and dependency management
- ❌ Mixed abstraction levels (low-level file ops + high-level coordination)

## After: Streamlined Architecture (165 lines)

The new `main.lua` is a **coordinator with integrated initialization and event handling**:
- ✅ Simple plugin definition and initialization
- ✅ Direct event handling without unnecessary abstraction
- ✅ Delegates menu construction to `MenuManager`  
- ✅ Clean separation of concerns
- ✅ Direct initialization without unnecessary abstraction layers

## Architecture Overview

```
main.lua (165 lines - Coordinator + Initialization + Event Handling)
├── menu/
│   └── menu_manager.lua          # Menu construction & management
├── api/                          # API operations (existing)
├── settings/                     # Settings management (existing)
└── browser/                      # Browser functionality (existing)
```

## Module Responsibilities

### 📋 main.lua - Coordinator & Initializer & Event Handler (165 lines)
**Single Responsibility**: Coordinate modules, handle straightforward initialization, and manage events
- Creates specialized managers (`MenuManager`)
- Initializes download directory, settings, API, and browser launcher
- Handles dispatcher registration and events directly (simple, no abstraction needed)
- Provides KOReader integration points (`init`, `addToMainMenu`, `onDispatcherRegisterActions`)
- **Focused initialization logic** - no unnecessary abstraction

### 📱 menu/ - Menu Construction & Management  
**Single Responsibility**: KOReader menu integration
- **`menu_manager.lua`**: Builds complete menu hierarchy with modular methods
- Dynamic menu content based on settings
- Separated menu construction from menu actions (actions still delegate to other modules)

## Benefits of This Architecture

### 1. **Single Responsibility Principle**
Each module has one clear purpose:
- `main.lua`: Coordination, initialization, and simple event handling
- `menu/`: Menu construction only

### 2. **Simplified Structure**
- **Removed unnecessary abstraction**: Event handling is simple enough to live in main.lua directly
- **No mixed concerns**: Low-level initialization separate from high-level coordination within main.lua
- **Clear dependencies**: Each module has clear, injected dependencies

### 3. **Maintainability**  
- **Easy to find code**: Menu changes go in `menu/`, simple events stay in `main.lua`
- **Simplified initialization**: All setup logic in one logical place
- **Focused modules**: Each specialized module does one thing well
- **Less abstraction**: Fewer layers to understand and maintain

### 4. **Extensibility**
- **New menu items**: Add to `MenuManager` without touching main file
- **New events**: Add directly to main.lua (simple dispatcher actions don't need abstraction)
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
- **main.lua**: 165 lines of coordination, initialization, and event handling (**13% reduction**)
- **menu/**: 511 lines of focused menu construction and dialogs
- **Total**: Clean, focused modules with minimal abstraction overhead

### Key Improvements
- **📦 Streamlined Design**: Clear separation without unnecessary layers
- **🧪 Testable Components**: Each specialized module independently testable
- **📚 Self-Documenting**: Module names clearly indicate their purpose
- **🔧 Maintainable**: Easy to modify specific functionality
- **🎯 Single Responsibility**: Each module does one thing well
- **⚡ Simplified**: Removed abstraction layers that provided no real value

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
    
    -- Simple event handling directly in main (no abstraction needed)
    self.ui.menu:registerToMainMenu(self)
end

-- Simple event methods directly in main.lua
function Miniflux:onDispatcherRegisterActions()
    Dispatcher:registerAction("miniflux_read_entries", {
        category = "none",
        event = "ReadMinifluxEntries",
        title = _("Read Miniflux entries"),
        general = true,
    })
end

function Miniflux:onReadMinifluxEntries()
    if self.browser_launcher then
        self.browser_launcher:showMainScreen()
    end
end
```

## Future Enhancements

This streamlined architecture makes it easy to add new functionality:

1. **New Initialization Steps**: Add directly to main.lua init method with clear error handling
2. **New Menu Sections**: Add builder methods to `MenuManager`
3. **New Events**: Add directly to main.lua (simple dispatcher events don't need abstraction)
4. **New Modules**: Follow the same patterns established in existing modules

The plugin now follows modern software architecture principles with minimal abstraction overhead while maintaining all existing functionality and providing a solid foundation for future development. 