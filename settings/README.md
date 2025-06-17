# Miniflux Settings Architecture

This directory contains the simplified settings system for the Miniflux plugin. The complex OOP architecture has been flattened into a single, efficient module.

## Directory Structure

```
settings/
├── README.md                    # This file - architecture documentation
├── settings.lua                 # Main settings module (functional API)
└── ui/
    ├── README.md               # UI components documentation
    └── settings_dialogs.lua    # UI dialogs for settings configuration
```

## Architecture Overview

The settings system has been simplified from a complex OOP hierarchy to a straightforward functional module that:

- **Always gets from source of truth**: Direct access to LuaSettings without caching or abstraction layers
- **No OOP complexity**: Simple functions instead of classes, inheritance, and dependency injection
- **Minimal memory footprint**: No object instances or complex state management
- **Fast and reliable**: Direct LuaSettings calls without performance overhead

## Design Principles

### 1. **Simplicity Over Complexity**
- Single module instead of multiple classes
- Functional API instead of OOP methods
- Direct LuaSettings access instead of abstraction layers

### 2. **Source of Truth Pattern**
- All settings are read directly from LuaSettings on every call
- No caching or state management complexity
- Immediate persistence with `settings.save()`

### 3. **Validation at the Boundary**
- Input validation when setting values
- Sensible defaults for all settings
- Graceful fallback to defaults on invalid data

## Module Responsibilities

### `settings.lua` - All Settings Management
- Server configuration (address, API token)
- Sorting preferences (order, direction, limit)
- Display settings (hide read entries, include images, font size)
- Input validation and type checking
- Default value management
- Direct LuaSettings persistence

### `ui/settings_dialogs.lua` - UI Components
- Server settings dialog
- Limit configuration dialog
- Connection testing
- Dynamic menu generation for sort options
- Integration with the simplified settings API

## Benefits of This Architecture

### 1. **Maintainability**
- Single file to understand and modify
- No complex inheritance or dependency chains
- Clear, simple function names and purposes

### 2. **Performance**
- No object instantiation overhead
- Direct LuaSettings access (fast enough for this use case)
- Minimal memory footprint

### 3. **Reliability**
- Always gets current values from storage
- No cache invalidation issues
- Simple error handling and logging

### 4. **Simplicity**
- Easy to understand and debug
- No complex patterns or abstractions
- Straightforward functional API

## Usage Examples

### Basic Usage
```lua
local Settings = require("settings/settings")

-- No initialization needed - auto-initializes on first use
local server = Settings.getServerAddress()
Settings.setServerAddress("https://miniflux.example.com")
Settings.save()
```

### Complete Configuration
```lua
local Settings = require("settings/settings")

-- Configure server
Settings.setServerAddress("https://miniflux.example.com")
Settings.setApiToken("your-api-token-here")

-- Configure sorting
Settings.setLimit(50)
Settings.setOrder("published_at")
Settings.setDirection("desc")

-- Configure display
Settings.setHideReadEntries(true)
Settings.setIncludeImages(false)

-- Save all changes
Settings.save()
```

### Validation and Constants
```lua
local Settings = require("settings/settings")

-- Get available options
local valid_orders = Settings.VALID_SORT_ORDERS
local valid_directions = Settings.VALID_SORT_DIRECTIONS
local defaults = Settings.DEFAULTS

-- Validation is automatic
Settings.setOrder("invalid_order")  -- Will log warning and use default
Settings.setLimit("not_a_number")   -- Will log warning and use default
```

## Migration from Old Architecture

The external API remains the same for compatibility:

- `Settings.getServerAddress()` (was `settings:getServerAddress()`)
- `Settings.setServerAddress(addr)` (was `settings:setServerAddress(addr)`)
- `Settings.isConfigured()` (was `settings:isConfigured()`)
- All other getter/setter methods follow the same pattern

The main changes:
- Use `.` instead of `:` for method calls (functional vs OOP)
- No need to call `init()` or manage instances
- Automatic initialization on first use
- Direct save with `Settings.save()`

This simplified architecture removes all the complexity while maintaining the same functionality and external API compatibility. 