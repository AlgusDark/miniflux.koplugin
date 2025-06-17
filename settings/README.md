# Miniflux Settings Architecture

This directory contains the object-oriented settings system for the Miniflux plugin. The architecture follows the common `new()` and `init()` pattern used throughout the codebase for consistency and maintainability.

## Directory Structure

```
settings/
├── README.md                    # This file - architecture documentation
├── settings.lua                 # Main settings module (OOP + functional API)
└── ui/
    └── README.md               # Documentation about UI consolidation
```

## Architecture Overview

The settings system uses a clean OOP design with:

- **Instance-based architecture**: Each instance manages its own state and LuaSettings file
- **Common API pattern**: Uses `new()` and `init()` methods like other modules in the codebase
- **Proper encapsulation**: Instance variables instead of module-level globals
- **Backward compatibility**: Maintains functional API through singleton pattern

## Design Principles

### 1. **Object-Oriented Design**
- Clear class definition with `MinifluxSettings` class
- Instance methods instead of global functions
- Proper state management with instance variables
- Consistent with other OOP modules in the codebase

### 2. **Flexible Instantiation**
- `new()` method for creating instances
- `init()` method for lazy initialization
- Multiple instances supported for testing or specialized use cases

### 3. **Backward Compatibility**
- Functional API maintained through singleton pattern
- Existing code continues to work without changes
- Smooth migration path for future refactoring

### 4. **Source of Truth Pattern**
- All settings read directly from LuaSettings on every call
- No complex caching or state management
- Immediate persistence with `instance:save()`

## Module Responsibilities

### `settings.lua` - Complete Settings Management
- **MinifluxSettings class**: OOP interface with `new()` and `init()`
- **Server configuration**: Address, API token, connection validation
- **Sorting preferences**: Order, direction, limit with validation
- **Display settings**: Hide read entries, include images
- **Functional API**: Backward-compatible singleton-based functions
- **Input validation**: Type checking and default value fallback

### `ui/` - UI Integration Documentation
- Documents the consolidation of settings dialogs into the menu system
- Settings UI integrated directly with menu building for better cohesion

## Usage Examples

### OOP API (Recommended for new code)
```lua
local Settings = require("settings/settings")

-- Create a new settings instance
local settings = Settings.MinifluxSettings:new()
settings:init()

-- Configure server
settings:setServerAddress("https://miniflux.example.com")
settings:setApiToken("your-api-token-here")

-- Configure sorting
settings:setLimit(50)
settings:setOrder("published_at")
settings:setDirection("desc")

-- Save changes
settings:save()

-- Check configuration
if settings:isConfigured() then
    print("Settings are ready!")
end
```

### Functional API (Backward compatibility)
```lua
local Settings = require("settings/settings")

-- Auto-initialization on first use
local server = Settings.getServerAddress()
Settings.setServerAddress("https://miniflux.example.com")
Settings.save()

-- All existing functional API calls work unchanged
Settings.setApiToken("your-token")
Settings.setLimit(100)
if Settings.isConfigured() then
    print("Ready to go!")
end
```

### Advanced Usage (Multiple instances)
```lua
local Settings = require("settings/settings")

-- Create specialized settings instances
local test_settings = Settings.MinifluxSettings:new()
test_settings:init()

local production_settings = Settings.MinifluxSettings:new()
production_settings:init()

-- Configure each independently
test_settings:setServerAddress("https://test.miniflux.com")
production_settings:setServerAddress("https://miniflux.example.com")
```

### Validation and Constants
```lua
local Settings = require("settings/settings")

-- Access constants (available on both class and module)
local valid_orders = Settings.VALID_SORT_ORDERS
local defaults = Settings.MinifluxSettings.DEFAULTS

-- Validation is automatic
local settings = Settings.MinifluxSettings:new()
settings:init()
settings:setOrder("invalid_order")  -- Will log warning and use default
```

## Benefits of This Architecture

### 1. **Maintainability**
- Clear OOP structure with well-defined class boundaries
- Instance methods provide better encapsulation than global functions
- Consistent with other modules using `new()` and `init()` pattern
- Easy to understand and modify

### 2. **Flexibility**
- Multiple instances supported for testing or different configurations
- Each instance manages its own state independently
- Can create specialized settings instances for different purposes

### 3. **Testability**
- Easy to create isolated instances for unit testing
- No global state interference between tests
- Clear initialization and cleanup patterns

### 4. **Consistency**
- Follows the same patterns as other OOP modules in the codebase
- Common `new()` and `init()` API familiar to developers
- EmmyLua type annotations for IDE support

### 5. **Backward Compatibility**
- Existing code continues to work without changes
- Gradual migration path for modernizing code
- Functional API delegates to singleton instance seamlessly

## Migration Path

The module supports both APIs simultaneously:

### Existing Code (No changes needed)
```lua
-- This continues to work unchanged
local Settings = require("settings/settings")
Settings.setServerAddress("https://example.com")
local configured = Settings.isConfigured()
```

### New Code (Recommended)
```lua
-- Use OOP API for new development
local Settings = require("settings/settings")
local settings = Settings.MinifluxSettings:new()
settings:init()
settings:setServerAddress("https://example.com")
local configured = settings:isConfigured()
```

## Class Interface

The `MinifluxSettings` class provides these methods:

### Core Methods
- `new(o?)` - Create new instance
- `init()` - Initialize settings file and defaults
- `save()` - Persist settings to disk
- `export()` - Export all settings as table
- `reset()` - Reset to defaults

### Server Settings
- `getServerAddress()` / `setServerAddress(address)`
- `getApiToken()` / `setApiToken(token)`
- `isConfigured()` - Check if server is configured

### Sorting Settings
- `getLimit()` / `setLimit(limit)`
- `getOrder()` / `setOrder(order)`
- `getDirection()` / `setDirection(direction)`

### Display Settings
- `getHideReadEntries()` / `setHideReadEntries(hide)`
- `toggleHideReadEntries()` - Toggle and return new value
- `getIncludeImages()` / `setIncludeImages(include)`
- `toggleIncludeImages()` - Toggle and return new value
- `getAutoMarkRead()` / `setAutoMarkRead(auto_mark)`

This OOP architecture provides a solid foundation for settings management while maintaining full backward compatibility with existing code. 