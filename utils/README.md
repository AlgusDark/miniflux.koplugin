# Miniflux Utils Directory

This directory contains utility modules for the Miniflux KOReader plugin. The utilities are organized by domain and responsibility to improve maintainability and code organization.

## Utility Modules

### Core System Utilities
- **`file_utils.lua`** - File operations and string manipulation (only functions actually used)
- **`ui_components.lua`** - Reusable UI components and standardized dialogs
- **`progress_utils.lua`** - Progress tracking for long-running operations

### Entry Processing Utilities
- **`entry_utils.lua`** - Entry validation, file operations, and status management
- **`metadata_loader.lua`** - Loading entry metadata from filesystem
- **`navigation_context.lua`** - Global navigation state management

### Content Processing Utilities
- **`html_utils.lua`** - HTML document creation and processing
- **`image_discovery.lua`** - Image discovery and URL processing
- **`image_download.lua`** - HTTP image downloading
- **`image_utils.lua`** - Unified image processing interface (facade)

## Recent Improvements

### 1. Modular Image Processing
**Before:** `image_utils.lua` was 350 lines handling multiple concerns
**After:** Split into focused modules:
- `image_discovery.lua` - Image discovery and URL normalization
- `image_download.lua` - HTTP downloading with progress tracking
- `image_utils.lua` - Backward-compatible facade

### 2. YAGNI Compliance & Better Separation
**Before:** Generic `utils.lua` with unused functions, private service methods
**After:** Focused `file_utils.lua` with proper file utilities
- Moved `writeFile()` from private EntryService method to reusable utility
- Better separation of concerns - file operations belong in utilities
- No backward compatibility layers - direct imports only

## Usage Guidelines

### Import Patterns
```lua
-- File operations
local FileUtils = require("utils/file_utils")

-- Entry processing
local EntryUtils = require("utils/entry_utils")

-- UI components
local UIComponents = require("utils/ui_components") 
local ProgressUtils = require("utils/progress_utils")

-- Content processing
local HtmlUtils = require("utils/html_utils")
local ImageUtils = require("utils/image_utils")      -- HTML processing
local ImageDiscovery = require("utils/image_discovery") -- Image discovery
local ImageDownload = require("utils/image_download")   -- Image downloading
```

### Dependency Graph  
```
EntryService -> EntryUtils, ImageDiscovery, ImageDownload, ImageUtils, HtmlUtils, FileUtils, ProgressUtils, NavigationContext
ViewService -> UIComponents
ApiClient -> FileUtils
ImageUtils -> ImageDiscovery (HTML processing only)
```

## Benefits of Refactoring

1. **Single Responsibility** - Each module has a clear, focused purpose
2. **Reduced Complexity** - Smaller, more manageable files  
3. **Better Testability** - Focused modules are easier to test
4. **YAGNI Compliance** - Only functions that are actually used
5. **Maintainability** - Easier to locate and modify specific functionality
6. **Clear Dependencies** - Explicit imports show module relationships

## YAGNI Lessons Learned

### What We Removed (unused functions):
- `fileExists()` - KOReader already has `util.fileExists()`
- `writeFile()` - EntryService already has `_saveFile()`  
- `readFile()` - Not needed anywhere
- `getOrCreateDirectory()` - Not used
- `downloadImages()` - Entry processing uses single downloads in loops

### What We Kept (actually used):
- `rtrimSlashes()` - Used by API client
- `writeFile()` - Moved from EntryService to proper utility
- `downloadImage()` - Used by entry processing
- All discovery and HTML processing functions

### What We Improved:
- Removed backward compatibility re-exports
- Direct imports instead of facade patterns
- Proper separation: file operations in utilities, not services

## Final Directory Structure (Post-YAGNI)

```
utils/
├── README.md              # Documentation
├── file_utils.lua         # File operations - YAGNI compliant, no facades
├── ui_components.lua      # UI components 
├── progress_utils.lua     # Progress tracking
├── entry_utils.lua        # Entry operations
├── metadata_loader.lua    # Metadata loading
├── navigation_context.lua # Navigation state
├── html_utils.lua         # HTML processing
├── image_discovery.lua    # Image discovery - direct import
├── image_download.lua     # Image downloading - direct import
└── image_utils.lua        # HTML image processing only
```

**Total: 11 focused files with direct imports, no facades**

## Future Considerations

- **YAGNI First** - Don't create functions until they're actually needed
- **No Facades** - Use direct imports instead of backward compatibility layers
- **Proper Separation** - Move operations from services to utilities when reusable
- **Direct Dependencies** - Avoid re-export patterns that hide dependencies
- Monitor usage patterns before adding new utilities
- Prefer using existing KOReader utilities over creating duplicates 