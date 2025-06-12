--[[--
Sorting Settings Module

This module handles sorting and pagination settings like sort order, direction, and limit.
It follows the single responsibility principle by focusing only on sorting configuration.

@module koplugin.miniflux.settings.sorting_settings
--]]--

local BaseSettings = require("settings/base_settings")
local Enums = require("settings/enums")

---@class SortingSettings : BaseSettings
---@field settings LuaSettings The injected settings storage instance
local SortingSettings = {}
setmetatable(SortingSettings, {__index = BaseSettings})

---Create a new sorting settings instance
---@param o? table Optional initialization table
---@return SortingSettings
function SortingSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Get sort order setting
---@return SortOrder The sort order
function SortingSettings:getOrder()
    return self:get("order", Enums.DEFAULTS.order)
end

---Set sort order with validation
---@param order SortOrder The sort order
---@return boolean True if successfully set
function SortingSettings:setOrder(order)
    return self:setWithValidation(
        "order", 
        order, 
        Enums.isValidSortOrder, 
        Enums.DEFAULTS.order
    )
end

---Get sort direction setting
---@return SortDirection The sort direction
function SortingSettings:getDirection()
    return self:get("direction", Enums.DEFAULTS.direction)
end

---Set sort direction with validation
---@param direction SortDirection The sort direction
---@return boolean True if successfully set
function SortingSettings:setDirection(direction)
    return self:setWithValidation(
        "direction", 
        direction, 
        Enums.isValidSortDirection, 
        Enums.DEFAULTS.direction
    )
end

---Get entries limit setting
---@return number The entries limit
function SortingSettings:getLimit()
    return self:get("limit", Enums.DEFAULTS.limit)
end

---Set entries limit with validation
---@param limit number The entries limit
---@return boolean True if successfully set
function SortingSettings:setLimit(limit)
    local function isValidLimit(lim)
        return type(lim) == "number" and lim > 0 and lim <= 1000
    end
    
    -- Convert to number if it's a string
    if type(limit) == "string" then
        limit = tonumber(limit)
    end
    
    return self:setWithValidation(
        "limit", 
        limit, 
        isValidLimit, 
        Enums.DEFAULTS.limit
    )
end

---Get all sorting settings as a table
---@return table<string, any> Map of sorting settings
function SortingSettings:getAllSortingSettings()
    return {
        order = self:getOrder(),
        direction = self:getDirection(),
        limit = self:getLimit()
    }
end

---Set all sorting settings at once
---@param settings table<string, any> Map of sorting settings
---@return boolean True if all settings were set successfully
function SortingSettings:setAllSortingSettings(settings)
    local success = true
    
    if settings.order then
        success = success and self:setOrder(settings.order)
    end
    
    if settings.direction then
        success = success and self:setDirection(settings.direction)
    end
    
    if settings.limit then
        success = success and self:setLimit(settings.limit)
    end
    
    return success
end

---Get sort order display name
---@return string Human-readable sort order name
function SortingSettings:getOrderDisplayName()
    local order = self:getOrder()
    for _, order_info in pairs(Enums.SORT_ORDERS) do
        if order_info.key == order then
            return order_info.name
        end
    end
    return "Unknown"
end

---Get sort direction display name
---@return string Human-readable sort direction name
function SortingSettings:getDirectionDisplayName()
    local direction = self:getDirection()
    for _, direction_info in pairs(Enums.SORT_DIRECTIONS) do
        if direction_info.key == direction then
            return direction_info.name
        end
    end
    return "Unknown"
end

---Get all available sort orders with display names
---@return table<string, {key: SortOrder, name: string}> Available sort orders
function SortingSettings:getAvailableSortOrders()
    return Enums.SORT_ORDERS
end

---Get all available sort directions with display names
---@return table<string, {key: SortDirection, name: string}> Available sort directions
function SortingSettings:getAvailableSortDirections()
    return Enums.SORT_DIRECTIONS
end

---Reset sorting settings to defaults
---@return boolean True if successfully reset
function SortingSettings:resetToDefaults()
    local success = true
    success = success and self:setOrder(Enums.DEFAULTS.order)
    success = success and self:setDirection(Enums.DEFAULTS.direction)
    success = success and self:setLimit(Enums.DEFAULTS.limit)
    return success
end

return SortingSettings 