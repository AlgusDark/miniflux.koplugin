# Miniflux API Client

This API client provides a clean, developer-friendly interface for interacting with the Miniflux API.

## Basic Usage

```lua
local MinifluxAPI = require("api/api_client")

-- Initialize the API client
local api = MinifluxAPI:new({
    server_address = "https://miniflux.example.com",
    api_token = "your_api_token_here"
})

-- Test connection
local success, message = api:testConnection()
if success then
    print(message)
else
    print("Error: " .. message)
end
```

## HTTP Methods

The API client provides clean HTTP methods that accept a config table:

### GET Requests

```lua
-- Simple GET request
local success, data = api:get("/feeds")

-- GET with query parameters
local success, data = api:get("/entries", {
    query = {
        limit = 10,
        status = {"unread"},
        order = "published_at",
        direction = "desc"
    }
})
```

### POST Requests

```lua
-- POST with body
local success, data = api:post("/categories", {
    body = {
        title = "New Category"
    }
})

-- POST with both body and query parameters
local success, data = api:post("/entries", {
    body = {
        entry_ids = {1, 2, 3},
        status = "read"
    },
    query = {
        some_param = "value"
    }
})
```

### PUT Requests

```lua
-- PUT with body
local success, data = api:put("/entries", {
    body = {
        entry_ids = {123, 456},
        status = "read"
    }
})
```

### DELETE Requests

```lua
-- Simple DELETE
local success, data = api:delete("/categories/123")

-- DELETE with query parameters
local success, data = api:delete("/entries/456", {
    query = {
        force = "true"
    }
})
```

## Specialized Modules

### Entries

```lua
-- Get entries with filtering
local success, data = api.entries:getEntries({
    limit = 20,
    status = {"unread"},
    category_id = 5,
    order = "published_at",
    direction = "desc"
})

-- Mark entries as read
local success, result = api.entries:markAsRead(123)
local success, result = api.entries:markMultipleAsRead({123, 456, 789})

-- Navigation
local success, prev = api.entries:getPrevious(123, {status = {"unread"}})
local success, next = api.entries:getNext(123, {status = {"unread"}})
```

### Categories

```lua
-- Get categories with counts
local success, categories = api.categories:getAll(true)

-- Get category entries
local success, entries = api.categories:getEntries(5, {
    limit = 10,
    status = {"unread"}
})

-- Create/update/delete categories
local success, category = api.categories:create("New Category")
local success, category = api.categories:update(5, "Updated Title")
local success, result = api.categories:delete(5)
```

### Feeds

```lua
-- Get feeds and counters
local success, feeds = api.feeds:getFeeds()
local success, counters = api.feeds:getCounters()

-- Get feed entries
local success, entries = api.feeds:getEntries(10, {
    limit = 20,
    status = {"unread"}
})

-- Feed management
local success, result = api.feeds:refresh(10)
local success, result = api.feeds:markAsRead(10)
```

## Benefits of the Refactored API

1. **Cleaner Interface**: No more `Utils.getEntriesWithOptions(self.api, base_endpoint, options)` - just `api:get(endpoint, {query = params})`

2. **Consistent Pattern**: All HTTP methods follow the same `(endpoint, config)` pattern where config can contain `query` and `body`

3. **URL Encoding**: Query parameters are automatically URL-encoded using `util.urlEncode()`

4. **Type Safety**: Full TypeScript-style annotations for better IDE support

5. **Better Maintainability**: No separate Utils module to maintain - functionality is integrated where it belongs

6. **Flexible**: Supports both simple requests and complex queries with multiple parameters

7. **Array Handling**: Properly handles array parameters like `status = {"read", "unread"}` 