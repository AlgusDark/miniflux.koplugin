# Architecture Analysis & Feed Reader Plugin Design

## Overview

This document captures the comprehensive architectural analysis and design decisions for the KOReader Feed Reader plugin (formerly Miniflux plugin). It serves as a reference for future development and architectural decisions.

## Evolution: From Single Provider to Multi-Provider Architecture

### Initial Assessment: Over-Engineering vs User Value

**Original Problem:** We initially considered creating separate plugins for different content providers, which led to plugin loading order issues and dependency hell.

**Key Insight:** After thorough analysis, we determined that a **single plugin with internal providers** is the optimal architecture.

### Final Architecture Decision: Single Plugin + Container DI + Internal Providers

**Chosen Architecture:**
```
feedreader.koplugin/  # Renamed from miniflux.koplugin
├── main.lua                      # Plugin orchestrator & lifecycle manager
├── container.lua                 # Dependency injection container
├── core/                         # Shared infrastructure
│   ├── browser/
│   │   ├── base_browser.lua      # Core browser functionality
│   │   └── browser_factory.lua   # Browser creation patterns
│   ├── settings/
│   │   └── base_settings.lua     # Core settings infrastructure
│   └── ui/
│       ├── provider_menu.lua     # Provider selection UI
│       └── provider_settings.lua # Provider enable/disable
└── providers/                    # Internal provider modules
    ├── miniflux/
    │   ├── miniflux_provider.lua  # Provider implementation
    │   ├── miniflux_api.lua      # API client
    │   ├── miniflux_browser.lua  # Provider-specific browser
    │   └── miniflux_settings.lua # Provider-specific settings
    ├── readeck/                  # Future provider
    └── hackernews/               # Future provider
```

**Why This Architecture:**
✅ **No plugin loading order issues** - Single plugin controls everything  
✅ **Clean separation** - Providers are internal modules, not separate plugins  
✅ **Container DI benefits** - Lazy loading, memory management, clean dependencies  
✅ **User control** - Enable/disable providers within single plugin  
✅ **Scalable** - Easy to add new providers as internal modules

### Rejected Alternatives

#### 1. Multiple Separate Plugins ❌
**Problem:** Plugin loading order is not guaranteed in KOReader
- Provider plugins might load before core plugin
- User could disable core but keep providers  
- Cross-plugin dependencies create fragility

#### 2. Manual DI for Multi-Provider ❌  
**Problem:** Doesn't scale beyond 2-3 providers
- `main.lua` becomes 300+ line god object
- Tight coupling between all providers
- Complex browser creation for each provider

#### 3. Provider Abstraction Over Current Code ❌
**Problem:** 80%+ refactoring required for theoretical benefits
- Codebase is heavily RSS/Miniflux-specific
- No concrete plans for other provider types
- Over-engineering for imaginary requirements

## KOReader Plugin Lifecycle Management

### Plugin Loading & Initialization

**KOReader Plugin Lifecycle:**
```
Application Start → FileManager/ReaderUI Init → PluginLoader:loadPlugins() → Plugin:init()
├── FileManager context: loads non-doc-only plugins
└── ReaderUI context: loads all plugins

Application Context Switch:
FileManager → ReaderUI: PluginLoader:finalize() → new Plugin instances created
ReaderUI → FileManager: PluginLoader:finalize() → new Plugin instances created

Application Shutdown: PluginLoader:finalize() → Plugin instances destroyed
```

**Critical Insights:**
1. **Multiple Plugin Instances:** Plugin gets instantiated once per UI context (FileManager vs ReaderUI)
2. **No Guaranteed Persistence:** Plugin instances are destroyed and recreated on context switches
3. **Finalization Happens:** `PluginLoader:finalize()` clears all plugin instances

### Cleanup Considerations & Testing Needed

**Memory Management Concerns:**
```lua
-- Example cleanup scenarios to test:
1. User opens Feed Reader in FileManager → switches to ReaderUI → back to FileManager
   → Are all browser instances properly cleaned up?
   
2. User opens browser, downloads entries → switches UI context → returns
   → Are download processes still running? Are temp files cleaned up?
   
3. User has API requests in progress → switches context  
   → Are network requests cancelled or do they complete and leak memory?
```

