--[[--
Categories Provider for Miniflux Browser

Simple provider that fetches and formats categories data for the browser.

@module miniflux.browser.providers.categories_provider
--]]--

local _ = require("gettext")

---@class CategoriesProvider
local CategoriesProvider = {}

---Create a new categories provider
---@return CategoriesProvider
function CategoriesProvider:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get categories list with counts
---@param api MinifluxAPI API client instance
---@return boolean success, MinifluxCategory[]|string result_or_error
function CategoriesProvider:getCategories(api)
    return api.categories:getCategories(true) -- true = include counts
end

---Convert categories to menu items for browser
---@param categories MinifluxCategory[] Categories data
---@return table[] Menu items array
function CategoriesProvider:toMenuItems(categories)
    local menu_items = {}
    
    for _, category in ipairs(categories) do
        local category_title = category.title or _("Untitled Category")
        local unread_count = category.total_unread or 0
        
        local menu_item = {
            text = category_title,
            mandatory = string.format("(%d)", unread_count),
            action_type = "category_entries",
            category_data = {
                id = category.id,
                title = category_title,
                unread_count = unread_count,
            }
        }
        
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

---Get subtitle for categories list
---@param count number Number of categories
---@param hide_read_entries boolean Whether read entries are hidden
---@return string Formatted subtitle
function CategoriesProvider:getSubtitle(count, hide_read_entries)
    local icon = hide_read_entries and "⊘ " or "◯ "
    return icon .. count .. " " .. _("categories")
end

return CategoriesProvider 