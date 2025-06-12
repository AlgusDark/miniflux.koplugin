--[[--
Categories Screen for Miniflux Browser

This module handles the display of categories list and navigation to individual categories.
It manages category data presentation and user interactions.

@module miniflux.browser.screens.categories_screen
--]]--

local BrowserUtils = require("browser/utils/browser_utils")
local SortingUtils = require("browser/utils/sorting_utils")
local _ = require("gettext")

---@class CategoryMenuItem
---@field text string Menu item display text
---@field mandatory string Unread count display
---@field action_type string Action type identifier
---@field category_data MinifluxCategory Category data

---@class CategoriesScreen
---@field browser BaseBrowser Reference to the browser instance
---@field cached_categories? MinifluxCategory[] Cached categories data
local CategoriesScreen = {}

---Create a new categories screen instance
---@return CategoriesScreen
function CategoriesScreen:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function CategoriesScreen:init(browser)
    self.browser = browser
end

-- Show categories list screen
function CategoriesScreen:show(paths_updated, page_info)
    local loading_info = self.browser:showLoadingMessage(_("Fetching categories..."))
    
    -- Request categories with counts enabled
    local success, result
    local ok, err = pcall(function()
        success, result = self.browser.api:getCategories(true)
    end)
    
    self.browser:closeLoadingMessage(loading_info)
    
    if not ok then
        self.browser:showErrorMessage(_("Failed to fetch categories: ") .. tostring(err))
        return
    end
    
    if not self.browser:handleApiError(success, result, _("Failed to fetch categories")) then
        return
    end
    
    if not self.browser:validateData(result, "categories") then
        return
    end
    
    -- Build menu items
    local menu_items = self:buildCategoryMenuItems(result)
    
    -- Sort by unread count
    SortingUtils.sortByUnreadCount(menu_items)
    
    -- Create navigation data
    local navigation_data = self.browser.page_state_manager:createNavigationData(
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
    local hide_read_entries = self.browser.settings and self.browser.settings:getHideReadEntries()
    local eye_icon = hide_read_entries and "⊘ " or "◯ "
    local subtitle = eye_icon .. #result .. _(" categories")
    
    self.browser:updateBrowser(_("Categories"), menu_items, subtitle, navigation_data)
end

-- Build menu items for categories
function CategoriesScreen:buildCategoryMenuItems(categories)
    local menu_items = {}
    
    for i, category in ipairs(categories) do
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

-- Show entries for a specific category
function CategoriesScreen:showCategoryEntries(category_id, category_title, paths_updated)
    local loading_info = self.browser:showLoadingMessage(_("Fetching entries for category..."))
    
    local options = BrowserUtils.getApiOptions(self.browser.settings)
    local success, result
    local ok, err = pcall(function()
        success, result = self.browser.api:getCategoryEntries(category_id, options)
    end)
    
    self.browser:closeLoadingMessage(loading_info)
    
    if not ok then
        self.browser:showErrorMessage(_("Failed to fetch category entries: ") .. tostring(err))
        return
    end
    
    if not self.browser:handleApiError(success, result, _("Failed to fetch category entries")) then
        return
    end
    
    -- Check if we have no entries and show appropriate message
    local entries = result.entries or {}
    if #entries == 0 then
        local hide_read_entries = self.browser.settings and self.browser.settings:getHideReadEntries()
        -- Show "no entries" message
        local no_entries_items = {
            {
                text = hide_read_entries and _("There are no unread entries.") or _("There are no entries."),
                mandatory = "",
                action_type = "no_action",
            }
        }
        
        -- Create navigation data
        local navigation_data = self.browser.page_state_manager:createNavigationData(
            paths_updated or false,
            "categories", 
            {
                category_id = category_id,
                category_title = category_title,
            },
            nil,  -- page_info
            paths_updated  -- is_settings_refresh when paths_updated is true
        )
        
        self.browser:showEntriesList(no_entries_items, category_title, true, navigation_data)
        return
    end
    
    -- Create navigation data - ensure we capture current page state unless paths are being updated
    local navigation_data = self.browser.page_state_manager:createNavigationData(
        paths_updated or false,
        "categories", 
        {
            category_id = category_id,
            category_title = category_title,
        },
        nil,  -- page_info
        paths_updated  -- is_settings_refresh when paths_updated is true
    )
    
    self.browser:showEntriesList(entries, category_title, true, navigation_data)
end

-- Show entries for a specific category (refresh version - no navigation context)
function CategoriesScreen:showCategoryEntriesRefresh(category_id, category_title)
    -- Call the regular method but indicate this is a refresh (paths_updated = true)
    self:showCategoryEntries(category_id, category_title, true)
end

-- Handle category screen content restoration from navigation
function CategoriesScreen:showContent(paths_updated, page_info)
    -- Show categories but prevent adding to navigation history and include page restoration
    self:show(paths_updated or true, page_info)
end

-- Cache management methods
function CategoriesScreen:getCachedCategories()
    -- Simple in-memory cache for categories data
    return self.cached_categories
end

function CategoriesScreen:cacheCategories(categories)
    -- Simple in-memory cache for categories data
    self.cached_categories = categories
end

function CategoriesScreen:invalidateCache()
    -- Clear the in-memory cache
    self.cached_categories = nil
end

return CategoriesScreen 