**Required Cleanup Implementation:**
```lua
-- main.lua
function FeedReader:onCloseWidget()
    logger.info("FeedReader: Cleaning up plugin instance")
    
    -- Clean container cache
    if self.container then
        self.container:cleanup()
    end
    
    -- Close any open browsers
    self:closeAllBrowsers()
    
    -- Cancel any background operations
    self:cancelBackgroundOperations()
    
    -- Save settings
    if self.settings then
        self.settings:save()
    end
end

-- container.lua  
function Container:cleanup()
    logger.info("Container: Cleaning up cached services")
    
    -- Cleanup cached services
    for name, service in pairs(self._cache) do
        if service.cleanup then
            service:cleanup()
        end
    end
    
    -- Clear cache with weak references for GC
    self._cache = setmetatable({}, { __mode = "v" })
    self._initializing = {}
end
```

## Container DI Implementation Details

### Service Lifecycle Management

**Container Responsibilities:**
1. **Lazy Creation:** Services created only when first accessed
2. **Caching:** Same instance returned for subsequent requests  
3. **Cleanup:** Proper teardown when plugin is destroyed
4. **Provider Management:** Register/unregister internal providers

```lua
-- container.lua - Core implementation
local Container = {}

function Container:new(plugin)
    local instance = {
        plugin = plugin,
        settings = plugin.settings,
        -- Weak references allow automatic GC
        _cache = setmetatable({}, { __mode = "v" }),
        -- Prevent circular dependency loops
        _initializing = {},
        -- Provider registry
        _providers = {},
    }
    setmetatable(instance, self)
    return instance
end

-- Provider management
function Container:registerProvider(name, provider)
    self._providers[name] = provider
    logger.info("Container: Registered provider", name)
end

function Container:getProviders()
    return self._providers
end

-- Lazy service creation with circular dependency detection
function Container:getMinifluxApi()
    if self._cache.miniflux_api then
        return self._cache.miniflux_api
    end
    
    if self._initializing.miniflux_api then
        error("Circular dependency detected: miniflux_api")
    end
    
    self._initializing.miniflux_api = true
    
    local MinifluxAPI = require("providers/miniflux/miniflux_api")
    local miniflux_api = MinifluxAPI:new({
        settings = self:getMinifluxSettings()
    })
    
    self._cache.miniflux_api = miniflux_api
    self._initializing.miniflux_api = nil
    
    return miniflux_api
end
```

## Current Architecture Issues (Post-Refactoring Analysis)

### Misplaced Domain Logic (Still Needs Fixing)

**Files incorrectly located in `utils/`:**

#### 1. `utils/entry_utils.lua` → `providers/miniflux/entry_entity.lua`
**Why:** Entry-specific business logic, not generic utilities
- Entry validation rules  
- Miniflux-specific file operations
- DocSettings integration with miniflux metadata

#### 2. `utils/navigation.lua` → `core/services/navigation_service.lua`
**Why:** Core navigation service that could be shared across providers
- RSS navigation algorithms (could be reused by other RSS providers)
- API orchestration patterns
- Time-based navigation logic

### Core vs Provider-Specific Code

**Core Infrastructure (Reusable):**
- ✅ Browser base classes → `core/browser/`
- ✅ Settings infrastructure → `core/settings/`  
- ✅ Navigation service → `core/services/navigation_service.lua`
- ✅ Generic utilities → `utils/` (error, notification, time_utils, etc.)

**Provider-Specific (Miniflux Only):**
- ✅ Miniflux API client → `providers/miniflux/miniflux_api.lua`
- ✅ Entry entity with miniflux logic → `providers/miniflux/entry_entity.lua`
- ✅ Miniflux-specific browser → `providers/miniflux/miniflux_browser.lua`

### Utils That Need Cleanup

#### Pure Generic (Keep in utils/)
- ✅ `error.lua`, `notification.lua`, `time_utils.lua`, `debugger.lua`

#### Mixed (Need refactoring)
- 🟡 `files.lua` - Split generic file ops from miniflux metadata loading
- 🟡 `html_utils.lua` - Remove miniflux-specific assumptions  
- 🟡 `images.lua` - Make purely generic image processing

## Application vs Domain Services (DDD Concepts)

### Application Services (Workflow Orchestration)
**Purpose:** Coordinate multiple operations, handle infrastructure concerns

