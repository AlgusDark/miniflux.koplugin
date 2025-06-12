# Menu Module

This directory contains modules responsible for KOReader menu construction and management.

## Files

### `menu_manager.lua`
Handles the construction and management of Miniflux menu items:
- **Menu Structure**: Builds the complete Miniflux menu hierarchy  
- **Dynamic Content**: Handles dynamic menu text and state updates
- **Settings Integration**: Integrates with settings modules for real-time updates
- **Modular Construction**: Breaks menu building into focused, testable methods

## Architecture

Follows the single responsibility principle and modular design:
- **Builder Pattern**: Uses individual builder methods for each menu section
- **Separation of Concerns**: Only handles menu construction, delegates actions to other modules
- **Dynamic Updates**: Supports real-time menu updates based on settings changes
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

## Usage

```lua
local MenuManager = require("menu/menu_manager")
local menu_manager = MenuManager:new()

-- Add to KOReader main menu
menu_manager:addToMainMenu(menu_items, plugin_instance)

-- Or build just the menu structure
local menu_structure = menu_manager:buildMainMenu(plugin_instance)
```

## Benefits

- **Modularity**: Each menu section has its own builder method
- **Testability**: Individual menu components can be tested in isolation
- **Maintainability**: Easy to modify menu structure without affecting other code
- **Dynamic Content**: Real-time updates based on settings without menu recreation
- **Clean Code**: Complex menu logic extracted from main plugin file 