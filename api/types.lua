--[[--
Miniflux API Type Definitions

This module contains all type aliases and data structure definitions used throughout
the Miniflux API system. Centralizing types here prevents duplication and ensures
consistency across all modules.

@module koplugin.miniflux.api.types
--]]--

---@alias HttpMethod "GET"|"POST"|"PUT"|"DELETE"
---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortOrder "id"|"status"|"published_at"|"category_title"|"category_id"
---@alias SortDirection "asc"|"desc"

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field url string Entry URL
---@field content string Entry content
---@field summary string Entry summary
---@field status EntryStatus Entry read status
---@field starred boolean Whether entry is bookmarked
---@field published_at string Publication timestamp
---@field created_at string Creation timestamp
---@field feed MinifluxFeed Associated feed information

---@class MinifluxFeed
---@field id number Feed ID
---@field title string Feed title
---@field site_url string Feed website URL
---@field feed_url string Feed RSS URL
---@field category MinifluxCategory Feed category

---@class MinifluxCategory
---@field id number Category ID
---@field title string Category title
---@field total_unread number Number of unread entries in category

---@class MinifluxUser
---@field id number User ID
---@field username string Username
---@field is_admin boolean Whether user is admin

---@class ApiOptions
---@field limit? number Maximum number of entries to fetch
---@field order? SortOrder Sort order field
---@field direction? SortDirection Sort direction
---@field status? EntryStatus[]|EntryStatus Entry status filter

---@class EntriesResponse
---@field entries MinifluxEntry[] Array of entries
---@field total number Total number of entries matching criteria

---@class FeedCounters
---@field reads table<string, number> Read counts by feed ID
---@field unreads table<string, number> Unread counts by feed ID

-- Export types for use by other modules
local Types = {}

-- Type validation functions
Types.isValidHttpMethod = function(method)
    local valid_methods = {GET = true, POST = true, PUT = true, DELETE = true}
    return valid_methods[method] ~= nil
end

Types.isValidEntryStatus = function(status)
    local valid_statuses = {read = true, unread = true, removed = true}
    return valid_statuses[status] ~= nil
end

Types.isValidSortOrder = function(order)
    local valid_orders = {
        id = true,
        status = true,
        published_at = true,
        category_title = true,
        category_id = true
    }
    return valid_orders[order] ~= nil
end

Types.isValidSortDirection = function(direction)
    local valid_directions = {asc = true, desc = true}
    return valid_directions[direction] ~= nil
end

return Types 