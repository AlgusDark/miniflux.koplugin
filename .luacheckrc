-- Luacheck configuration for Miniflux KOReader plugin
-- https://luacheck.readthedocs.io/en/stable/config.html

-- Standard library globals (Lua 5.1 for KOReader)
std = "lua51"

-- Maximum line length
max_line_length = 100

-- Global variables allowed (KOReader framework)
globals = {
    -- KOReader UI framework
    "UIManager",
    "BookList", 
    "WidgetContainer",
    "InfoMessage",
    "ButtonDialog",
    "ConfirmBox",
    "MultiInputDialog",
    "ButtonDialogTitle",
    "TitleBar",
    "ImageViewer",
    "IconButton",
    "FrameContainer",
    "VerticalGroup",
    "TextWidget",
    "IconWidget",
    "EventListener",
    
    -- KOReader system
    "DataStorage",
    "LuaSettings",
    "CacheSQLite",
    "DocSettings",
    "Dispatcher",
    "FFIUtil",
    
    -- KOReader utilities
    "util",
    "lfs",
    "logger",
    "dbg",
    
    -- Localization
    "_", -- gettext function
    
    -- Third-party libraries (from koreader-base thirdparty)
    "htmlparser",
}

-- Read-only globals (cannot be modified)
read_globals = {
    "require",
    "pcall", "xpcall",
    "pairs", "ipairs",
    "tostring", "tonumber",
    "string", "table", "math", "os", "io",
    "type", "getmetatable", "setmetatable",
    "rawget", "rawset", "rawequal", "rawlen",
    "next", "select",
    "unpack", -- Lua 5.1
}

-- Files and patterns to ignore
exclude_files = {
    "dist/",
    "typedefs/",
    "improvements/",
    ".luarocks/",
    "spec/",
}

-- Warnings to ignore
ignore = {
    "212", -- Unused argument (common in callback functions)
    "213", -- Unused loop variable (common in pairs/ipairs)
    "311", -- Value assigned to variable is unused (false positives in complex flow analysis)
    "542", -- Empty if branch (intentional early returns and error handling)
    "431", -- Shadowing upvalue (acceptable in nested scopes)
    "432", -- Shadowing definition of variable (acceptable in different scopes)
    "631", -- Line too long (handled by StyLua)
    "211", -- Unused local variables (including underscore-prefixed)
    "231", -- Variables set but never accessed (including underscore-prefixed)
}

-- Pattern-specific configurations
files["src/**/*.lua"] = {
    -- Source files can use all defined globals
}

files["spec/**/*.lua"] = {
    -- Test files (when we add them)
    globals = {
        "describe", "it", "before_each", "after_each", -- busted globals
        "assert", "spy", "stub", "mock", -- busted assertion/mocking
    }
}