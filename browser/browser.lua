--[[--
Generic Browser - Base Class for Content Browsers

Provides common browser functionality including navigation, history management,
and content display. Designed to be extended by specific browser implementations.

@module browser.browser
--]]

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local BrowserHistory = require("browser/browser_history")
local UIComponents = require("utils/ui_components")
local _ = require("gettext")

---@class ContentData
---@field title string Browser title
---@field items table[] Menu items to display
---@field params? ShowContentParams Parameters for history and page restoration
---@field subtitle? string Optional subtitle

---@class ShowContentParams
---@field paths_updated? boolean Whether this is a back navigation (don't add to history)
---@field page_info? PageInfo Page information for restoration
---@field [string] any Additional parameters specific to browser implementation

---@class Browser : Menu
---@field close_callback function|nil Callback function to execute when closing the browser
---@field history BrowserHistory Browser navigation history
---@field current_location string Current location/view for refreshing
---@field current_params table Current parameters for refreshing
---@field new fun(self: Browser, o: table): Browser Override Menu:new to return correct type
local Browser = Menu:extend({
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
    close_callback = nil,
})

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function Browser:init()
    -- Initialize browser history
    self.history = BrowserHistory:new()

    -- Current location tracking for refresh functionality
    self.current_location = self:getInitialLocation()
    self.current_params = {}

    -- Generate initial menu (will be populated by navigate)
    self.title = self.title or _("Browser")
    self.item_table = {}

    -- Set up settings button (if onLeftButtonTap not already defined)
    if not self.onLeftButtonTap then
        self.onLeftButtonTap = function()
            self:showSettingsDialog()
        end
    end

    -- Initialize parent
    Menu.init(self)
end

-- =============================================================================
-- ABSTRACT METHODS - MUST BE IMPLEMENTED BY SUBCLASSES
-- =============================================================================

---Navigate to a specific location (must be implemented by subclass)
---@param location string Target location identifier
---@param params? table Navigation parameters
function Browser:navigate(location, params)
    error("Browser:navigate must be implemented by subclass")
end

---Get the initial location for the browser (must be implemented by subclass)
---@return string location Initial location identifier
function Browser:getInitialLocation()
    return "main"
end

---Determine if this navigation should be added to history (can be overridden by subclass)
---@param location string Target location
---@param params table Navigation parameters
---@return boolean should_add_to_history
function Browser:shouldAddToHistory(location, params)
    -- Default: add to history unless explicitly marked as paths_updated
    return not (params and params.paths_updated)
end

---Create history state for current location (can be overridden by subclass)
---@return HistoryState|nil state State to save, or nil if shouldn't save
function Browser:createHistoryState()
    -- Default implementation - subclasses should override to provide specific state
    if not self.current_location then
        return nil
    end

    return {
        location = self.current_location,
        params = self.current_params or {},
        page_info = {
            page = self.page or 1,
            perpage = self.perpage or 20,
        }
    }
end

---Show settings dialog (can be overridden by subclass)
function Browser:showSettingsDialog()
    UIComponents.showInfoMessage(_("Settings not implemented"), 2)
end

-- =============================================================================
-- CONTENT UPDATE AND DISPLAY
-- =============================================================================

---Update browser content and handle history
---@param content_data ContentData Content to display
---@param target_location? string Explicit target location (if different from inferred)
function Browser:updateContent(content_data, target_location)
    if not content_data or not content_data.title or not content_data.items then
        UIComponents.showErrorMessage(_("Invalid content data"))
        return
    end

    local params = content_data.params or {}
    local location = target_location or self.current_location or self:getInitialLocation()

    -- Handle navigation history - save current state before navigating
    if self:shouldAddToHistory(location, params) then
        local history_state = self:createHistoryState()
        if history_state then
            self.history:push(history_state)
        end
    end

    -- Update current location tracking
    self.current_location = location
    self.current_params = params

    -- Handle page restoration for back navigation
    local select_number = 1
    if params.page_info then
        select_number = self:calculateSelectNumber(params.page_info, #content_data.items)
    end

    -- Update browser content
    self.title = content_data.title
    self.subtitle = content_data.subtitle or ""
    self:switchItemTable(content_data.title, content_data.items, select_number, nil, content_data.subtitle)

    -- Update back button state
    self:updateBackButton()
end

---Show main screen (calls navigate with initial location)
function Browser:showMainScreen()
    local initial_location = self:getInitialLocation()
    self:navigate(initial_location)
    UIManager:show(self)
end

-- =============================================================================
-- NAVIGATION AND HISTORY
-- =============================================================================

---Navigate back in history
---@return boolean success True if navigation was successful
function Browser:goBack()
    local restore_state = self.history:goBack()
    if not restore_state then
        return false
    end

    -- Navigate to previous location with error handling
    local success = pcall(function()
        self:navigate(restore_state.location, {
            paths_updated = true,
            page_info = restore_state.page_info,
            -- Merge any additional parameters from history
            unpack(restore_state.params or {})
        })
    end)

    if not success then
        UIComponents.showErrorMessage(_("Navigation failed"))
        self:navigate(self:getInitialLocation(), { paths_updated = true })
        return false
    end

    self:updateBackButton()
    return true
end

---Clear all navigation history
function Browser:clearHistory()
    self.history:clear()
    self:updateBackButton()
end

---Check if back navigation is possible
---@return boolean can_go_back True if there's history to go back to
function Browser:canGoBack()
    return self.history:canGoBack()
end

-- =============================================================================
-- MENU HANDLING
-- =============================================================================

function Browser:onMenuSelect(item)
    if not item then
        return
    end

    -- If item has onSelect function, call it
    if item.onSelect and type(item.onSelect) == "function" then
        item.onSelect(self, item)
        return
    end

    -- Fallback to action handling (for backward compatibility)
    self:handleItemAction(item)
end

---Handle item actions (should be overridden by subclass)
---@param item table Menu item
function Browser:handleItemAction(item)
    -- Default implementation - subclasses should override
    UIComponents.showInfoMessage(_("Action not implemented"), 2)
end

-- =============================================================================
-- REFRESH AND STATE MANAGEMENT
-- =============================================================================

---Refresh current view
function Browser:refreshCurrentView()
    local location = self.current_location
    local params = self.current_params or {}
    params.paths_updated = true -- Don't add to history

    self:navigate(location, params)
end

-- =============================================================================
-- UTILITY METHODS
-- =============================================================================

---Update back button state based on navigation stack
function Browser:updateBackButton()
    if self.history:canGoBack() then
        self.onReturn = function()
            return self:goBack()
        end
        -- Sync with Menu widget's paths for back button display
        if not self.paths then
            self.paths = {}
        end
        local depth = self.history:getDepth()
        while #self.paths < depth do
            table.insert(self.paths, true)
        end
    else
        self.onReturn = nil
        if self.paths then
            self.paths = {}
        end
    end

    -- Update page info to show/hide back button
    if self.updatePageInfo then
        pcall(function()
            self:updatePageInfo()
        end)
    end
end

---Calculate select number for page restoration
---@param page_info PageInfo Page information
---@param total_items number Total number of items
---@return number select_number Item number to select
function Browser:calculateSelectNumber(page_info, total_items)
    local target_page = page_info.page
    if target_page and target_page >= 1 then
        local perpage = self.perpage or 20
        local select_number = (target_page - 1) * perpage + 1
        if select_number > total_items then
            select_number = total_items > 0 and total_items or 1
        end
        return select_number
    end
    return 1
end

function Browser:closeAll()
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
end

return Browser
