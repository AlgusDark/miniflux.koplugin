#!/usr/bin/env lua

-- Script to remove comments from Lua files in the dist directory
-- Preserves functionality while reducing file size

local function remove_comments(content)
    -- Remove block comments (including LuaDoc style)
    content = content:gsub("%-%-%[%[.-%]%]", "")
    
    -- Remove type annotations (---@)
    content = content:gsub("\n%s*%-%-%-@[^\n]*", "")
    
    -- Remove single-line comments (but preserve shebang)
    content = content:gsub("\n%s*%-%-[^%-][^\n]*", "")
    content = content:gsub("\n%s*%-%-%s*$", "")
    
    -- Remove inline comments (careful not to break strings)
    -- This is trickier, so we'll be conservative and only remove obvious cases
    content = content:gsub("(%s)%-%-[^\n\"']*\n", "%1\n")
    
    -- Remove multiple consecutive blank lines
    content = content:gsub("\n\n+", "\n\n")
    
    -- Remove trailing whitespace
    content = content:gsub("%s+\n", "\n")
    
    -- Remove leading/trailing blank lines
    content = content:gsub("^%s*\n", "")
    content = content:gsub("\n%s*$", "")
    
    -- Ensure file ends with newline
    if content:len() > 0 and content:sub(-1) ~= "\n" then
        content = content .. "\n"
    end
    
    return content
end

local function process_file(filepath)
    local file = io.open(filepath, "r")
    if not file then
        print("Error: Cannot open file " .. filepath)
        return false
    end
    
    local content = file:read("*all")
    file:close()
    
    local cleaned = remove_comments(content)
    
    file = io.open(filepath, "w")
    if not file then
        print("Error: Cannot write to file " .. filepath)
        return false
    end
    
    file:write(cleaned)
    file:close()
    
    return true
end

local function find_lua_files(dir)
    local files = {}
    local handle = io.popen('find "' .. dir .. '" -name "*.lua" -type f')
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

-- Main execution
local dist_dir = arg[1] or "dist/miniflux.koplugin"

if not io.open(dist_dir, "r") then
    print("Error: Directory " .. dist_dir .. " does not exist")
    print("Usage: lua remove-comments.lua [dist_directory]")
    os.exit(1)
end

print("Removing comments from Lua files in " .. dist_dir)

local files = find_lua_files(dist_dir)
local processed = 0
local errors = 0

for _, file in ipairs(files) do
    print("Processing: " .. file)
    if process_file(file) then
        processed = processed + 1
    else
        errors = errors + 1
    end
end

print("\nSummary:")
print("  Files processed: " .. processed)
print("  Errors: " .. errors)
print("  Total files: " .. #files)