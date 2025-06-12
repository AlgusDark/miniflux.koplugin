--[[--
Enums for Miniflux settings

This module defines all valid enumeration values used throughout the settings system.

@module koplugin.miniflux.settings.enums
--]]--

---@class MinifluxEnums
local MinifluxEnums = {}

---Valid sort order options
---@type table<string, {key: SortOrder, name: string}>
MinifluxEnums.SORT_ORDERS = {
    ID = {key = "id", name = "ID"},
    STATUS = {key = "status", name = "Status"},
    PUBLISHED_AT = {key = "published_at", name = "Published date"},
    CATEGORY_TITLE = {key = "category_title", name = "Category title"},
    CATEGORY_ID = {key = "category_id", name = "Category ID"},
}

---Valid sort direction options
---@type table<string, {key: SortDirection, name: string}>
MinifluxEnums.SORT_DIRECTIONS = {
    ASCENDING = {key = "asc", name = "Ascending"},
    DESCENDING = {key = "desc", name = "Descending"},
}

---Default values for all settings
---@type table<string, any>
MinifluxEnums.DEFAULTS = {
    server_address = "",
    api_token = "",
    limit = 100,
    order = "published_at",
    direction = "desc",
    hide_read_entries = true,
    auto_mark_read = false,
    download_images = false,
    include_images = true,
    entry_font_size = 14
}

---Get all valid sort order keys
---@return SortOrder[] Array of valid sort order keys
function MinifluxEnums.getValidSortOrders()
    local orders = {}
    for _, order in pairs(MinifluxEnums.SORT_ORDERS) do
        table.insert(orders, order.key)
    end
    return orders
end

---Get all valid sort direction keys
---@return SortDirection[] Array of valid sort direction keys
function MinifluxEnums.getValidSortDirections()
    local directions = {}
    for _, direction in pairs(MinifluxEnums.SORT_DIRECTIONS) do
        table.insert(directions, direction.key)
    end
    return directions
end

---Check if a sort order is valid
---@param order string Sort order to validate
---@return boolean True if valid
function MinifluxEnums.isValidSortOrder(order)
    for _, valid_order in pairs(MinifluxEnums.SORT_ORDERS) do
        if valid_order.key == order then
            return true
        end
    end
    return false
end

---Check if a sort direction is valid
---@param direction string Sort direction to validate
---@return boolean True if valid
function MinifluxEnums.isValidSortDirection(direction)
    for _, valid_direction in pairs(MinifluxEnums.SORT_DIRECTIONS) do
        if valid_direction.key == direction then
            return true
        end
    end
    return false
end

return MinifluxEnums 