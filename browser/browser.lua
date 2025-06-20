--[[--
Miniflux Browser - Main Coordinator

Browser component that coordinates between various services to provide a unified
browsing experience for Miniflux. Delegates specific responsibilities to:
- ViewService: Content display and view state management
- PathService: Navigation path management and back button logic
- DialogService: User dialog interactions (via EntryUtils)
- NavigationService: Complex entry navigation logic (via EntryUtils)

@module miniflux.browser.browser
--]] --

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local MenuBuilder = require("browser/menu_builder")
local EntryUtils = require("browser/utils/entry_utils")
local NavigationContext = require("utils/navigation_context")
local UIComponents = require("utils/ui_components")
local ViewService = require("services/view_service")
local PathService = require("services/path_service")
local _ = require("gettext")

---@class MinifluxBrowser : Menu
---@field close_callback function|nil Callback function to execute when closing the browser
---@field unread_count number|nil Number of unread entries
---@field feeds_count number|nil Number of feeds
---@field categories_count number|nil Number of categories
---@field view_service ViewService Service handling content display and view state
---@field path_service PathService Service handling navigation paths and back button
---@field entry_utils EntryUtils Utility handling entry display and dialog management
---@field data MenuBuilder Data layer for menu item generation
local MinifluxBrowser = Menu:extend {
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
    close_callback = nil,
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MinifluxBrowser:init()
    -- Required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir

    -- Initialize menu builder
    self.data = MenuBuilder:new(self.api, self.settings)

    -- Initialize EntryUtils instance with settings dependency
    self.entry_utils = EntryUtils:new(self.settings)

    -- Initialize ViewService
    self.view_service = ViewService:new(self, self.data, self.settings)

    -- Initialize PathService and wire it up
    self.path_service = PathService:new(self, self.view_service)
    self.view_service:setPathService(self.path_service)

    -- Navigation state
    self.navigation_paths = {}
    self.current_context = { type = "main" }

    -- Generate initial menu
    self.title = self.title or _("Miniflux")
    self.item_table = self:generateMainMenu()

    -- Set up settings button
    self.onLeftButtonTap = function()
        self:showConfigDialog()
    end

    -- Initialize parent
    Menu.init(self)
end

function MinifluxBrowser:generateMainMenu()
    local unread_count = self.unread_count or 0
    local feeds_count = self.feeds_count or 0
    local categories_count = self.categories_count or 0

    return {
        {
            text = _("Unread"),
            mandatory = tostring(unread_count),
            action_type = "unread"
        },
        {
            text = _("Feeds"),
            mandatory = tostring(feeds_count),
            action_type = "feeds"
        },
        {
            text = _("Categories"),
            mandatory = tostring(categories_count),
            action_type = "categories"
        }
    }
end

-- =============================================================================
-- MENU HANDLING
-- =============================================================================

function MinifluxBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        return
    end

    if item.action_type == "unread" then
        self.view_service:showUnreadEntries()
    elseif item.action_type == "feeds" then
        self.view_service:showFeeds()
    elseif item.action_type == "categories" then
        self.view_service:showCategories()
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            self.view_service:showFeedEntries(feed_data.id, feed_data.title)
        end
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            self.view_service:showCategoryEntries(category_data.id, category_data.title)
        end
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data then
            self:openEntry(entry_data)
        end
    end
end

-- =============================================================================
-- CONTENT DISPLAY METHODS (delegated to ViewService)
-- =============================================================================

function MinifluxBrowser:openEntry(entry_data)
    -- Set navigation context directly using NavigationContext

    if self.current_context.type == "feed_entries" and self.current_context.feed_id then
        NavigationContext.setFeedContext(self.current_context.feed_id, entry_data.id)
    elseif self.current_context.type == "category_entries" and self.current_context.category_id then
        NavigationContext.setCategoryContext(self.current_context.category_id, entry_data.id)
    else
        -- For unread_entries or any other context, use global
        NavigationContext.setGlobalContext(entry_data.id)
    end

    -- Show the entry using EntryUtils instance
    self.entry_utils:showEntry({
        entry = entry_data,
        api = self.api,
        download_dir = self.download_dir,
        browser = self,
    })
end

function MinifluxBrowser:showMainContent()
    self.view_service:showMainContent()
end

-- =============================================================================
-- NAVIGATION MANAGEMENT (delegated to PathService)
-- =============================================================================

function MinifluxBrowser:createNavData(paths_updated, parent_type, current_data, page_info)
    return self.path_service:createNavData(paths_updated, parent_type, current_data, page_info)
end

function MinifluxBrowser:updateBackButton()
    self.path_service:updateBackButton()
end

function MinifluxBrowser:goBack()
    return self.path_service:goBack()
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function MinifluxBrowser:showConfigDialog()
    if not self.settings then
        UIComponents.showErrorMessage(_("Settings not available"))
        return
    end

    local is_entry_view = self.view_service:isInEntryView()
    local is_unread_view = self.current_context.type == "unread_entries"

    local buttons = {}

    -- Show toggle only for non-unread entry views
    if is_entry_view and not is_unread_view then
        local hide_read = self.settings.hide_read_entries
        local eye_icon = hide_read and "◯ " or "⊘ "
        local button_text = eye_icon .. (hide_read and _("Show all entries") or _("Show only unread entries"))

        table.insert(buttons, {
            {
                text = button_text,
                callback = function()
                    UIManager:close(self.config_dialog)
                    self:toggleReadEntriesVisibility()
                end,
            },
        })
    end

    -- Close button
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(self.config_dialog)
            end,
        },
    })

    self.config_dialog = ButtonDialogTitle:new {
        title = _("Miniflux Settings"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.config_dialog)
end

function MinifluxBrowser:toggleReadEntriesVisibility()
    local now_hidden = self.settings:toggleHideReadEntries()
    local message = now_hidden and _("Now showing only unread entries") or _("Now showing all entries")
    UIComponents.showInfoMessage(message, 2)

    -- Refresh current view
    self.view_service:refreshCurrentView()
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

function MinifluxBrowser:closeAll()
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
end

return MinifluxBrowser
