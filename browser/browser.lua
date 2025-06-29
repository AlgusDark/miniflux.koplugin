--[[--
Generic Browser - Base class for content browsers

Provides generic browser functionality including navigation, menu integration,
and UI management. Specialized browsers extend this class and implement
abstract methods for provider-specific behavior.

@module browser.browser
--]]

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")

-- Navigation type definitions for generic browser functionality
---@alias NavigationContext {feed_id?: number, category_id?: number}
---@alias NavigationState {from: string, to: string, page_state: number, context?: NavigationContext}
---@alias ForwardNavigationConfig {from: string, to: string, context?: NavigationContext}
---@alias RouteConfig {view_name: string, page_state?: number, context?: NavigationContext}

---@class BrowserOptions : MenuOptions

---@class Browser : Menu
---@field settings MinifluxSettings Plugin settings
---@field api MinifluxAPI API client
---@field download_dir string Download directory path
---@field entry_service EntryService Entry service instance
---@field miniflux_plugin Miniflux Plugin instance for context management
local Browser = Menu:extend({
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
})

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function Browser:init()
    -- Required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir
    self.miniflux_plugin = self.miniflux_plugin or error("miniflux_plugin required")

    -- Require shared EntryService
    self.entry_service = self.entry_service or error("entry_service required")

    -- Set up settings button
    self.onLeftButtonTap = function()
        self:showConfigDialog()
    end

    -- Initialize Menu parent
    Menu.init(self)
end

-- =============================================================================
-- MAIN ENTRY POINT
-- =============================================================================

---Open the browser (defaults to main view, but flexible for future use)
---@param view_name? string View to open to (defaults to "main")
function Browser:open(view_name)
    self:navigate({ view_name = view_name or "main" })
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function Browser:showConfigDialog()
    if not self.settings then
        local Notification = require("utils/notification")
        Notification:error(_("Settings not available"))
        return
    end

    local buttons = {
        {
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(self.config_dialog)
                end,
            },
        },
    }

    self.config_dialog = ButtonDialogTitle:new({
        title = _("Settings"),
        title_align = "center",
        buttons = buttons,
    })
    UIManager:show(self.config_dialog)
end

-- =============================================================================
-- NAVIGATION MANAGEMENT
--
-- Simple navigation using self.paths (like OPDSBrowser) to store NavigationState objects.
-- Each navigation state contains: {from, to, page_state, context}
--
-- Flow:
-- 1. User clicks "Feeds" → goForward() → store current state in self.paths → navigate()
-- 2. User hits back → goBack() → pop from self.paths → navigate()
-- 3. navigate() routes to appropriate view using provider-specific getRouteHandlers()
-- =============================================================================

---Get current item number for page state restoration
---@return number Current item number (for use with switchItemTable)
function Browser:getCurrentItemNumber()
    local page = tonumber(self.page) or 1
    local perpage = tonumber(self.perpage) or 20
    local current_item = tonumber(self.itemnumber) or 1

    if page > 1 then
        local item_number = (page - 1) * perpage + current_item
        return math.max(item_number, 1)
    end

    return math.max(current_item, 1)
end

---Navigate forward (store current state in paths and route to new view)
---@param nav_config ForwardNavigationConfig Forward navigation configuration
function Browser:goForward(nav_config)
    -- Store current navigation state in self.paths (like OPDSBrowser)
    self.paths = self.paths or {}
    local nav_state = {
        from = nav_config.from,
        to = nav_config.to,
        page_state = self:getCurrentItemNumber(),
    }
    if nav_config.context then
        nav_state.context = nav_config.context
    end
    table.insert(self.paths, nav_state)

    -- Navigate to new view (always start fresh when going forward)
    local route_config = {
        view_name = nav_config.to,
        page_state = nil, -- start fresh
    }
    if nav_config.context then
        route_config.context = nav_config.context
    end
    self:navigate(route_config)
end

---Navigate back (pop previous state from paths and route back)
function Browser:goBack()
    local prev_nav = table.remove(self.paths)
    if prev_nav then
        -- Navigate back to previous view (restore page position)
        local route_config = {
            view_name = prev_nav.from,
            page_state = prev_nav.page_state, -- restore position
        }
        if prev_nav.context then
            route_config.context = prev_nav.context
        end
        self:navigate(route_config)
    end
end

---Core navigation method (handles view routing, back button setup, and browser visibility)
---@param nav_config RouteConfig Navigation configuration
function Browser:navigate(nav_config)
    if not UIManager:isWidgetShown(self) then
        UIManager:show(self)
    end

    -- Set up back button if we have navigation history
    if #self.paths > 0 then
        self.onReturn = function() self:goBack() end
    else
        self.onReturn = nil -- At root
    end

    -- Get provider-specific route handlers
    local view_handlers = self:getRouteHandlers(nav_config)
    local handler = view_handlers[nav_config.view_name]
    if not handler then
        error("Unknown view: " .. tostring(nav_config.view_name))
    end

    -- Get view data from the view component
    local view_data = handler()
    if not view_data then
        return -- Error already handled by view component
    end

    -- Handle navigation state based on view data
    if view_data.is_root then
        self.paths = {}
        self.onReturn = nil
    end

    -- Render the view using returned data
    self:switchItemTable(
        view_data.title,
        view_data.items,
        view_data.page_state,
        view_data.menu_title,
        view_data.subtitle
    )
end

---Close the browser (for compatibility with entry service)
function Browser:close()
    UIManager:close(self)
end

-- =============================================================================
-- ABSTRACT METHODS (Must be implemented by subclasses)
-- =============================================================================

---Get route handlers for this browser type
---@param nav_config RouteConfig Navigation configuration
---@return table<string, function> Route handlers lookup table
function Browser:getRouteHandlers(nav_config)
    error("Browser subclass must implement getRouteHandlers(nav_config)")
end

---Open an item with optional navigation context
---@param item_data table Item data to open
---@param context? table Navigation context
function Browser:openItem(item_data, context)
    error("Browser subclass must implement openItem()")
end

return Browser
