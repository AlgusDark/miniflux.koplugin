# Event-Driven Architecture Migration

## Overview

This document outlines the migration from dependency injection (DI) to KOReader's native Events system for the Miniflux plugin. The goal is to create a more maintainable, KOReader-native architecture that leverages proven event-driven communication patterns.

## Background

### Current State: Dependency Injection
The plugin currently uses manual dependency injection throughout `main.lua`:

```lua
self.settings = MinifluxSettings:new()
self.api_client = APIClient:new({ settings = self.settings })
self.miniflux_api = MinifluxAPI:new({ api_client = self.api_client })
self.entry_service = EntryService:new({
    settings = self.settings,
    miniflux_api = self.miniflux_api,
    -- ... more dependencies
})
```

**Problems with Current Approach:**
- Complex dependency graphs that are hard to maintain
- Tight coupling between modules
- Difficult to extend or modify without breaking changes
- Not aligned with KOReader's native patterns

### Target State: Event-Driven Communication
Using KOReader's parent-child pattern with event-based configuration:

```lua
-- Plugin as central registry (like ReaderUI)
self.api_client = APIClient:new({ plugin = self })
self.miniflux_api = MinifluxAPI:new({ plugin = self })

-- Modules access siblings through parent
local settings = self.plugin.settings
local api = self.plugin.api_client

-- Settings changes broadcast events
UIManager:broadcastEvent(Event:new("MinifluxSettingsChanged", { key = "server_address", value = new_value }))
```

## KOReader's Module System (Research Findings)

### Core Architecture Patterns

#### 1. Parent-Child Module Access (Primary Pattern)
KOReader avoids singletons and uses parent references for module communication:

```lua
-- Module registration in ReaderUI
self:registerModule('view', ReaderView:new{ui = self, ...})
self:registerModule('highlight', ReaderHighlight:new{ui = self, ...})

-- Module access via parent reference
self.ui.view.footer:addContent()
self.ui.highlight:toggle()
if self.ui.view then  -- Always check existence
    self.ui.view:refresh()
end
```

#### 2. Event Broadcasting (Secondary Pattern)
Events are used for loose coupling between distant modules:

- **`UIManager:sendEvent(event)`**: Sends to widgets top-to-bottom, stops at first handler returning true
- **`UIManager:broadcastEvent(event)`**: Sends to ALL widgets regardless of consumption  
- **`self.ui:handleEvent(event)`**: Direct event sending to specific widget

#### 3. Module Registration Pattern
From actual `ReaderUI:registerModule`:

```lua
function ReaderUI:registerModule(name, ui_module, always_active)
    if name then
        self[name] = ui_module  -- Direct property access
        ui_module.name = "reader" .. name
    end
    table.insert(self, ui_module)  -- Widget hierarchy
    if always_active then
        table.insert(self.active_widgets, ui_module)
    end
end
```

#### 4. Memory Management and Cleanup
KOReader uses explicit cleanup without singletons:

```lua
function Module:onCloseWidget()
    UIManager:unschedule(self.task)
    if self.handle then
        self.handle:close()
    end
    self.task = nil
end
```

### Key Events for Our Use Case

#### 1. FlushSettings Event
- **Trigger**: `UIManager:close()` calls `UIManager:flushSettings()`
- **Purpose**: Ensures settings persistence before app termination
- **Implementation**: Located in `ui/uimanager.lua:1665`
- **Handler**: `function Module:onFlushSettings()`

#### 2. Custom Plugin Events
We'll define custom events for inter-module communication:
- `MinifluxSettingsChanged`: Settings value updates
- `MinifluxApiConfigured`: API client configuration complete
- `MinifluxEntryDownloaded`: Entry download completion
- `MinifluxNavigationChanged`: Browser navigation state changes

## Migration Plan

### Phase 1: MVP Implementation

#### Step 1: Add Event Infrastructure to Main Plugin

**File: `src/main.lua`**