**Example:** `services/entry_service.lua` ✅
```lua
function EntryService:readEntry(entry_data, browser)
    -- 1. Validate (delegates to domain)
    local valid, err = EntryUtils.validateForDownload(entry_data)
    
    -- 2. Orchestrate download (coordinates multiple services) 
    local success = EntryDownloader.startCancellableDownload({...})
    
    -- 3. Handle UI feedback (infrastructure concern)
    if not success then
        Notification:error(_("Failed to download and show entry"))
    end
end
```

**Characteristics:**
- Thin coordinators
- UI dependencies (notifications, browsers)
- Infrastructure dependencies
- Transaction management

### Domain Services (Business Logic)
**Purpose:** Implement complex business rules, work with domain objects

**Example:** `utils/navigation.lua` (should be `services/navigation_service.lua`)
```lua
function Navigation.navigateToEntry(entry_info, config)
    -- Business validation (domain rules)
    local valid, err = Navigation.validateNavigationInput(...)
    
    -- Domain logic (RSS navigation rules)
    local context = getBrowserContext() or { type = "global" }
    
    -- Complex business algorithm (time-based navigation)
    local nav_options = Navigation.buildNavigationOptions({
        published_unix = published_unix,
        direction = direction,
        context = context  -- Domain concept
    })
    
    -- Business rule: API first, fallback to local
    local success, result = Navigation.performNavigationSearch(...)
end
```

**Characteristics:**
- Rich business logic
- Domain concepts (feed/category context, time-based navigation)
- Should be infrastructure-agnostic (current code violates this)
- Complex algorithms

## Implementation Plan: Container DI + Multi-Provider Architecture

### Phase 1: Core Infrastructure Setup

```bash
# Create new directory structure
mkdir -p core/browser core/settings core/ui core/services
mkdir -p providers/miniflux

# Create container infrastructure
touch container.lua
touch core/browser/base_browser.lua
touch core/settings/base_settings.lua
touch core/ui/provider_menu.lua
```

### Phase 2: Move Domain Logic to Proper Locations

```bash
# Move entry logic to provider-specific location
mv utils/entry_utils.lua providers/miniflux/entry_entity.lua

# Move navigation to core (can be shared across RSS providers)
mv utils/navigation.lua core/services/navigation_service.lua

# Update import references:
# require("utils/entry_utils") → require("providers/miniflux/entry_entity")
# require("utils/navigation") → require("core/services/navigation_service")
```

### Phase 3: Implement Container DI

```bash
# Create container with lazy loading
# Implement provider registry
# Add cleanup mechanisms
# Update main.lua to use container orchestration
```

### Phase 4: Extract Core Components

```bash
# Extract reusable browser logic to core/browser/
# Create base settings infrastructure in core/settings/
# Move shared UI components to core/ui/
```

### Phase 5: Cleanup Testing & Validation

```bash
# Test plugin lifecycle cleanup
# Validate memory management
# Test UI context switching scenarios
# Performance benchmarking on low-powered devices
```

### Final Target Structure

```
feedreader.koplugin/
├── main.lua                           # Plugin orchestrator
├── container.lua                      # DI container with lifecycle management
├── core/                              # Shared infrastructure  
│   ├── browser/
│   │   ├── base_browser.lua          # Reusable browser functionality
│   │   └── browser_factory.lua       # Browser creation patterns
│   ├── settings/
│   │   └── base_settings.lua         # Core settings infrastructure  
│   ├── services/
│   │   └── navigation_service.lua    # Shared RSS navigation logic
│   └── ui/
│       ├── provider_menu.lua         # Provider selection interface
│       └── provider_settings.lua     # Enable/disable providers
├── providers/                         # Internal provider modules
│   └── miniflux/
│       ├── miniflux_provider.lua     # Provider implementation
│       ├── miniflux_api.lua          # Miniflux API client
│       ├── miniflux_browser.lua      # Provider-specific browser
│       ├── miniflux_settings.lua     # Provider-specific settings
│       └── entry_entity.lua          # Miniflux entry business logic
├── services/                          # Application services
│   ├── entry_service.lua             # Entry workflow orchestration
│   └── entry_downloader.lua          # Download management
└── utils/                             # Pure generic utilities
    ├── error.lua, notification.lua   # ✅ Already pure
    ├── files.lua                     # Generic file operations only
    ├── html_utils.lua                # Generic HTML processing
    └── images.lua                    # Generic image processing
```

