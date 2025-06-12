# Miniflux Browser Architecture

This directory contains the refactored modular browser architecture for the Miniflux plugin. The code has been organized following the same design patterns used in the `api/` and `settings/` folders, implementing modern software architecture principles.

## Directory Structure

```
browser/
├── README.md                    # This file - architecture documentation
├── main_browser.lua            # Main browser coordinator (Facade pattern)
├── lib/                        # Legacy library components (to be migrated)
│   ├── base_browser.lua        # Base browser functionality 
│   └── browser_utils.lua       # Legacy utilities (being replaced)
├── features/                   # Feature modules (business logic)
│   ├── navigation_manager.lua  # Navigation state and back button logic
│   └── page_state_manager.lua  # Page position capture/restoration
├── screens/                    # Screen modules (UI presentation)
│   ├── main_screen.lua         # Main menu (Unread/Feeds/Categories)
│   ├── feeds_screen.lua        # Feeds list and feed entries
│   └── categories_screen.lua   # Categories list and category entries
└── utils/                      # Utility modules (like api/utils/)
    ├── browser_utils.lua        # General browser utilities
    ├── sorting_utils.lua        # Sorting and filtering operations
    ├── entry_utils.lua          # Entry downloading and processing
    └── navigation_utils.lua     # Entry navigation and file management
```

## Architecture Principles

### 1. **Single Responsibility Principle (SRP)**
Each module has one clear responsibility:
- **Types**: Centralized type definitions and validation
- **Screens**: Handle UI presentation and user interactions for specific views
- **Features**: Contain business logic and state management  
- **Utils**: Focused utility modules for specific operations
- **Main Browser**: Acts as a coordinator, delegating to appropriate modules

### 2. **Dependency Injection**
Following the pattern from `api/` and `settings/`:
- Modules receive dependencies through `init()` methods
- Enables easy testing with mock dependencies
- Promotes loose coupling between modules

### 3. **Facade Pattern**
The `main_browser.lua` acts as a facade that:
- Provides a unified interface to all browser operations
- Handles initialization and coordination between modules
- Provides a clean, unified interface
- Simplifies client usage (like `api_client.lua` and `settings_manager.lua`)

### 4. **Modular Utilities**
The `utils/` directory follows the same pattern as `api/utils/`:
- **browser_utils.lua**: General browser functionality (API options, validation)
- **sorting_utils.lua**: Sorting and filtering operations
- **entry_utils.lua**: Entry downloading, processing, and file operations
- **navigation_utils.lua**: Entry navigation and file management

### 5. **Co-located Types**
Type definitions are placed directly in the files where they're used:
- Type annotations alongside implementations
- Data structure definitions in relevant modules
- No centralized type files to maintain
- Better IDE support and error detection

## Module Responsibilities

### Type Definitions (Co-located)
- Type aliases (`ActionType`, `ContextType`, `BrowserState`) defined where used
- Data structure definitions (`BrowserMenuItem`, `NavigationData`, etc.) in relevant modules
- Type validation handled through EmmyLua annotations
- Consistent typing through co-located annotations

### `main_browser.lua` - Main Coordinator
- **Initialization**: Set up all browser modules with dependencies
- **Delegation**: Route method calls to appropriate modules
- **Navigation**: Coordinate between different screens and features
- **Event Handling**: Process user interactions and delegate to screens

### `features/` - Business Logic Modules
- **NavigationManager**: Smart back navigation, page position preservation
- **PageStateManager**: Captures and restores user position in lists
- **Future**: Additional feature modules can be added (History, Bookmarks, etc.)

### `screens/` - UI Presentation Modules
- **MainScreen**: Handles main menu with counts
- **FeedsScreen**: Manages feed list and individual feed entries
- **CategoriesScreen**: Manages category list and category entries
- **Future**: Additional screen modules (HistoryScreen, SearchScreen, etc.)

### `utils/` - Utility Modules
- **browser_utils.lua**: API options building, validation, subtitle formatting
- **sorting_utils.lua**: Unified menu item sorting by unread count
- **entry_utils.lua**: Entry downloading, image processing, HTML generation, KOReader integration
- **navigation_utils.lua**: Entry navigation, marking read/unread, file management

## Benefits of This Architecture

### 1. **Maintainability**
- Easy to find and modify specific functionality
- Clear separation of concerns reduces cognitive load
- Consistent patterns across modules match `api/` and `settings/`

### 2. **Testability**
- Each module can be tested independently
- Dependency injection enables easy mocking
- Focused modules have fewer test scenarios

### 3. **Extensibility**
- New features can be added as new modules in `features/`
- New screens can be added to `screens/` directory
- New utilities can be added to `utils/` directory
- Existing modules can be enhanced without affecting others

### 4. **Performance**
- Modules can be loaded on-demand
- Specialized caching per domain
- Reduced memory footprint through focused modules

### 5. **Type Safety**
- Centralized type definitions prevent inconsistencies
- EmmyLua annotations throughout for IDE support
- Clear interfaces between modules

### 6. **Code Efficiency**
- **Eliminated Duplication**: Utility modules prevent code repetition
- **Improved Organization**: Clear module boundaries
- **Better Performance**: Focused modules load only what's needed
- **Enhanced Maintainability**: Easy to locate and modify functionality

## Design Pattern Consistency

This refactored browser architecture now follows the same excellent patterns as:

### API Architecture (`api/`)
- **Base Class**: `base_client.lua` → `lib/base_browser.lua`
- **Facade**: `api_client.lua` → `main_browser.lua`
- **Types**: Co-located with implementations
- **Utils**: `utils/` → `utils/`
- **Specialized Modules**: `entries_api.lua`, `feeds_api.lua` → `screens/*.lua`

### Settings Architecture (`settings/`)
- **Base Class**: `base_settings.lua` → pattern followed in features
- **Facade**: `settings_manager.lua` → `main_browser.lua`
- **Enums**: `enums.lua` → Co-located annotations
- **Specialized Modules**: `server_settings.lua`, `sorting_settings.lua` → `features/*.lua`

## Migration Status

### ✅ **Completed**
- Co-located type definitions in implementation files
- Modular utility system in `utils/`
- Consistent documentation and architecture

### 🔄 **In Progress**
- Updating existing modules to use new utilities
- Implementing dependency injection in `base_browser.lua`
- Migrating from `lib/browser_utils.lua` to `utils/` modules

### 📋 **Future Enhancements**
- Additional feature modules (History, Search, Bookmarks)
- Enhanced base browser class with dependency injection
- Additional screen modules for specialized views

## Usage Examples

### Basic Usage (Current)
```lua
local MainBrowser = require("browser/main_browser")
local browser = MainBrowser:new(config)
browser:showMainContent()
```

### Advanced Usage (New Modular API)
```lua
local SortingUtils = require("browser/utils/sorting_utils")
local EntryUtils = require("browser/utils/entry_utils")

-- Use simplified utilities
SortingUtils.sortByUnreadCount(items) -- Works for both feeds and categories
EntryUtils.showEntry(entry, api, download_dir, context)
```

### Adding New Features
To add a new feature (e.g., Search functionality):

1. **Create Feature Module**: `features/search_manager.lua`
2. **Create Screen Module**: `screens/search_screen.lua`
3. **Add Utilities**: `utils/search_utils.lua` if needed
4. **Update Main Browser**: Add delegation logic in `main_browser.lua`
5. **Update Types**: Add type annotations directly in the module files

This modular approach makes the codebase much more manageable and follows the same excellent design patterns established in the `api/` and `settings/` folders. 