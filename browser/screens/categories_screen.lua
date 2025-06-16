--[[--
Categories Screen for Miniflux Browser

This module handles the display of categories list and navigation to individual categories.
It manages category data presentation and user interactions.

@module miniflux.browser.screens.categories_screen
--]]--

local BaseScreen = require("browser/screens/base_screen")
local SortingUtils = require("browser/utils/sorting_utils")
local _ = require("gettext")

---@class CategoryMenuItem
---@field text string Menu item display text
---@field mandatory string Unread count display
---@field action_type string Action type identifier
---@field category_data MinifluxCategory Category data

---@class CategoriesScreen : BaseScreen
---@field cached_categories? MinifluxCategory[] Cached categories data
local CategoriesScreen = BaseScreen:extend{}

---Show categories list screen
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function CategoriesScreen:show(paths_updated, page_info)
    -- Request categories with counts enabled
    local result = self:performApiCall({
        operation_name = "fetch categories",
        api_call_func = function()
            return self.browser.api:getCategories(true)
        end,
        loading_message = _("Fetching categories..."),
        data_name = "categories"
    })
    
    if not result then
        return
    end
    
    -- Build menu items
    local menu_items = self:buildCategoryMenuItems(result)
    
    -- Sort by unread count
    SortingUtils.sortByUnreadCount(menu_items)
    
    -- Create navigation data
    local navigation_data = self:createNavigationData(
        paths_updated, 
        "main", 
        nil, 
        page_info  -- This is still used for logging in createNavigationData
    )
    
    -- If page_info is provided (back navigation), add it as restore_page_info
    if page_info then
        navigation_data.restore_page_info = page_info
    end
    
    -- Build subtitle with status icon
    local subtitle = self:buildSubtitle(#result, "categories")
    
    self:updateBrowser(_("Categories"), menu_items, subtitle, navigation_data)
end

---Build menu items for categories
---@param categories MinifluxCategory[] List of categories
---@return CategoryMenuItem[] Array of category menu items
function CategoriesScreen:buildCategoryMenuItems(categories)
    local menu_items = {}
    
    for _, category in ipairs(categories) do
        local category_title = category.title or _("Untitled Category")
        local unread_count = category.total_unread or 0
        
        local menu_item = {
            text = category_title,
            action_type = "category_entries",
            category_data = {
                id = category.id,
                title = category_title,
                unread_count = unread_count,
            }
        }
        
        -- Always show unread count only for categories (not affected by show/hide read setting)
        menu_item.mandatory = string.format("(%d)", unread_count)
        
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

---Show entries for a specific category
---@param category_id number The category ID
---@param category_title string The category title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function CategoriesScreen:showCategoryEntries(category_id, category_title, paths_updated)
    local options = self:getApiOptions()
    
    local result = self:performApiCall({
        operation_name = "fetch category entries",
        api_call_func = function()
            return self.browser.api:getCategoryEntries(category_id, options)
        end,
        loading_message = _("Fetching entries for category..."),
        data_name = "category entries",
        skip_validation = true  -- Skip validation since we handle empty entries properly
    })
    
    if not result then
        return
    end
    
    -- Check if we have no entries and show appropriate message
    local entries = result.entries or {}
    if #entries == 0 then
        -- Create no entries item
        local no_entries_items = { self:createNoEntriesItem() }
        
        -- Create navigation data
        local navigation_data = self:createNavigationData(
            paths_updated or false,
            "categories", 
            {
                category_id = category_id,
                category_title = category_title,
            },
            nil,  -- page_info
            paths_updated  -- is_settings_refresh when paths_updated is true
        )
        
        self:showEntriesList(no_entries_items, category_title, true, navigation_data)
        return
    end
    
    -- Create navigation data - ensure we capture current page state unless paths are being updated
    local navigation_data = self:createNavigationData(
        paths_updated or false,
        "categories", 
        {
            category_id = category_id,
            category_title = category_title,
        },
        nil,  -- page_info
        paths_updated  -- is_settings_refresh when paths_updated is true
    )
    
    self:showEntriesList(entries, category_title, true, navigation_data)
end

---Show entries for a specific category (refresh version - no navigation context)
---@param category_id number The category ID
---@param category_title string The category title
---@return nil
function CategoriesScreen:showCategoryEntriesRefresh(category_id, category_title)
    -- Call the regular method but indicate this is a refresh (paths_updated = true)
    self:showCategoryEntries(category_id, category_title, true)
end

---Handle category screen content restoration from navigation
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function CategoriesScreen:showContent(paths_updated, page_info)
    -- Show categories but prevent adding to navigation history and include page restoration
    self:show(paths_updated or true, page_info)
end

---Get cached categories
---@return MinifluxCategory[]|nil Cached categories data or nil if not cached
function CategoriesScreen:getCachedCategories()
    -- Simple in-memory cache for categories data
    return self.cached_categories
end

---Cache categories data
---@param categories MinifluxCategory[] Categories data to cache
---@return nil
function CategoriesScreen:cacheCategories(categories)
    -- Simple in-memory cache for categories data
    self.cached_categories = categories
end

---Invalidate cached data
---@return nil
function CategoriesScreen:invalidateCache()
    -- Clear the in-memory cache
    self.cached_categories = nil
end

return CategoriesScreen 