# Settings UI Module

This directory contains user interface components related to settings configuration.

## Files

### `settings_dialogs.lua`
Handles all settings-related UI dialogs and interactions:
- **Server Settings Dialog**: Configure server address and API token
- **Limit Settings Dialog**: Set entries limit with validation
- **Connection Testing**: Test server connectivity
- **Menu Generation**: Dynamic sort order and direction menus
- **Settings Integration**: Direct integration with settings modules

## Usage

```lua
local SettingsDialogs = require("settings/ui/settings_dialogs")
local dialogs = SettingsDialogs:new()
dialogs:init(settings_manager, api_client)

-- Show various dialogs
dialogs:showServerSettings()
dialogs:showLimitSettings()
dialogs:testConnection()

-- Get dynamic menus
local order_menu = dialogs:getOrderSubMenu()
local direction_menu = dialogs:getDirectionSubMenu()
```

## Architecture

Follows the same dependency injection pattern as other settings modules:
- **Initialization**: Requires SettingsManager and API client instances
- **Separation of Concerns**: Only handles UI presentation, delegates business logic
- **Integration**: Works seamlessly with the modular settings architecture 