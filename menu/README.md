# Menu Module

This directory contains modules responsible for KOReader menu construction, management, and all settings dialogs.

## Files

### `menu_manager.lua`
Handles the complete menu system for Miniflux including:
- **Menu Structure**: Builds the complete Miniflux menu hierarchy  
- **Dynamic Content**: Handles dynamic menu text and state updates
- **Settings Integration**: Direct integration with settings data layer
- **Settings Dialogs**: All settings configuration dialogs
- **Connection Testing**: Server connectivity testing
- **Submenu Generation**: Dynamic sort order and direction menus
- **Modular Construction**: Breaks functionality into focused, testable methods

## Architecture

Follows the single responsibility principle for menu management while consolidating related UI functionality:
- **Menu Building**: Individual builder methods for each menu section
- **Dialog Management**: All settings dialogs within the menu context
- **Direct Settings Access**: Simplified access to settings data layer
- **Clean Dependencies**: Receives initialized plugin instance with all dependencies

## Menu Structure

```
Miniflux
├── Read entries
└── Settings
    ├── Server address
    ├── Entries limit - [current limit]
    ├── Sort order - [current order]
    ├── Sort direction - [current direction]  
    ├── Include images - [ON/OFF]
    └── Test connection
```

## Settings Dialog Methods

All previously separate settings dialog functionality is now included:
- `showServerSettings()` - Configure server address and API token
- `showLimitSettings()` - Set entries limit with validation  
- `testConnection()` - Test server connectivity
- `getOrderSubMenu()` - Dynamic sort order menu
- `getDirectionSubMenu()` - Dynamic sort direction menu
- `getIncludeImagesSubMenu()` - Image inclusion toggle menu

## Usage

```lua
local MenuManager = require("menu/menu_manager")
local menu_manager = MenuManager:new()

-- Add to KOReader main menu (includes all dialogs)
menu_manager:addToMainMenu(menu_items, plugin_instance)

-- Or build just the menu structure
local menu_structure = menu_manager:buildMainMenu(plugin_instance)

-- Dialog methods are now internal (called from menu callbacks)
```

## Benefits

- **Unified Menu System**: All menu-related functionality in one place
- **Simpler Architecture**: Eliminated separate settings dialogs module
- **Better Cohesion**: Menu building and menu actions together
- **Direct Data Access**: No intermediate abstraction layers
- **Easier Maintenance**: Single module for all menu concerns
- **Testability**: All menu functionality testable in one place
- **Dynamic Content**: Real-time updates based on settings without recreation
- **Modularity**: Each menu section has its own builder method
- **Testability**: Individual menu components can be tested in isolation
- **Maintainability**: Easy to modify menu structure without affecting other code
- **Clean Code**: Complex menu logic extracted from main plugin file 