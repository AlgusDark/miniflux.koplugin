# SQLite Best Practices for KOReader Plugins

This document captures important lessons learned about using lua-ljsqlite3 in KOReader plugins.

## Key Learnings

### 1. Use `rowexec()` for Simple Single-Value Queries

**✅ DO THIS:**
```lua
-- For queries that return a single value
local count = db_conn:rowexec('SELECT COUNT(*) FROM entries')
local value = db_conn:rowexec('SELECT value FROM settings WHERE key = "last_sync"')
```

**❌ DON'T DO THIS:**
```lua
-- Prepared statements with rows() iterator can fail silently
local stmt = db_conn:prepare('SELECT COUNT(*) as count FROM entries')
for row in stmt:rows() do
    count = row.count  -- This might return nil/0 even with data!
end
```

### 2. Use `db:exec()` for INSERT/UPDATE/DELETE Operations

**✅ DO THIS:**
```lua
-- Direct SQL execution with string formatting
local sql = string.format([[
    INSERT INTO entries (id, title, url) 
    VALUES (%d, %s, %s)
]], 
    entry.id,
    escape_sql(entry.title),
    escape_sql(entry.url)
)
db_conn:exec(sql)
```

**❌ DON'T DO THIS:**
```lua
-- Prepared statements with bind() can fail with "NOT NULL constraint" errors
local stmt = db_conn:prepare('INSERT INTO entries (id, title, url) VALUES (?, ?, ?)')
stmt:bind(1, entry.id)
stmt:bind(2, entry.title)  -- May be treated as nil!
stmt:bind(3, entry.url)    -- May be treated as nil!
stmt:step()
```

### 3. Always Escape SQL String Values

```lua
local function escape_sql(str)
    if str == nil then
        return "NULL"
    else
        -- Convert to string and escape single quotes
        return "'" .. tostring(str):gsub("'", "''") .. "'"
    end
end
```

### 4. Avoid `stmt:rows()` Iterator - Use `stmt:step()` Instead

**❌ DON'T DO THIS:**
```lua
-- The rows() iterator can fail with "column index out of range"
for row in stmt:rows() do
    entry.title = row.title  -- May fail!
    entry.url = row.url
end
```

**✅ DO THIS:**
```lua
-- Use step() with get_value() by column index
while stmt:step() == 101 do -- SQLITE_ROW
    local entry = {
        id = stmt:get_value(0),     -- column 0
        title = stmt:get_value(1),   -- column 1
        url = stmt:get_value(2),     -- column 2
    }
    table.insert(entries, entry)
end
```

### 5. Consider `bindkv()` for Named Parameters

If you do use prepared statements, consider `bindkv()` over `bind()` for better clarity:

**✅ RECOMMENDED - Use bindkv() with named parameters:**
```lua
-- More readable and less error-prone
local stmt = db:prepare('INSERT INTO entries (id, title, url) VALUES (:id, :title, :url)')
stmt:bindkv({
    id = entry.id,
    title = entry.title,
    url = entry.url
})
stmt:step()
```

**❌ AVOID - Positional bind() calls:**
```lua
-- Harder to maintain and prone to position errors
local stmt = db:prepare('INSERT INTO entries (id, title, url) VALUES (?, ?, ?)')
stmt:bind(1, entry.id)
stmt:bind(2, entry.title)  -- May still be treated as nil!
stmt:bind(3, entry.url)    -- May still be treated as nil!
stmt:step()
```

**Note:** Even with `bindkv()`, the underlying string binding issues in lua-ljsqlite3 may persist. If you encounter "NOT NULL constraint" errors, fall back to `db:exec()` with proper escaping.

### 6. Use Prepared Statements Only When Necessary

Prepared statements work well for:
- Repeated queries in loops where performance matters
- Simple parameterized queries without complex data types
- Queries where you're certain all values are non-nil

But prefer `db:exec()` or `rowexec()` for:
- INSERT operations with nullable columns or string values
- Queries returning single values
- One-off queries where prepared statement overhead isn't worth it
- Complex queries with mixed data types

### 7. Database File Location

```lua
-- Always use DataStorage for database paths
local DataStorage = require('datastorage')
local db_path = DataStorage:getSettingsDir() .. '/your_plugin.db'
-- This resolves to: ~/.config/koreader/settings/your_plugin.db
```

### 8. Database Initialization Pattern

