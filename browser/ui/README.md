# Browser UI Module

This directory contains user interface components related to browser initialization and launching.

## Files

### `browser_launcher.lua`
Handles browser initialization, data fetching, and main screen creation:
- **Data Fetching**: Retrieves unread counts, feeds count, and categories count
- **Error Handling**: Robust error handling for network and API failures
- **Loading States**: User feedback during data loading operations
- **Browser Creation**: Initializes and launches the main browser interface
- **Integration**: Coordinates between API, settings, and browser modules

## Usage

```lua
local BrowserLauncher = require("browser/ui/browser_launcher")
local launcher = BrowserLauncher:new()
launcher:init(settings_manager, api_client, download_dir)

-- Launch the main browser
launcher:showMainScreen()
```

## Architecture

Follows the same dependency injection pattern as other modules:
- **Initialization**: Requires SettingsManager, API client, and download directory
- **Separation of Concerns**: Handles UI orchestration, delegates to specialized modules
- **Error Recovery**: Graceful handling of network errors with user feedback
- **Modular Design**: Coordinates between multiple specialized modules

## Data Flow

1. **Configuration Check**: Validates server settings before proceeding
2. **API Initialization**: Sets up API client with current settings
3. **Data Fetching**: Retrieves counts for main menu (unread, feeds, categories)
4. **Browser Creation**: Instantiates and configures the main browser
5. **Error Handling**: Provides user feedback for any failures

## Benefits

- **Clean Separation**: Browser initialization separated from browser functionality
- **Robust Error Handling**: Network failures don't crash the interface
- **User Feedback**: Loading states and error messages keep users informed
- **Modular Integration**: Works seamlessly with the browser architecture 