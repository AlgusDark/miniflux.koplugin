# Miniflux Settings Architecture

This directory contains the object-oriented settings system for the Miniflux plugin. The architecture follows the common `new()` and `init()` pattern used throughout the codebase for consistency and maintainability.

## Directory Structure

```
settings/
├── README.md                    # This file - architecture documentation
├── settings.lua                 # Main settings module (OOP only)
└── ui/
    └── README.md               # Documentation about UI consolidation
```

## Architecture Overview

The settings system uses a clean OOP design with:

- **Instance-based architecture**: Each instance manages its own state and LuaSettings file
- **Common API pattern**: Uses `new()` and `init()` methods like other modules in the codebase
- **Proper encapsulation**: Instance variables instead of module-level globals
- **Clean interface**: Simple class export without unnecessary complexity

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

### 3. **Source of Truth Pattern**
- All settings read directly from LuaSettings on every call
- No complex caching or state management
- Immediate persistence with `instance:save()`

## Module Responsibilities

### `settings.lua` - Complete Settings Management
- **MinifluxSettings class**: OOP interface with `new()` and `init()`
- **Server configuration**: Address, API token, connection validation
- **Sorting preferences**: Order, direction, limit with validation
- **Display settings**: Hide read entries, include images
- **Input validation**: Type checking and default value fallback

### `ui/` - UI Integration Documentation
- Documents the consolidation of settings dialogs into the menu system
- Settings UI integrated directly with menu building for better cohesion

## Usage Examples

### OOP API (Standard usage)
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

### 5. **Simplicity**
- Clean, focused API without unnecessary complexity
- No backward compatibility layers to maintain
- Straightforward class-based design

## Class Interface

The `MinifluxSettings` class provides these methods:

### Core Methods
- `new(o?)` - Create new instance
- `init()` - Initialize settings file and defaults
- `save()` - Persist settings to disk

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

This clean OOP architecture provides a solid foundation for settings management with a simple, maintainable interface. 