1. Add module registration method following ReaderUI pattern:
```lua
---Register a module with the plugin for event handling (following ReaderUI pattern)
---@param name string Module name
---@param module table Module instance
---@param always_active? boolean Whether module should always receive events
function Miniflux:registerModule(name, module, always_active)
    if name then
        self[name] = module  -- Direct property access like ReaderUI
        module.name = "miniflux_" .. name
    end
    table.insert(self, module)  -- Add to widget hierarchy
    if always_active then
        if not self.active_modules then
            self.active_modules = {}
        end
        table.insert(self.active_modules, module)
    end
end
```

2. Add module access method:
```lua
---Get a registered module by name
---@param name string Module name
---@return table|nil Module instance or nil if not found
function Miniflux:getModule(name)
    return self[name]
end
```

3. Add FlushSettings handler:
```lua
---Handle FlushSettings event from UIManager
function Miniflux:onFlushSettings()
    logger.dbg('[Miniflux:Main] Handling FlushSettings event')
    
    -- Save current plugin state
    if self.settings then
        self.settings:save()
    end
    
    -- Broadcast to registered modules
    UIManager:broadcastEvent(Event:new("MinifluxFlushSettings"))
end
```

#### Step 2: Make Settings Event-Aware

**File: `src/settings/settings.lua`**

1. Add event broadcasting on setting changes:
```lua
---Handle property writing with auto-save and event broadcasting
---@param key string Property name
---@param value any Property value
function MinifluxSettings:__newindex(key, value)
    -- Handle settings
    if DEFAULTS[key] ~= nil then
        local old_value = self.settings:readSetting(key, DEFAULTS[key])
        self.settings:saveSetting(key, value)
        
        -- Broadcast settings change event
        local UIManager = require('ui/uimanager')
        local Event = require('ui/event')
        UIManager:broadcastEvent(Event:new("MinifluxSettingsChanged", {
            key = key,
            old_value = old_value,
            new_value = value
        }))
    else
        -- For unknown keys, set them directly on the object
        rawset(self, key, value)
    end
end
```

2. Add FlushSettings handler:
```lua
---Handle FlushSettings event
function MinifluxSettings:onMinifluxFlushSettings()
    logger.dbg('[Miniflux:Settings] Handling FlushSettings event')
    self:save()
end
```

#### Step 3: Event-Driven API Client

**File: `src/api/api_client.lua`**

1. Add parent reference for module access:
```lua
---Create a new API instance with parent reference
---@param config table Configuration with plugin parent reference
---@return APIClient
function APIClient:new(config)
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.plugin = config.plugin  -- Store parent reference
    
    return instance
end
```

2. Add settings event handler:
```lua
---Handle settings change events
---@param args table Event arguments with key, old_value, new_value
function APIClient:onMinifluxSettingsChanged(args)
    if args.key == 'server_address' or args.key == 'api_token' then
        logger.dbg('[Miniflux:APIClient] Settings changed:', args.key, '=>', args.new_value)
        -- Access settings through parent plugin (no singletons!)
        -- Settings are automatically updated since we access them dynamically
    end
end
```

3. Update makeRequest to access settings through parent:
```lua
function APIClient:makeRequest(method, endpoint, config)
    config = config or {}
    
    -- Access settings through parent plugin instead of stored reference
    local settings = self.plugin.settings
    local server_address = settings.server_address
    local api_token = settings.api_token
    
    -- ... rest of method unchanged
end
```

#### Step 4: Update MinifluxAPI for Event Integration

**File: `src/api/miniflux_api.lua`**

1. Add parent reference pattern:
```lua
---Create a new MinifluxAPI instance with parent reference
---@param config table Configuration with plugin parent reference
---@return MinifluxAPI
function MinifluxAPI:new(config)
    local instance = {
        plugin = config.plugin,  -- Store parent reference
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end
```

2. Access API client through parent:
```lua
---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@param config? table Configuration including optional dialogs
---@return MinifluxEntriesResponse|nil result, Error|nil error
function MinifluxAPI:getEntries(options, config)
    config = config or {}
    
    -- Access api_client through parent plugin
    local api_client = self.plugin.api_client
    
    return api_client:get('/entries', {
        query = options,
        dialogs = config.dialogs,
    })
end
```

