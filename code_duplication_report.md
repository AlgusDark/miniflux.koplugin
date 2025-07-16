# Code Duplication Report for miniflux.koplugin

This report identifies patterns of code duplication and repeated code blocks that could be extracted into shared utilities or base classes.

## 1. InfoMessage Dialog Creation Pattern

**Duplication Found**: InfoMessage creation with timeout is repeated across multiple files with similar patterns.

### Current Pattern (repeated 20+ times):
```lua
UIManager:show(InfoMessage:new({
    text = _('Some message'),
    timeout = 3,
}))
```

### Files Affected:
- `menu/settings/check_updates.lua` (11 occurrences)
- `menu/settings/update_settings.lua` (9 occurrences)
- `utils/notification.lua` (4 occurrences - already abstracted)

### Recommendation:
The `utils/notification.lua` module already provides a clean abstraction for this pattern. Other files should be refactored to use this utility instead of direct InfoMessage creation.

## 2. Directory Creation Pattern

**Duplication Found**: Directory existence check and creation logic is repeated.

### Current Pattern:
```lua
if not lfs.attributes(dir_path, 'mode') then
    local success = lfs.mkdir(dir_path)
    if not success then
        -- error handling
    end
end
```

### Files Affected:
- `main.lua`
- `menu/settings/copy_css.lua`
- `services/update_service.lua`
- `utils/files.lua` (already abstracted as `Files.createDirectory`)

### Recommendation:
The `utils/files.lua` already provides `Files.createDirectory()`. Other occurrences should use this utility method.

## 3. File Existence Check Pattern

**Duplication Found**: File/directory existence checks using `lfs.attributes` are repeated extensively.

### Current Pattern:
```lua
if lfs.attributes(file_path, 'mode') == 'file' then
    -- file exists
end
```

### Files Affected:
- `entities/entry_entity.lua` (5 occurrences)
- `services/entry_service.lua` (2 occurrences)
- `services/navigation_service.lua` (3 occurrences)
- `services/update_service.lua` (1 occurrence)
- `menu/settings/copy_css.lua` (2 occurrences)
- `menu/settings/check_updates.lua` (2 occurrences)
- `browser/miniflux_browser.lua` (2 occurrences)
- `utils/collections_queue.lua` (3 occurrences)
- `utils/images.lua` (1 occurrence)
- `utils/files.lua` (1 occurrence)
- `main.lua` (1 occurrence)

### Recommendation:
Create utility functions in `utils/files.lua`:
```lua
function Files.fileExists(path)
    return lfs.attributes(path, 'mode') == 'file'
end

function Files.directoryExists(path)
    return lfs.attributes(path, 'mode') == 'directory'
end
```

## 4. Error Handling Pattern in cache_service.lua

**Duplication Found**: Identical error handling pattern repeated 9 times.

### Current Pattern:
```lua
if err then
    return nil, err
end
```

### Files Affected:
- `services/cache_service.lua` (9 occurrences with identical pattern)
- `services/update_service.lua` (1 occurrence)

### Recommendation:
While this is a standard Lua error propagation pattern, the repetition in cache_service.lua suggests the file could benefit from internal helper methods to reduce duplication.

## 5. Validation Pattern

**Duplication Found**: Similar validation patterns for checking nil/type.

### Current Pattern:
```lua
if not value or type(value) ~= 'expected_type' then
    -- handle error
end
```

### Files Affected:
- `entities/entry_entity.lua`
- `services/collection_service.lua`
- `utils/cache_store.lua`

### Recommendation:
Create a validation utility module with common validation functions:
```lua
-- utils/validation.lua
function Validation.isValidTable(value)
    return value ~= nil and type(value) == 'table'
end

function Validation.isValidNumber(value, min)
    return value ~= nil and type(value) == 'number' and (not min or value >= min)
end
```

## 6. ConfirmBox Dialog Pattern

**Duplication Found**: ConfirmBox creation follows similar patterns.

### Current Pattern:
```lua
UIManager:show(ConfirmBox:new({
    text = _('Message'),
    ok_text = _('OK'),
    ok_callback = function()
        -- action
    end,
}))
```

### Files Affected:
- `services/entry_service.lua`
- `menu/settings/copy_css.lua`
- `menu/settings/check_updates.lua` (3 occurrences)
- `browser/miniflux_browser.lua`

### Recommendation:
Create a dialog utility that wraps common dialog patterns with sensible defaults.

## 7. Logger Pattern

**Duplication Found**: Extensive logger calls with similar formatting patterns, especially in `services/update_service.lua`.

### Current Pattern:
```lua
logger.info('UpdateService: ' .. message)
logger.warn('UpdateService: ' .. error_message)
```

### Files Affected:
- `services/update_service.lua` (30+ logger calls with 'UpdateService:' prefix)

### Recommendation:
Create a module-specific logger wrapper that automatically adds the prefix:
```lua
local function createLogger(prefix)
    return {
        info = function(msg) logger.info(prefix .. ': ' .. msg) end,
        warn = function(msg) logger.warn(prefix .. ': ' .. msg) end,
        -- etc.
    }
end
```

## 8. Cache Key Generation

**Duplication Found**: Cache keys are generated in different ways but follow similar patterns.

### Current Pattern in cache_service.lua:
```lua
local cache_key = 'feeds'
local cache_key = 'categories'
local cache_key = self.miniflux_api:buildEntriesUrl(options) .. '_count'
```

### Recommendation:
Standardize cache key generation with a helper method that ensures consistent formatting.

## 9. API Call Pattern with Error Handling

**Duplication Found**: API calls with similar error handling patterns.

### Current Pattern:
```lua
local result, err = self.miniflux_api:getSomething(config)
if err then
    return nil, err
end
-- process result
```

### Files Affected:
- `services/cache_service.lua` (multiple API calls)
- `services/navigation_service.lua`
- `menu/settings/test_connection.lua`

### Recommendation:
The pattern is standard for Lua error handling, but the cache_service could benefit from a wrapper method for API calls with caching.

## Summary

The codebase shows good organization with some utilities already extracted (like `notification.lua` and `files.lua`), but there are opportunities to further reduce duplication by:

1. **Using existing utilities more consistently** - Many files recreate patterns that already have utility functions
2. **Creating new utilities** for file system operations, validation, and dialog creation
3. **Standardizing error handling** and logging patterns within modules
4. **Extracting common UI patterns** into reusable components

The most impactful improvements would be:
- Migrating all InfoMessage usage to the Notification utility
- Creating file system utilities and using them consistently
- Creating a validation utility module
- Adding logger wrappers for modules with extensive logging