```lua
-- Set pragmas immediately after opening
local SQ3 = require('lua-ljsqlite3/init')
local db = SQ3.open(db_path)

-- Set journal mode based on device
if Device:canUseWAL() then
    db:exec('PRAGMA journal_mode=WAL;')
else
    db:exec('PRAGMA journal_mode=TRUNCATE;')
end

-- Create tables using multiline SQL
db:exec([[
    CREATE TABLE IF NOT EXISTS entries (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_title ON entries(title);
]])
```

## Why These Issues Occur

1. **lua-ljsqlite3 Binding Quirks**: The bind() method in lua-ljsqlite3 can treat Lua strings as nil in certain cases, causing "NOT NULL constraint failed" errors even when values are clearly present.

2. **Iterator Behavior**: The `stmt:rows()` iterator might not work as expected for aggregate functions like COUNT(*), returning nil or 0 even when data exists.

3. **No bind_values Method**: Unlike some SQLite bindings, lua-ljsqlite3 doesn't have a `bind_values()` method, requiring individual bind() calls.

## Real-World Example

From our miniflux.koplugin experience:

```lua
-- This failed with "NOT NULL constraint failed: entries.url"
local stmt = db:prepare('INSERT INTO entries (url) VALUES (?)')
stmt:bind(1, "https://example.com")  -- String treated as nil!
stmt:step()

-- This worked perfectly
local sql = string.format(
    'INSERT INTO entries (url) VALUES (%s)',
    escape_sql("https://example.com")
)
db:exec(sql)
```

## Available SQLite API Functions in KOReader

Based on lua-ljsqlite3, these are the SQLite functions available in KOReader:

### Database Connection Methods
- `SQ3.open(path, mode)` - Open a database connection
- `db:close()` - Close the database connection
- `db:set_busy_timeout(ms)` - Set busy timeout in milliseconds
- `db:prepare(sql)` - Prepare a SQL statement for execution
- `db:exec(sql)` - Execute SQL commands (no result returned)
- `db:execsql(sql)` - Execute SQL and return results as table
- `db:rowexec(sql)` - Execute query expecting single row/value result

### Prepared Statement Methods
- `stmt:reset()` - Reset statement for reuse
- `stmt:close()` - Close and free statement
- `stmt:step()` - Execute statement step (returns SQLITE_ROW=101 or SQLITE_DONE=100)
- `stmt:bind(index, value)` - Bind parameter by position (1-indexed)
- `stmt:bindkv(table)` - Bind parameters by key-value table
- `stmt:clearbind()` - Clear all parameter bindings
- `stmt:resultset()` - Fetch all result rows as table
- `stmt:rows()` - Iterator for result rows (use with caution)
- `stmt:get_value(index)` - Get column value by index (0-indexed)

### Utility Functions
- `SQ3.blob(data)` - Create a blob object for binary data
- `SQ3.trim(str)` - Trim whitespace from strings

### Functions NOT Available
Notable functions that are NOT exposed in KOReader's SQLite binding:
- `bind_values()` - Must use individual `bind()` calls
- `get_names()` - Cannot get column names directly
- `get_types()` - Cannot get column types
- Transaction control must be done via `exec()` with BEGIN/COMMIT/ROLLBACK

## Should You Create a Wrapper?

For most KOReader plugins, creating a wrapper is **overkill**. The best practices above handle the quirks adequately. However, consider a minimal utility module if you:

1. Have many database operations across multiple files
2. Need consistent error handling and logging
3. Want to abstract the escape_sql pattern

A minimal utility approach:

```lua
-- utils/sqlite_helper.lua
local SQ3 = require('lua-ljsqlite3/init')

local SqliteHelper = {}

function SqliteHelper.escape_sql(str)
    if str == nil then
        return "NULL"
    else
        return "'" .. tostring(str):gsub("'", "''") .. "'"
    end
end

function SqliteHelper.exec_formatted(db, sql, ...)
    local args = {...}
    local escaped_args = {}
    for i, arg in ipairs(args) do
        if type(arg) == "number" then
            escaped_args[i] = tostring(arg)
        else
            escaped_args[i] = SqliteHelper.escape_sql(arg)
        end
    end
    return db:exec(string.format(sql, unpack(escaped_args)))
end

return SqliteHelper
```

But for simple plugins, inline SQL formatting with proper escaping is perfectly fine and more transparent.

## References

- KOReader's newsdownloader.koplugin uses similar patterns
- The offline_first.md documentation shows rowexec() usage
- Device:canUseWAL() pattern from coverbrowser plugin
- lua-ljsqlite3 source: https://github.com/koreader/koreader-base/blob/master/thirdparty/lua-ljsqlite3/init.lua