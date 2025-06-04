# Miniflux Browser Architecture

This directory contains the refactored modular browser architecture for the Miniflux plugin. The code has been organized into a clear separation of concerns following modern front-end patterns.

## Directory Structure

```
browser/
├── README.md                    # This file - architecture documentation
├── main_browser.lua            # Main browser coordinator (refactored)
├── lib/                        # Core library components
│   ├── base_browser.lua        # Base browser functionality 
│   └── browser_utils.lua       # Utility functions
├── features/                   # Feature modules (business logic)
│   ├── navigation_manager.lua  # Navigation state and back button logic
│   └── page_state_manager.lua  # Page position capture/restoration
└── screens/                    # Screen modules (UI presentation)
    ├── main_screen.lua         # Main menu (Unread/Feeds/Categories)
    ├── feeds_screen.lua        # Feeds list and feed entries
    └── categories_screen.lua   # Categories list and category entries
```

## Architecture Principles

### 1. **Separation of Concerns**
- **Screens**: Handle UI presentation and user interactions for specific views
- **Features**: Contain business logic and state management
- **Main Browser**: Acts as a coordinator, delegating to appropriate modules

### 2. **Module Pattern**
Each module follows a consistent pattern:
- `ModuleName:new()` - Object instantiation
- `ModuleName:init(browser)` - Initialization with browser reference
- Clear public API with focused responsibilities

### 3. **Dependency Injection**
The main browser injects itself into all modules, allowing:
- Access to shared services (API, settings, debug logging)
- Centralized coordination without tight coupling

## Key Features

### Navigation Management
- **Smart Back Navigation**: Remembers where user came from
- **Page Position Preservation**: Returns to exact page and item position
- **Navigation Stack**: Maintains breadcrumb trail of user actions

### Screen Modules
- **Main Screen**: Handles main menu with counts
- **Feeds Screen**: Manages feed list and individual feed entries
- **Categories Screen**: Manages category list and category entries

### Feature Modules
- **Navigation Manager**: Back button logic and navigation state
- **Page State Manager**: Captures and restores user position in lists

## Benefits of This Structure

1. **Maintainability**: Easy to find and modify specific functionality
2. **Testability**: Each module can be tested independently
3. **Readability**: Clear separation makes code easier to understand
4. **Extensibility**: New features (like History) can be added as new modules
5. **Reusability**: Feature modules can be reused across different screens

## Adding New Features

To add a new feature (e.g., History browser):

1. **Create Screen Module**: `screens/history_screen.lua`
2. **Add Feature Logic**: Extend existing features or create new ones in `features/`
3. **Update Main Browser**: Add delegation logic in `main_browser.lua`
4. **Update Navigation**: Add new screen type to navigation manager

## Example: Adding History Feature

```lua
-- screens/history_screen.lua
local HistoryScreen = {}

function HistoryScreen:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function HistoryScreen:init(browser)
    self.browser = browser
end

function HistoryScreen:show()
    -- Implementation for showing history
end

return HistoryScreen
```

This modular approach makes the codebase much more manageable and follows modern software architecture principles. 