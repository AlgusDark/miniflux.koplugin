# Miniflux Browser Architecture

This directory contains the simplified browser architecture using the provider pattern. The architecture eliminates overengineering by using simple data providers orchestrated by a main browser.

## Directory Structure

```
browser/
├── README.md                    # This file - architecture documentation
├── main_browser_simple.lua     # Simplified main browser (direct orchestration)
├── providers/                  # Simple data providers
│   ├── categories_provider.lua # Categories data provider
│   ├── feeds_provider.lua      # Feeds data provider  
│   └── entries_provider.lua    # Reusable entries provider
├── features/                   # Navigation features (business logic)
│   ├── navigation_manager.lua  # Navigation state and back button logic
│   └── page_state_manager.lua  # Page position capture/restoration
├── lib/                        # Base components
│   ├── base_browser.lua        # Base browser functionality 
│   └── ui_components.lua       # UI helper components
├── ui/                         # Browser initialization
│   └── browser_launcher.lua    # Browser launcher and setup
└── utils/                      # Utility modules
    ├── browser_utils.lua        # General browser utilities
    ├── sorting_utils.lua        # Sorting and filtering operations
    ├── entry_utils.lua          # Entry downloading and processing
    ├── navigation_utils.lua     # Entry navigation and file management
    ├── image_utils.lua          # Image processing utilities
    ├── html_utils.lua           # HTML generation utilities
    └── progress_utils.lua       # Progress tracking utilities
```

## Architecture Principles

### 1. **Provider Pattern**
Simple data providers that just fetch and format data:
- **Providers**: Just provide data, no UI logic
- **Main Browser**: Orchestrates everything directly
- **Single Responsibility**: Each provider handles one data type
- **Reusability**: Entries provider used for feeds, categories, and unread

### 2. **Direct Orchestration**
No complex intermediary layers:
- Main browser calls providers directly
- Providers return formatted data
- Browser updates UI immediately
- Clear, linear data flow

### 3. **Minimal Abstraction**
Only abstract what needs to be reused:
- Entries provider reused across contexts
- Navigation features shared but simple
- No over-engineered screen classes
- Direct method calls instead of delegation

### 4. **Focused Utilities**
Specialized utility modules for specific tasks:
- **browser_utils.lua**: API options and common browser functions
- **entry_utils.lua**: Entry downloading and file management
- **navigation_utils.lua**: Entry navigation between entries
- **image_utils.lua**: Image discovery and downloading
- **html_utils.lua**: HTML document generation
- **progress_utils.lua**: Progress tracking and user feedback

## Module Responsibilities

### `main_browser_simple.lua` - Direct Orchestrator
- **Menu Handling**: Process user selections and route to appropriate actions
- **Data Coordination**: Call providers to get data and format for display
- **UI Updates**: Update browser interface with new content
- **Context Management**: Track current browsing context (main, feeds, categories, entries)
- **Navigation**: Handle back button and view transitions

### `providers/` - Data Provider Modules
- **CategoriesProvider**: Fetch categories with counts, format as menu items
- **FeedsProvider**: Fetch feeds and counters, format with unread/total counts
- **EntriesProvider**: Reusable provider for unread, feed, and category entries
- **Simple Interface**: Just data fetching and formatting, no UI logic

### `features/` - Navigation Features
- **NavigationManager**: Smart back navigation and navigation state management
- **PageStateManager**: Page position capture and restoration for smooth navigation
- **Focused Scope**: Only handle navigation concerns, not data or UI

### `utils/` - Specialized Utilities
- **browser_utils.lua**: API options building and common browser operations
- **entry_utils.lua**: Entry downloading, file management, KOReader integration
- **navigation_utils.lua**: Entry-to-entry navigation and read/unread operations
- **image_utils.lua**: Image discovery, downloading, and HTML processing
- **html_utils.lua**: HTML document generation and content cleaning
- **progress_utils.lua**: User feedback during long operations

## Benefits of This Architecture

### 1. **Simplicity**
- 61% less code (1,748 → 686 lines)
- Direct orchestration instead of complex delegation
- Clear data flow: Provider → Browser → UI
- No overengineered abstractions

### 2. **Maintainability**
- Easy to understand and modify
- Single main browser file controls everything
- Providers are simple and focused
- Clear separation between data and UI

### 3. **Reusability**
- Single entries provider handles all entry contexts
- Common utilities shared across the browser
- Navigation features work consistently
- No duplication between similar screens

### 4. **Performance**
- Less code to load and execute
- Direct method calls instead of delegation layers
- Simple caching where needed
- Focused utility modules

### 5. **Extensibility**
- Add new providers for new data types
- Extend existing providers with new methods
- Main browser easily handles new actions
- Clear patterns to follow

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

### Basic Browser Usage
```lua
local SimpleBrowser = require("browser/main_browser_simple")
local browser = SimpleBrowser:new{
    settings = settings,
    api = api,
    download_dir = download_dir,
    unread_count = 50,
    feeds_count = 25,
    categories_count = 8
}
```

### Provider Usage
```lua
-- Categories
local categories_provider = CategoriesProvider:new()
local success, categories = categories_provider:getCategories(api)
local menu_items = categories_provider:toMenuItems(categories)

-- Entries (reusable)
local entries_provider = EntriesProvider:new()
local success, result = entries_provider:getFeedEntries(api, settings, feed_id)
local menu_items = entries_provider:toMenuItems(result.entries, false)
```

### Adding New Features
To add a new data type (e.g., Bookmarks):

1. **Create Provider**: `providers/bookmarks_provider.lua`
2. **Add Methods**: `getBookmarks()`, `toMenuItems()`
3. **Update Main Browser**: Add `showBookmarks()` method
4. **Add Menu Action**: Handle `bookmarks` action type

Simple and straightforward - no complex coordination or screen management needed. 