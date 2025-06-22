--[[--
API Utilities

This module contains shared utility functions used across the Miniflux API modules.

@module koplugin.miniflux.api.utils
--]]

local apiUtils = {}

---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortDirection "asc"|"desc"

---@class ApiOptions
---@field limit? number Maximum number of entries to return
---@field order? "id"|"status"|"published_at"|"category_title"|"category_id" Field to sort by
---@field direction? SortDirection Sort direction
---@field status? EntryStatus[] Entry status filter
---@field category_id? number Filter by category ID
---@field feed_id? number Filter by feed ID
---@field published_before? number Filter entries published before this timestamp
---@field published_after? number Filter entries published after this timestamp

---Convert ApiOptions to query parameters
---@param options? ApiOptions Query options for filtering and sorting
---@return table Query parameters table
function apiUtils.buildQueryParams(options)
    if not options then
        return {}
    end

    local params = {}

    if options.limit then
        params.limit = options.limit
    end

    if options.order then
        params.order = options.order
    end

    if options.direction then
        params.direction = options.direction
    end

    if options.status then
        params.status = options.status
    end

    if options.category_id then
        params.category_id = options.category_id
    end

    if options.feed_id then
        params.feed_id = options.feed_id
    end

    if options.published_before then
        params.published_before = options.published_before
    end

    if options.published_after then
        params.published_after = options.published_after
    end

    return params
end

return apiUtils
