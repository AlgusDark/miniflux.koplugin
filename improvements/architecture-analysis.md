# Architecture Analysis & Domain-Driven Design Discussion

## Overview

This document captures the comprehensive architectural analysis and Domain-Driven Design (DDD) discussions for the KOReader Miniflux plugin. It serves as a reference for future development and architectural decisions.

## Initial Problem: Over-Engineering vs User Value

### The Provider Architecture Idea

Initially, we considered implementing a **provider-based architecture** to support multiple RSS/content services:

```
providers/
├── miniflux/
├── readeck/    # Future
├── instapaper/ # Future
```

**Theoretical Benefits:**
- Code reusability across different content providers
- Clean separation of domain logic
- Future extensibility for other services

### Reality Check: The Honest Assessment

**Critical Finding:** The codebase is **heavily miniflux-specific** at all levels:

1. **Entry Point (`main.lua`):**
   - Hardcoded miniflux imports and initialization
   - Fixed directory structure (`/miniflux/`)
   - Miniflux-specific plugin naming and behavior

2. **API Layer:**
   - All endpoints are miniflux-specific (`/entries`, `/feeds`, `/categories`)
   - Miniflux data structures (`MinifluxEntry`, `MinifluxFeed`)

3. **Business Logic:**
   - RSS-specific navigation (feed/category context)
   - Miniflux metadata structures
   - DocSettings with `miniflux_` prefixes

4. **UI Layer:**
   - RSS-specific terminology ("Feeds", "Categories", "Unread Entries")
   - Miniflux-specific workflows

**Conclusion:** Creating provider abstraction would require **80%+ code refactoring** for theoretical benefits with no concrete plans for other providers.

### Decision: Focus on User Value

Instead of architectural over-engineering, focus on **actual user needs**:

✅ **Immediate Value:** UX improvements users actually want  
❌ **Theoretical Value:** Architecture for problems we don't have

## Current Architecture Issues

### Misplaced Domain Logic

Two major files are incorrectly located in `utils/`:

#### 1. `utils/entry_utils.lua` - NOT a Utility!
**What it actually is:** Entry domain entity with business logic
- Entry validation rules
- File operations specific to entries  
- Metadata management with DocSettings
- UI coordination dialogs
- Status management

**Should be:** `entities/entry_entity.lua`

#### 2. `utils/navigation.lua` - NOT a Utility!
**What it actually is:** Navigation domain service
- Complex RSS navigation algorithms
- API orchestration with fallback logic
- Business rules (feed/category/global context)
- Time-based navigation with miniflux timestamps
- Offline mode handling

**Should be:** `services/navigation_service.lua`

### Utils That Need Cleanup

#### Generic (Keep in utils/)
- ✅ `error.lua` - Pure error objects
- ✅ `notification.lua` - Generic KOReader notifications  
- ✅ `time_utils.lua` - Pure ISO-8601 conversion
- ✅ `debugger.lua` - Generic logging (exception: hardcoded path OK for temporary tool)

#### Mixed (Need refactoring)
- 🟡 `files.lua` - Generic file ops + miniflux metadata loading (split needed)
- 🟡 `html_utils.lua` - Generic HTML processing + entry-specific assumptions
- 🟡 `images.lua` - Generic image processing + minor RSS assumptions

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

## Recommended Refactoring Plan

### Phase 1: Move Domain Logic to Proper Locations

```bash
# Create proper structure
mkdir -p entities services

# Move domain logic
mv utils/entry_utils.lua entities/entry_entity.lua
mv utils/navigation.lua services/navigation_service.lua
```

### Phase 2: Extract and Clean Mixed Utilities

```bash
# Extract metadata loading from files.lua to entry entity
# Make html_utils.lua and images.lua purely generic
# Keep only generic file operations in files.lua
```

### Phase 3: Update All Import References

Update all `require("utils/entry_utils")` → `require("entities/entry_entity")`  
Update all `require("utils/navigation")` → `require("services/navigation_service")`

### Final Clean Structure

```
entities/
└── entry_entity.lua          # Domain entity (business logic)

services/
├── entry_service.lua          # Application service (workflow orchestration)
├── entry_downloader.lua       # Application service (download workflows)  
└── navigation_service.lua     # Domain service (navigation business rules)

utils/                         # Pure generic utilities
├── error.lua, notification.lua, time_utils.lua  # ✅ Already pure
├── files.lua                  # Generic file operations only
├── html_utils.lua             # Generic HTML processing  
└── images.lua                 # Generic image processing
```

## Key Architectural Principles

1. **Don't Over-Engineer:** Solve problems you actually have
2. **User Value First:** Focus on features users want
3. **Honest Assessment:** Acknowledge when abstraction costs exceed benefits
4. **Domain-Driven Design:** Put domain logic in appropriate layers
5. **Clean Utils:** Keep utilities truly generic and reusable

## Future Considerations

**If/when** we add support for other content providers:

1. **Assess at that time** whether provider abstraction adds value
2. **Start simple** with clear domain boundaries  
3. **Avoid premature optimization** for theoretical requirements
4. **Focus on actual reuse patterns** rather than imagined ones

The current single-provider focus is **architecturally sound** and **user-focused**. 