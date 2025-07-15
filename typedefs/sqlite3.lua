---@meta
---@module "lua-ljsqlite3/init"

---@class SQLite3
local SQLite3 = {}

---Open a database connection
---@param path string Database file path
---@param mode? string Open mode (optional)
---@return SQLiteConnection connection Database connection object
function SQLite3.open(path, mode) end

---Create a blob object for binary data
---@param data string Binary data
---@return any blob Blob object
function SQLite3.blob(data) end

---Trim whitespace from strings
---@param str string String to trim
---@return string trimmed Trimmed string
function SQLite3.trim(str) end

---@class SQLiteConnection
local SQLiteConnection = {}

---Close the database connection
function SQLiteConnection:close() end

---Set busy timeout in milliseconds
---@param timeout_ms number Timeout in milliseconds
function SQLiteConnection:set_busy_timeout(timeout_ms) end

---Execute SQL commands (no result returned)
---@param sql string SQL commands to execute
---@return number code SQLite result code
function SQLiteConnection:exec(sql) end

---Execute SQL and return results as table
---@param sql string SQL query to execute
---@return table results Query results as nested table
function SQLiteConnection:execsql(sql) end

---Execute query expecting single row/value result
---@param sql string SQL query to execute
---@return any value Single value or row result
function SQLiteConnection:rowexec(sql) end

---Prepare a SQL statement for execution
---@param sql string SQL statement with optional placeholders
---@return SQLiteStatement statement Prepared statement object
function SQLiteConnection:prepare(sql) end

---@class SQLiteStatement
local SQLiteStatement = {}

---Reset statement for reuse
---@return SQLiteStatement self Returns self for chaining
function SQLiteStatement:reset() end

---Close and free statement
function SQLiteStatement:close() end

---Execute statement step
---@return number code Result code (101=SQLITE_ROW, 100=SQLITE_DONE)
function SQLiteStatement:step() end

---Bind parameter by position (1-indexed)
---@param index number Parameter position (1-indexed)
---@param value any Value to bind
---@return SQLiteStatement self Returns self for chaining
function SQLiteStatement:bind(index, value) end

---Bind parameters by key-value table
---Named parameters in SQL should use :name syntax
---Example: INSERT INTO table (col1, col2) VALUES (:key1, :key2)
---Then use: stmt:bindkv({key1 = "value1", key2 = "value2"})
---@param params table<string, any> Key-value pairs to bind
---@param prefix? string Parameter prefix (default ":")
---@return SQLiteStatement self Returns self for chaining
function SQLiteStatement:bindkv(params, prefix) end

---Clear all parameter bindings
---@return SQLiteStatement self Returns self for chaining
function SQLiteStatement:clearbind() end

---Fetch all result rows as table
---@return table results All rows as nested table
function SQLiteStatement:resultset() end

---Iterator for result rows (use with caution due to known issues)
---@return function iterator Row iterator function
function SQLiteStatement:rows() end

---Get column value by index (0-indexed)
---@param index number Column index (0-indexed)
---@return any value Column value
function SQLiteStatement:get_value(index) end

---SQLite result codes
---@class SQLiteResultCode
---@field SQLITE_OK number 0 - Successful result
---@field SQLITE_DONE number 100 - sqlite3_step() has finished executing
---@field SQLITE_ROW number 101 - sqlite3_step() has another row ready

return SQLite3
