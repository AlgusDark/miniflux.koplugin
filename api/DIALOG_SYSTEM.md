# Enhanced API Client with Dialog System

The MinifluxAPI client now supports automatic dialog management for improved user experience. This eliminates the need for manual dialog handling throughout the codebase.

## Features

### 1. Validation-First Approach
- Configuration validation happens **before** showing loading dialogs
- Prevents showing loading dialogs for operations that will fail immediately
- Provides better user experience by showing error dialogs instead of loading then error

### 2. Automatic Dialog Management
- **Loading dialogs**: Shown automatically during API requests
- **Success dialogs**: Shown after successful operations
- **Error dialogs**: Shown for failed operations
- **Timeout support**: Configurable timeouts for all dialog types

### 3. Backward Compatibility
- All existing API calls continue to work unchanged
- Dialogs are **opt-in** - only shown when explicitly configured
- No breaking changes to existing code

## Usage Examples

### Basic API Calls (No Dialogs)
```lua
-- Existing calls work unchanged
local success, result = api.entries:getEntries(options)
local success, result = api:get("/me") 
```

### Loading Dialog Only (Most Common Pattern)
```lua
-- Connection testing with validation and loading
local success, result = api:testConnection({
    dialogs = {
        loading = { text = _("Testing connection to Miniflux server...") }
    }
})

-- Show result manually (API provides good messages)
UIManager:show(InfoMessage:new({
    text = result,
    timeout = success and 3 or 5,
}))
```

### Complete Dialog Automation (High-Frequency Operations)
```lua
-- Entry status changes with full dialog automation
local success, result = api.entries:markAsRead(entry_id, {
    dialogs = {
        loading = { text = _("Marking entry as read...") },
        success = { text = _("Entry marked as read"), timeout = 2 },
        error = { text = _("Failed to mark entry as read"), timeout = 5 }
    }
})

-- No manual dialog management needed!
if success then
    -- Handle business logic side effects
    self:onEntryStatusChanged(entry_id, "read")
end
```

### Repository Layer (Enhanced with Optional Dialog Support)
```lua
-- Pure data access (existing pattern)
local entries, error_msg = entry_repository:getUnread()
if not entries then
    UIComponents.showErrorMessage(_("Failed to fetch entries: ") .. error_msg)
    return
end

-- Enhanced with optional dialog support (Phase 2 pattern)
local entries, error_msg = entry_repository:getUnread({
    dialogs = {
        loading = { text = _("Fetching unread entries...") },
        error = { text = _("Failed to fetch entries"), timeout = 5 }
    }
})
if not entries then
    -- Error dialog already shown by repository
    return
end
```

## Dialog Configuration

### Structure
```lua
{
    dialogs = {
        loading = { text = "Loading...", timeout = nil },
        success = { text = "Success!", timeout = 3 },
        error = { text = "Error occurred", timeout = 5 }
    }
}
```

### Options
- **text**: Dialog message text
- **timeout**: Dialog timeout in seconds (nil = persistent until closed)

### Default Timeouts
- Loading: No timeout (closes when request completes)
- Success: 3 seconds
- Error: 3 seconds

## Implementation Details

### Request Flow
1. **Validation**: Check server address and API token
2. **Error on Validation Failure**: Show error dialog if validation fails
3. **Loading Dialog**: Show loading dialog if validation passes
4. **HTTP Request**: Make the actual API call
5. **Close Loading**: Always close loading dialog after request
6. **Success/Error**: Show appropriate result dialog

### Error Handling
- Network errors automatically show error dialogs
- HTTP errors (400, 401, 403, 500) show specific error messages
- JSON parsing errors show appropriate error dialogs
- Custom error messages can override default messages

### API Methods
All HTTP methods support the new dialog system:
- `api:get(endpoint, config)`
- `api:post(endpoint, config)`
- `api:put(endpoint, config)`
- `api:delete(endpoint, config)`

Where `config` can include:
- `query`: Query parameters
- `body`: Request body (for POST/PUT)
- `dialogs`: Dialog configuration

## Benefits

1. **Consistent UX**: Standardized dialog patterns across the application
2. **Reduced Boilerplate**: No need for manual dialog management in every API call
3. **Better Error Handling**: Automatic error message display with fallbacks
4. **Validation-First**: Prevents showing loading dialogs for invalid requests
5. **Flexibility**: Opt-in system allows granular control over which dialogs to show

## Migration Status: Complete ✅

The Enhanced API Dialog System migration has been completed across three phases:

- **Phase 1**: High-impact user operations (connection testing, entry status changes)
- **Phase 2**: Navigation & browsing operations (browser init, list loading, navigation)  
- **Phase 3**: Cleanup and deprecation (UIComponents cleanup, final documentation)

**Result**: 100% adoption of the dialog system for all network operations with 70+ lines of manual dialog code eliminated.

## Migration Guide

### ✅ For New Features (Recommended Pattern)
Use the enhanced API dialog system for all network operations:

```lua
-- ✅ Complete dialog automation for high-frequency operations
local success, result = api.entries:markAsRead(entry_id, {
    dialogs = {
        loading = { text = _("Marking entry as read...") },
        success = { text = _("Entry marked as read"), timeout = 2 },
        error = { text = _("Failed to mark entry as read"), timeout = 5 }
    }
})

-- ✅ Loading-only for operations with custom result handling
local success, result = api:testConnection({
    dialogs = {
        loading = { text = _("Testing connection...") }
    }
})
-- Custom result handling
UIManager:show(InfoMessage:new({
    text = result,
    timeout = success and 3 or 5
}))
```

### ⚠️ For Legacy Code Maintenance
Existing patterns continue working but should be upgraded when touched:

```lua
-- ⚠️ Deprecated but functional (will work but generate warnings)
local loading = UIComponents.showLoadingMessage(_("Loading..."))  
local success, result = api.entries:getEntries(options)
UIComponents.closeLoadingMessage(loading)

-- ✅ Upgrade to API dialog system during maintenance
local success, result = api.entries:getEntries(options, {
    dialogs = {
        loading = { text = _("Loading...") }
    }
})
```

### ✅ For Non-API Operations (Still Valid)
Some UIComponents methods remain useful for non-network operations:

```lua
-- ✅ Validation messages (immediate feedback)
UIComponents.showWarningMessage(_("Invalid input"))

-- ✅ Complex progress tracking (multi-step operations)
local progress = UIComponents.createProgressDialog(_("Processing..."))
progress:update(_("Step 1 of 3"))

-- ✅ Settings confirmations (user actions)
UIComponents.showInfoMessage(_("Settings saved"))
``` 