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

### 5. Use Prepared Statements Only When Necessary

Prepared statements work well for:
- Simple parameterized queries without complex data types
- Queries where you're certain all values are non-nil

But prefer `db:exec()` or `rowexec()` for:
- INSERT operations with nullable columns
- Queries returning single values
- Complex queries with mixed data types

### 5. Database File Location

```lua
-- Always use DataStorage for database paths
local DataStorage = require('datastorage')
local db_path = DataStorage:getSettingsDir() .. '/your_plugin.db'
-- This resolves to: ~/.config/koreader/settings/your_plugin.db
```

### 6. Database Initialization Pattern

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

## References

- KOReader's newsdownloader.koplugin uses similar patterns
- The offline_first.md documentation shows rowexec() usage
- Device:canUseWAL() pattern from coverbrowser plugin