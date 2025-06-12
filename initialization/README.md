# Initialization Module

This directory contains modules responsible for plugin bootstrap and setup operations.

## Files

### `plugin_initializer.lua`
Handles the initialization of all Miniflux plugin components:
- **Directory Setup**: Creates and validates download directories
- **Module Initialization**: Sets up all plugin modules with dependency injection
- **Settings Bootstrap**: Initializes settings manager and loads defaults
- **API Setup**: Configures API client with current settings
- **Error Handling**: Provides proper error handling during initialization

## Architecture

Follows the dependency injection pattern used throughout the codebase:
- **Single Responsibility**: Only handles initialization logic
- **Clean Dependencies**: Takes plugin instance and initializes all required modules
- **Error Recovery**: Graceful handling of initialization failures
- **Logging**: Comprehensive logging for debugging initialization issues

## Usage

```lua
local PluginInitializer = require("initialization/plugin_initializer")
local initializer = PluginInitializer:new()

-- Initialize all plugin components
local success = initializer:initializePlugin(plugin_instance)
if not success then
    -- Handle initialization failure
end
```

## Benefits

- **Separation of Concerns**: Initialization logic separated from main plugin coordination
- **Testability**: Easy to test initialization logic in isolation
- **Error Handling**: Robust error handling with proper logging
- **Maintainability**: Easy to modify initialization sequence without affecting main plugin 