3. Add event handler (optional - mainly for logging):
```lua
---Handle settings change events
function MinifluxAPI:onMinifluxSettingsChanged(args)
    logger.dbg('[Miniflux:MinifluxAPI] Settings changed:', args.key, '=>', args.new_value)
    -- No action needed - api_client handles the actual changes
end
```

#### Step 5: Update Main Plugin Initialization

**File: `src/main.lua`**

Replace DI pattern with parent-child registration:

```lua
function Miniflux:init()
    logger.info('[Miniflux:Main] Initializing plugin')
    
    -- Initialize core components
    local download_dir = self:initializeDownloadDirectory()
    if not download_dir then
        logger.err('[Miniflux:Main] Failed to initialize download directory')
        return
    end
    self.download_dir = download_dir
    
    -- Create settings (still needs direct creation for bootstrapping)
    self.settings = MinifluxSettings:new()
    
    -- Create modules with parent reference (no DI!)
    self.api_client = APIClient:new({ plugin = self })
    self.miniflux_api = MinifluxAPI:new({ plugin = self })
    
    -- Register modules for event handling
    self:registerModule('api_client', self.api_client, true)
    self:registerModule('miniflux_api', self.miniflux_api, true)
    
    -- Continue with existing DI for other services (Phase 2 will migrate these)
    local CacheService = require('services/cache_service')
    self.cache_service = CacheService:new({
        miniflux_api = self.miniflux_api,
        settings = self.settings,
    })
    
    -- ... rest of initialization
    
    logger.info('[Miniflux:Main] Plugin initialization complete')
end
```

#### Step 6: Add Cleanup Method

**File: `src/main.lua`**

Update onCloseWidget to handle module cleanup:

```lua
function Miniflux:onCloseWidget()
    logger.info('[Miniflux:Main] Plugin closing - cleaning up')
    
    -- Terminate background jobs
    self:terminateBackgroundJobs()
    
    -- Cancel any scheduled zombie collection
    if self.subprocesses_collector then
        UIManager:unschedule(function()
            self:collectSubprocesses()
        end)
        self.subprocesses_collector = nil
    end
    
    -- Clear download cache
    local DownloadCache = require('utils/download_cache')
    DownloadCache.clear()
    
    -- Cleanup services
    if self.key_handler_service then
        self.key_handler_service:cleanup()
    end
    if self.readerlink_service then
        self.readerlink_service:cleanup()
    end
    
    -- Clear module references for garbage collection
    self.api_client = nil
    self.miniflux_api = nil
    self.cache_service = nil
    
    -- Revert wrapped methods
    if self.wrapped_onClose then
        self.wrapped_onClose:revert()
        self.wrapped_onClose = nil
    end
end
```

### Phase 2: Comprehensive Migration

#### Services Migration
After MVP validation, migrate remaining services:
- `EntryService`
- `CollectionService` 
- `QueueService`
- `KeyHandlerService`
- `ReaderLinkService`

#### Event Catalog
Define comprehensive event catalog:
- **Configuration Events**: Settings, API configuration
- **Data Events**: Entry downloads, sync operations
- **UI Events**: Navigation changes, browser state
- **System Events**: Network status, device suspend/resume

### Phase 3: Advanced Patterns

#### Custom Event Bus
Create plugin-specific event bus for complex scenarios:
```lua
local MinifluxEventBus = {}
function MinifluxEventBus:subscribe(event_name, handler)
function MinifluxEventBus:publish(event_name, data)
```

#### State Management
Event-driven state management for plugin-wide state:
```lua
local MinifluxState = {}
function MinifluxState:onMinifluxNavigationChanged(args)
function MinifluxState:onMinifluxEntryDownloaded(args)
```

## Benefits

### 1. Memory Management
- **No Singletons**: Proper garbage collection when plugin closes
- **Clear Ownership**: Plugin owns all modules, clear lifecycle management
- **Automatic Cleanup**: When parent is destroyed, all children become eligible for GC
- **Resource Management**: Explicit cleanup in `onCloseWidget()` prevents resource leaks

