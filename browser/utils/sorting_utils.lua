--[[--
Sorting Utilities for Miniflux Browser

This utility module handles sorting and filtering operations for browser menu items,
following the single responsibility principle.

@module miniflux.browser.utils.sorting_utils
--]]--

local SortingUtils = {}

---Get unread count from an item (handles different data structures)
---@param item table Menu item to get unread count from
---@return number Unread count
---@return string Title for alphabetical sorting
local function getUnreadCountAndTitle(item)
    -- Handle feeds (direct unread_count property)
    if item.unread_count then
        return item.unread_count, item.text or ""
    end
    
    -- Handle categories (nested in category_data)
    if item.category_data and item.category_data.unread_count then
        return item.category_data.unread_count, item.category_data.title or ""
    end
    
    -- Fallback
    return 0, item.text or ""
end

---Sort menu items by unread count (unified function for feeds and categories)
---@param items table[] Array of menu items to sort
---@return nil
function SortingUtils.sortByUnreadCount(items)
    table.sort(items, function(a, b)
        local a_unread, a_title = getUnreadCountAndTitle(a)
        local b_unread, b_title = getUnreadCountAndTitle(b)
        
        -- Items with unread entries come first
        if a_unread > 0 and b_unread == 0 then
            return true
        elseif a_unread == 0 and b_unread > 0 then
            return false
        end
        
        -- If both have unread entries, sort by unread count (descending)
        if a_unread > 0 and b_unread > 0 and a_unread ~= b_unread then
            return a_unread > b_unread
        end
        
        -- Otherwise sort alphabetically
        return a_title:lower() < b_title:lower()
    end)
end

return SortingUtils 