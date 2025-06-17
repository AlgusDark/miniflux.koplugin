# Browser Architecture Refactor

## Problem
The original browser architecture was overengineered with too many layers:
- Complex screen coordinator managing multiple screen classes
- Separate screen classes for main, feeds, categories (lots of duplication)
- Complex navigation context management
- Over-abstracted UI components

## Solution: Provider Pattern
Simplified to a provider-based architecture where:
- `main_browser.lua` orchestrates everything directly
- Simple data providers just fetch and format data
- No complex screen coordinators or separate screen classes

## New Architecture

```
browser/
├── main_browser_simple.lua     # Direct orchestrator (replaces coordinator complexity)
├── providers/                  # Simple data providers
│   ├── categories_provider.lua # Provides categories data
│   ├── feeds_provider.lua      # Provides feeds data
│   └── entries_provider.lua    # Reusable entries provider
├── features/                   # Navigation features (kept)
│   ├── navigation_manager.lua
│   └── page_state_manager.lua
├── utils/                      # Utilities (kept)
└── lib/                        # Base browser (kept)
```

## What Was Removed/Simplified

### Removed Files (overengineered):
- `coordinators/screen_coordinator.lua` - 334 lines of complex coordination
- `screens/main_screen.lua` - 148 lines 
- `screens/feeds_screen.lua` - 252 lines
- `screens/categories_screen.lua` - 209 lines
- `screens/base_screen.lua` - 209 lines
- `screens/ui_components.lua` - 291 lines
- `main_browser.lua` - 308 lines of complex browser coordination

**Total removed: ~1,748 lines of complex code**

### Cleaned Up:
- Removed unused `showEntriesList` method from `base_browser.lua`
- Removed broken import of deleted `ScreenUI` module
- Empty `coordinators/` and `screens/` directories (legacy structure)

### Replaced With (simple):
- `providers/categories_provider.lua` - 58 lines
- `providers/feeds_provider.lua` - 76 lines  
- `providers/entries_provider.lua` - 118 lines
- `main_browser_simple.lua` - 434 lines

**Total new: ~686 lines of simple code**

## Benefits

1. **Less Code**: Reduced from ~1,748 lines to ~686 lines (-61%)
2. **Simpler Mental Model**: Providers just provide data, browser handles UI
3. **No Duplication**: Single entries provider reused for feeds/categories/unread
4. **Direct Control**: Main browser directly orchestrates instead of delegating through layers
5. **Easier to Understand**: Clear data flow without complex abstractions

## Provider Pattern Explained

### Categories Provider
```lua
-- Just provides categories data and formats it
function CategoriesProvider:getCategories(api)
    return api.categories:getCategories(true)
end

function CategoriesProvider:toMenuItems(categories)
    -- Convert to menu items
end
```

### Entries Provider (Reusable)
```lua
-- Handles all entry types based on context
function EntriesProvider:getUnreadEntries(api, settings)
function EntriesProvider:getFeedEntries(api, settings, feed_id)  
function EntriesProvider:getCategoryEntries(api, settings, category_id)
```

### Main Browser (Direct Orchestration)
```lua
function SimpleBrowser:onMenuSelect(item)
    if item.action_type == "categories" then
        self:showCategories()  -- Direct call
    elseif item.action_type == "category_entries" then
        self:showCategoryEntries(category_data.id, category_data.title)
    end
end

function SimpleBrowser:showCategories()
    -- Get data from provider
    local success, categories = self.categories_provider:getCategories(self.api)
    -- Format with provider
    local menu_items = self.categories_provider:toMenuItems(categories)
    -- Update browser directly
    self:updateBrowser(_("Categories"), menu_items, subtitle, nav_data)
end
```

## Usage

Instead of complex screen coordination:
```lua
-- OLD (complex)
self.screen_coordinator:getCategoriesScreen():show()
```

Now simple direct calls:
```lua
-- NEW (simple)  
self:showCategories()
```

The provider pattern eliminates overengineering while maintaining all functionality with much cleaner, more understandable code. 