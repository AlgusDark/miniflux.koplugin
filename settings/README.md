# Miniflux Settings Architecture

This directory contains the refactored modular settings system for the Miniflux plugin. The code has been organized following the Unix philosophy of "do one thing and do it well" and incorporates modern design patterns.

## Directory Structure

```
settings/
├── README.md                    # This file - architecture documentation
├── enums.lua                    # Enums and constants for settings
├── base_settings.lua            # Base class with common functionality
├── server_settings.lua          # Server connection settings
├── sorting_settings.lua         # Sorting and pagination settings
├── display_settings.lua         # UI display preferences
├── debug_settings.lua           # Debug and logging settings
└── settings_manager.lua         # Main coordinator (Facade pattern)
```

**Note**: Type aliases (`SortOrder`, `SortDirection`) are defined in `api.lua` to prevent duplication.

## Design Patterns Used

### 1. **Single Responsibility Principle (SRP)**
Each module has one clear responsibility:
- **ServerSettings**: Server address and API token management
- **SortingSettings**: Sort order, direction, and entry limits
- **DisplaySettings**: UI preferences like hiding read entries, image inclusion
- **DebugSettings**: Debug logging configuration

### 2. **Dependency Injection**
The `BaseSettings` class accepts a `LuaSettings` instance and logger through its `init()` method, allowing for:
- Easy testing with mock dependencies
- Flexible configuration of storage backends
- Loose coupling between modules

### 3. **Facade Pattern**
The `SettingsManager` acts as a facade that:
- Provides a unified interface to all settings modules
- Handles initialization and coordination
- Maintains backward compatibility with the old API

### 4. **Inheritance**
All settings modules inherit from `BaseSettings` which provides:
- Common CRUD operations
- Validation framework
- Bulk operations
- Error handling

### 5. **Enum Pattern**
The `enums.lua` file centralizes all constants and valid values:
- Type-safe sort orders and directions (types defined in `api.lua`)
- Centralized default values
- Validation functions

## Module Responsibilities

### `enums.lua` - Constants and Validation
- Defines all valid enumeration values
- Provides validation functions
- Centralizes default values
- Note: Type aliases are defined in `api.lua`

### `base_settings.lua` - Common Functionality
- Dependency injection setup
- Basic CRUD operations (`get`, `set`, `toggle`)
- Validation framework with `setWithValidation`
- Bulk operations (`getMultiple`, `setMultiple`)
- Error handling and logging

### `server_settings.lua` - Server Configuration
- Server address with URL validation and normalization
- API token management with validation
- Connection status checking
- Server-specific utility functions

### `sorting_settings.lua` - Sorting & Pagination
- Sort order with enum validation
- Sort direction with enum validation  
- Entry limit with range validation
- Display name resolution for UI
- Reset functionality

### `display_settings.lua` - UI Preferences
- Hide/show read entries toggle
- Image inclusion settings
- Auto-mark read functionality
- Entry font size with range validation
- Legacy settings support

### `debug_settings.lua` - Debug Configuration
- Debug logging enable/disable
- Simple boolean validation
- Convenience methods for common operations

### `settings_manager.lua` - Main Coordinator
- Initializes all sub-modules with dependency injection
- Provides unified API for settings management
- Handles default value loading
- Delegates operations to appropriate modules
- Instance-based pattern for efficient memory usage

## Benefits of This Architecture

### 1. **Maintainability**
- Easy to find and modify specific settings
- Clear separation of concerns
- Consistent patterns across modules

### 2. **Testability**
- Each module can be tested independently
- Dependency injection allows for easy mocking
- Validation logic is isolated and testable

### 3. **Extensibility**
- New setting categories can be added as new modules
- Existing modules can be extended without affecting others
- Plugin-specific settings can be added easily

### 4. **Type Safety**
- EmmyLua annotations throughout
- Enum-based validation
- Clear parameter and return types

### 5. **Clean Architecture**
- Direct access to SettingsManager
- No unnecessary wrapper layers
- Clear dependency paths

## Usage Examples

### Basic Usage
```lua
local settings = require("settings/settings_manager")

-- Direct access to the settings manager
local server = settings:getServerAddress()
settings:setServerAddress("https://miniflux.example.com")
```

### Advanced Usage (New Modular API)
```lua
local settings = require("settings/settings_manager")

-- Access specific modules
local serverConfig = settings:getModuleSettings("server")
local sortingConfig = settings:getModuleSettings("sorting")

-- Set all settings for a module at once
settings:setModuleSettings("display", {
    hide_read_entries = true,
    include_images = false,
    auto_mark_read = true
})
```

### Direct Module Access
```lua
local ServerSettings = require("settings/server_settings")
local LuaSettings = require("luasettings")

-- Create and inject dependencies
local storage = LuaSettings:open("test.lua")
local server = ServerSettings:new()
server:init(storage, logger)

-- Use normalized URL setting
server:setNormalizedServerAddress("https://example.com/")
```

## Adding New Settings

To add a new setting category:

1. **Create Module**: `settings/new_category_settings.lua`
2. **Inherit from BaseSettings**: Use the inheritance pattern
3. **Add to SettingsManager**: Include initialization and delegation
4. **Update Enums**: Add any new constants or defaults
5. **Document**: Update this README

### Example: Adding Theme Settings
```lua
-- settings/theme_settings.lua
local BaseSettings = require("settings/base_settings")
local Enums = require("settings/enums")

local ThemeSettings = {}
setmetatable(ThemeSettings, {__index = BaseSettings})

function ThemeSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function ThemeSettings:getTheme()
    return self:get("theme", "light")
end

function ThemeSettings:setTheme(theme)
    local validThemes = {"light", "dark", "sepia"}
    local function isValidTheme(t)
        for _, valid in ipairs(validThemes) do
            if t == valid then return true end
        end
        return false
    end
    
    return self:setWithValidation("theme", theme, isValidTheme, "light")
end

return ThemeSettings
```

This modular architecture makes the settings system much more maintainable and follows modern software engineering principles while maintaining full backward compatibility. 