### 2. KOReader Alignment
- **Native Patterns**: Uses KOReader's proven parent-child module system
- **Consistent Architecture**: Follows same patterns as ReaderUI and core modules
- **Better Integration**: Leverages existing event infrastructure
- **Defensive Programming**: Follows KOReader's nil-checking patterns

### 3. Maintainability
- **Loose Coupling**: Events for distant module communication
- **Tight Coupling**: Direct access for related modules (like ReaderUI)
- **Clear Dependencies**: Parent-child relationships are explicit
- **Easy Extension**: New modules can be added without modifying existing code

### 4. Testability
- **Isolated Testing**: Modules can be tested independently
- **Mock Parent**: Easy to mock plugin parent for testing
- **Predictable Behavior**: Event flow and parent access are easier to trace

## Challenges & Solutions

### 1. Type Annotations
**Challenge**: How to properly annotate parent-child relationships?

**Solution**: 
- Add explicit parent type annotations: `---@field plugin Miniflux Parent plugin instance`
- Use defensive programming with nil checks: `if self.plugin and self.plugin.settings then`
- Document parent-child contracts clearly in module headers

### 2. Performance
**Challenge**: Parent access might have slight overhead vs direct references

**Solution**:
- Profile parent access vs DI performance (expected to be negligible)
- Use direct property access for frequently accessed modules
- Cache parent references in local variables for tight loops

### 3. Debugging
**Challenge**: Parent-child relationships can be harder to trace than direct DI

**Solution**:
- Add comprehensive logging for module access patterns
- Use consistent naming conventions for parent references
- Document module dependency graphs
- Use KOReader's existing debugging tools

### 4. Circular Dependencies
**Challenge**: Modules might need to access each other through parent

**Solution**:
- Use events for cross-module communication instead of direct access
- Implement lazy initialization for complex dependencies
- Follow KOReader's patterns for handling circular references

## Success Metrics

### MVP Success Criteria
1. ✅ API client successfully responds to settings changes via events
2. ✅ No performance degradation compared to DI approach  
3. ✅ Proper garbage collection (no memory leaks from singletons)
4. ✅ Cleaner, more KOReader-native code patterns
5. ✅ Foundation for broader event-driven migration

### Long-term Success Criteria
1. 50% reduction in dependency complexity
2. Improved module isolation and testability
3. Easier plugin extension and customization
4. Better alignment with KOReader core patterns

## Implementation Timeline

### Week 1: MVP Development
- [ ] Event infrastructure in main.lua
- [ ] Settings event broadcasting
- [ ] API client event handling
- [ ] Basic integration testing

### Week 2: Testing & Refinement
- [ ] Performance testing vs DI approach
- [ ] Edge case handling
- [ ] Documentation completion
- [ ] Code review and feedback

### Week 3: Validation & Decision
- [ ] Real-world usage testing
- [ ] Architectural decision on full migration
- [ ] Plan next phases based on results

## Related Documentation

- [KOReader Event System](https://github.com/koreader/koreader/blob/master/frontend/ui/event.lua)
- [ReaderUI Module Registration](https://github.com/koreader/koreader/blob/master/frontend/apps/reader/readerui.lua)
- [UIManager Event Broadcasting](https://github.com/koreader/koreader/blob/master/frontend/ui/uimanager.lua)

## Conclusion

The migration to event-driven architecture with parent-child module access represents a significant improvement in code maintainability and KOReader integration. By starting with a focused MVP, we can validate the approach while minimizing risk to the existing codebase.

### Key Insights

1. **No Singletons Needed**: KOReader's parent-child pattern provides clean module access without memory leaks
2. **Event-Driven Configuration**: Settings changes can be reactively propagated through events
3. **Natural Cleanup**: Parent-child relationships ensure proper garbage collection
4. **KOReader Native**: Follows the same patterns as ReaderUI and core modules

### The Best of Both Worlds

This approach combines:
- **Tight coupling** for related modules (direct parent access)
- **Loose coupling** for distant modules (event system)
- **Automatic cleanup** (no singletons)
- **KOReader alignment** (proven patterns)

The result is a more maintainable, memory-efficient, and KOReader-native architecture that eliminates the complexity of custom dependency injection while providing better performance and cleaner code.