# Screen Standardization Bug Fix

## Issue Description

After completing the Screen Standardization refactoring, two browser functions were broken:

1. **Categories Browser**: Could show categories list but clicking on category entries failed
2. **Unread Browser**: Only showed "no found entries" instead of actual unread entries
3. **Feeds Browser**: Working correctly (used as reference)

## Root Cause

During the refactoring to use `BaseScreen:performApiCall()`, the `skip_validation = true` parameter was not consistently applied to API calls that need to handle empty results gracefully.

The `ErrorUtils.handleApiCall()` method performs data validation by default, but some API calls (like fetching entries) can legitimately return empty results that should not be treated as validation errors.

## Fix Applied

Added `skip_validation = true` to API calls that handle entries (which can be empty):

### 1. Categories Screen Fix
```lua
-- File: browser/screens/categories_screen.lua
-- Method: showCategoryEntries()

local result = self:performApiCall({
    operation_name = "fetch category entries",
    api_call_func = function()
        return self.browser.api:getCategoryEntries(category_id, options)
    end,
    loading_message = _("Fetching entries for category..."),
    data_name = "category entries",
    skip_validation = true  -- Added this line
})
```

### 2. Main Screen Fix  
```lua
-- File: browser/screens/main_screen.lua
-- Method: showUnreadEntries()

local result = self:performApiCall({
    operation_name = "fetch entries",
    api_call_func = function()
        return self.browser.api:getEntries(options)
    end,
    loading_message = _("Fetching entries..."),
    data_name = "entries",
    skip_validation = true  -- Added this line
})
```

## Why This Works

- **Feeds Screen**: Already had `skip_validation = true` for entry-related API calls, which is why it worked
- **Categories Screen**: The categories list API call (which works) doesn't need `skip_validation`, but the category entries call does
- **Main Screen**: The unread entries call needed `skip_validation` to handle cases where there are no unread entries

## Validation Strategy

The pattern is:
- **List APIs** (getFeeds, getCategories): Use normal validation (can fail if no data)
- **Entry APIs** (getEntries, getFeedEntries, getCategoryEntries): Use `skip_validation = true` (empty results are valid)
- **Counter APIs** (getFeedCounters): Use `skip_validation = true` (might not be available on older servers)

## Result

All three browser functions now work correctly:
- ✅ Categories Browser: Shows categories and category entries  
- ✅ Unread Browser: Shows unread entries properly
- ✅ Feeds Browser: Continues to work as before 