## Testing Requirements & Cleanup Validation

### Critical Test Scenarios

**Plugin Lifecycle Testing:**
```lua
-- Test 1: Memory cleanup on context switch
1. Open Feed Reader in FileManager
2. Create browser, download entries
3. Switch to ReaderUI → back to FileManager  
4. Verify: No memory leaks, no orphaned processes

-- Test 2: Background operation cleanup
1. Start entry download
2. Switch UI context mid-download
3. Verify: Download cancelled properly, temp files cleaned up

-- Test 3: API request cleanup
1. Initiate API calls  
2. Force plugin termination
3. Verify: Network requests cancelled, no hanging connections

-- Test 4: Container cache validation
1. Create multiple services through container
2. Plugin destruction
3. Verify: All cached services cleaned up, weak references working
```

**Provider Management Testing:**
```lua
-- Test 5: Provider enable/disable
1. Disable miniflux provider
2. Restart plugin
3. Verify: Miniflux not in menu, no memory allocated for disabled provider

-- Test 6: Container lazy loading
1. Enable multiple providers
2. Access only one provider
3. Verify: Only accessed provider services created, others remain uninitialized
```

### Performance Benchmarks Required

**Memory Usage Testing:**
- Memory consumption with 0 providers accessed
- Memory growth pattern when accessing 1, 2, 3 providers
- Memory cleanup effectiveness after provider use
- Weak reference garbage collection validation

**Startup Performance:**
- Plugin initialization time with container DI
- First provider access latency (lazy loading overhead)
- Menu building performance with multiple providers

## Key Architectural Principles

1. **Single Plugin Architecture:** Avoid plugin loading order issues by keeping everything in one plugin
2. **Container DI for Scale:** Use dependency injection container to manage complexity as providers grow
3. **Lazy Loading:** Create services only when needed to conserve memory on low-powered devices
4. **Proper Cleanup:** Always implement cleanup methods for plugin lifecycle management
5. **Core vs Provider Separation:** Share common functionality through core modules, isolate provider-specific logic
6. **User Control:** Allow users to enable/disable providers within single plugin interface
7. **Memory Consciousness:** Use weak references and proper garbage collection for cached services

## Decision Rationale Summary

### Why Single Plugin + Container DI?

**✅ Chosen Approach Benefits:**
- No plugin loading order dependencies
- Clean separation of concerns through internal modules
- Memory-efficient lazy loading
- User control over enabled providers
- Scalable architecture for future providers
- Proper lifecycle management

**❌ Rejected Approaches:**
- **Multiple plugins:** Plugin loading order hell, dependency fragility
- **Manual DI without container:** Doesn't scale beyond 2-3 providers  
- **Provider abstraction over current code:** 80%+ refactoring for theoretical benefits

### Container DI Justification

**When Container DI Makes Sense:**
- Multi-provider architecture (our case)
- Complex dependency graphs
- Need for lazy loading
- Memory-constrained environments
- Plugin lifecycle management requirements

**When Container DI is Overkill:**
- Single provider with < 10 services (original concern was valid)
- Simple linear dependencies
- No memory constraints

**Our Situation:** Multi-provider vision + memory constraints = Container DI is appropriate

## Next Steps & Immediate Actions

### Priority 1: Test Current Cleanup
**Before implementing container**, validate current plugin cleanup:
```bash
# Test scenarios in current codebase:
1. Open miniflux browser → switch FileManager ↔ ReaderUI → check for leaks
2. Start download → switch context → verify cleanup
3. Active API calls → plugin termination → verify no hanging requests
```

### Priority 2: Implement Container Architecture
If cleanup testing reveals issues or if multi-provider development starts soon:
```bash
1. Create container.lua with basic provider registry
2. Move utils/entry_utils.lua → providers/miniflux/entry_entity.lua  
3. Move utils/navigation.lua → core/services/navigation_service.lua
4. Implement proper cleanup in main.lua:onCloseWidget()
5. Add comprehensive lifecycle testing
```

### Priority 3: Performance Validation
```bash
1. Memory benchmarks before/after container implementation
2. Startup time measurements  
3. Provider lazy loading effectiveness testing
4. Low-powered device validation (e.g., older Kindles)
```

This architecture provides a **scalable foundation** for multi-provider support while being **appropriate for current needs** and **memory-conscious for KOReader's target devices**. 