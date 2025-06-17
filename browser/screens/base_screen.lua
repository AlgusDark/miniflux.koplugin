--[[--
Base Screen for Miniflux Browser

This is the base class that provides common functionality for all browser screens.
It standardizes patterns for initialization, error handling, loading messages,
cache management, and navigation data creation.

@module miniflux.browser.screens.base_screen
--]]--

local BrowserUtils = require("browser/utils/browser_utils")
local ErrorUtils = require("browser/utils/error_utils")
local _ = require("gettext")

---@class BaseScreen
---@field browser MainBrowser Reference to the browser instance
local BaseScreen = {}

---Create a new base screen instance
---@return BaseScreen
function BaseScreen:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end



---Initialize the screen with browser reference
---@param browser BaseBrowser Browser instance to manage
---@return nil
function BaseScreen:init(browser)
    self.browser = browser
end

-- =============================================================================
-- LOADING AND ERROR HANDLING UTILITIES
-- =============================================================================

---Show loading message and return loading info
---@param message string Loading message to display
---@return table Loading info for cleanup
function BaseScreen:showLoadingMessage(message)
    return self.browser:showLoadingMessage(message)
end

---Close loading message
---@param loading_info table Loading info from showLoadingMessage
---@return nil
function BaseScreen:closeLoadingMessage(loading_info)
    self.browser:closeLoadingMessage(loading_info)
end



---Show error message to user
---@param message string Error message to display
---@return nil
function BaseScreen:showErrorMessage(message)
    self.browser:showErrorMessage(message)
end

---Perform API call with standardized error handling
---@param params {operation_name: string, api_call_func: function, loading_message: string, data_name?: string, skip_validation?: boolean}
---@return any|nil Result data or nil if failed
function BaseScreen:performApiCall(params)
    return ErrorUtils.handleApiCall({
        browser = self.browser,
        operation_name = params.operation_name,
        api_call_func = params.api_call_func,
        loading_message = params.loading_message,
        data_name = params.data_name,
        skip_validation = params.skip_validation
    })
end



-- =============================================================================
-- NAVIGATION AND BROWSER INTEGRATION
-- =============================================================================

---Create navigation data for browser updates
---@param paths_updated? boolean Whether navigation paths were updated
---@param parent_type string Parent screen type
---@param current_data? table Current screen data
---@param page_info? table Page information for restoration
---@param is_settings_refresh? boolean Whether this is a settings refresh
---@return table Navigation data
function BaseScreen:createNavigationData(paths_updated, parent_type, current_data, page_info, is_settings_refresh)
    return self.browser.page_state_manager:createNavigationData(
        paths_updated or false,
        parent_type,
        current_data,
        page_info,
        is_settings_refresh or false
    )
end

---Update browser with new content
---@param title string Browser title
---@param items table[] Menu items
---@param subtitle string Browser subtitle
---@param navigation_data table Navigation data
---@return nil
function BaseScreen:updateBrowser(title, items, subtitle, navigation_data)
    self.browser:updateBrowser(title, items, subtitle, navigation_data)
end

---Show entries list via browser
---@param entries table[] List of entries
---@param title_prefix string Screen title prefix
---@param is_category boolean Whether this is a category view
---@param navigation_data table Navigation data
---@return nil
function BaseScreen:showEntriesList(entries, title_prefix, is_category, navigation_data)
    self.browser:showEntriesList(entries, title_prefix, is_category, navigation_data)
end

-- =============================================================================
-- SETTINGS ACCESS UTILITIES
-- =============================================================================

---Get API options from settings
---@return ApiOptions Options for API calls
function BaseScreen:getApiOptions()
    return BrowserUtils.getApiOptions(self.browser.settings)
end

---Check if read entries should be hidden
---@return boolean True if read entries should be hidden
function BaseScreen:shouldHideReadEntries()
    return self.browser.settings and self.browser.settings:getHideReadEntries()
end

---Get status icon for subtitles
---@return string Eye icon based on hide read entries setting
function BaseScreen:getStatusIcon()
    local hide_read_entries = self:shouldHideReadEntries()
    return hide_read_entries and "⊘ " or "◯ "
end

-- =============================================================================
-- COMMON UI PATTERNS
-- =============================================================================

---Create "no entries" menu item
---@param is_unread_only? boolean Whether this is for unread-only view
---@return table Menu item for no entries message
function BaseScreen:createNoEntriesItem(is_unread_only)
    local message
    if is_unread_only then
        message = _("There are no unread entries.")
    else
        local hide_read_entries = self:shouldHideReadEntries()
        message = hide_read_entries and _("There are no unread entries.") or _("There are no entries.")
    end
    
    return {
        text = message,
        mandatory = "",
        action_type = "no_action",
    }
end

---Build subtitle with count and status icon
---@param count number Item count
---@param item_type string Type of items (e.g., "feeds", "categories", "entries")
---@param is_unread_only? boolean Whether showing unread only
---@return string Formatted subtitle
function BaseScreen:buildSubtitle(count, item_type, is_unread_only)
    local icon = self:getStatusIcon()
    
    if is_unread_only then
        return "⊘ " .. count .. " " .. _("unread " .. item_type)
    else
        return icon .. count .. " " .. _(item_type)
    end
end

-- =============================================================================
-- ABSTRACT METHODS (to be overridden by subclasses)
-- =============================================================================

---Show main content (must be overridden by subclasses)
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function BaseScreen:show(paths_updated, page_info)
    error("BaseScreen:show() must be overridden by subclass")
end

---Show content for navigation restoration (default implementation)
---@param paths_updated? boolean Whether navigation paths were updated
---@param page_info? table Page information for restoration
---@return nil
function BaseScreen:showContent(paths_updated, page_info)
    -- Default implementation calls show with paths_updated = true
    self:show(paths_updated or true, page_info)
end

---Invalidate cached data (to be overridden by subclasses that use caching)
---@return nil
function BaseScreen:invalidateCache()
    -- Base implementation does nothing - subclasses override if needed
end

return BaseScreen 