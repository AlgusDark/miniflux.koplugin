--[[--
Miniflux Browser - Main Coordinator

Browser component that coordinates between various services to provide a unified
browsing experience for Miniflux. Delegates specific responsibilities to:
- ViewService: Content display and view state management
- PathService: Navigation path management and back button logic
- Dialog Management: User dialog interactions (integrated in EntryService)
- NavigationService: Complex entry navigation logic (via EntryService)

@module miniflux.browser.browser
--]]

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local EntryRepository = require("repositories/entry_repository")
local FeedRepository = require("repositories/feed_repository")
local CategoryRepository = require("repositories/category_repository")
local MenuFormatter = require("browser/menu_formatter")
local EntryService = require("services/entry_service")
local NavigationContext = require("utils/navigation_context")
local UIComponents = require("utils/ui_components")
local ViewService = require("services/view_service")
local PathService = require("services/path_service")
local _ = require("gettext")

---@class MinifluxBrowser : Menu
---@field close_callback function|nil Callback function to execute when closing the browser
---@field unread_count number|nil Number of unread entries (stored from initialization)
---@field feeds_count number|nil Number of feeds (stored from initialization)
---@field categories_count number|nil Number of categories (stored from initialization)
---@field view_service ViewService Service handling content display and view state
---@field path_service PathService Service handling navigation paths and back button
---@field entry_service EntryService Service handling entry display and dialog management
---@field entry_repository EntryRepository Repository for entry data access
---@field feed_repository FeedRepository Repository for feed data access
---@field category_repository CategoryRepository Repository for category data access
---@field menu_formatter MenuFormatter Formatter for menu items
---@field new fun(self: MinifluxBrowser, o: table): MinifluxBrowser Override Menu:new to return correct type
local MinifluxBrowser = Menu:extend({
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

function MinifluxBrowser:init()
    -- Required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir

    -- Initialize repositories
    self.entry_repository = EntryRepository:new(self.api, self.settings)
    self.feed_repository = FeedRepository:new(self.api, self.settings)
    self.category_repository = CategoryRepository:new(self.api, self.settings)

    -- Initialize menu formatter
    self.menu_formatter = MenuFormatter:new(self.settings)

    -- Initialize EntryService instance with settings and API dependencies
    self.entry_service = EntryService:new(self.settings, self.api)

    -- Initialize ViewService with repositories and formatter
    self.view_service = ViewService:new(
        self,
        self.entry_repository,
        self.feed_repository,
        self.category_repository,
        self.menu_formatter,
        self.settings
    )

    -- Initialize PathService and wire it up
    self.path_service = PathService:new(self, self.view_service)
    self.view_service:setPathService(self.path_service)

    -- Navigation state
    self.navigation_paths = {}
    self.current_context = { type = "main" }

    -- Generate initial menu (will be populated by showMainScreen)
    self.title = self.title or _("Miniflux")
    self.item_table = {}

    -- Set up settings button
    self.onLeftButtonTap = function()
        self:showConfigDialog()
    end

    -- Initialize parent
    Menu.init(self)
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

    -- Show the entry using EntryService instance
    -- EntryService will handle closing the browser and opening the Reader
    self.entry_service:showEntry({
        entry = entry_data,
        api = self.api,
        download_dir = self.download_dir,
        browser = self,
    })
end

-- Navigation methods are handled directly by ViewService and PathService
-- No wrapper methods needed since services call each other directly

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

    self.config_dialog = ButtonDialogTitle:new({
        title = _("Miniflux Settings"),
        title_align = "center",
        buttons = buttons,
    })
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
-- INITIALIZATION AND DATA FETCHING (merged from browser_launcher)
-- =============================================================================

---Show the main Miniflux browser screen with initial data
---@return nil
function MinifluxBrowser:showMainScreen()
    if self.settings.server_address == "" or self.settings.api_token == "" then
        UIManager:show(InfoMessage:new({
            text = _("Please configure server settings first"),
            timeout = 3,
        }))
        return
    end

    -- Show loading message while fetching initial data
    local loading_info = InfoMessage:new({
        text = _("Loading Miniflux data..."),
    })
    UIManager:show(loading_info)
    UIManager:forceRePaint() -- Force immediate display before API calls

    -- Fetch initial data for browser
    local unread_count, feeds_count, categories_count = self:fetchInitialData(loading_info)

    if not unread_count then
        -- Error already handled in fetchInitialData
        return
    end

    -- Close loading message and prepare for browser display
    UIManager:close(loading_info)

    -- Ensure all values are numbers (fallback to 0 if nil)
    self.unread_count = unread_count or 0
    self.feeds_count = feeds_count or 0
    self.categories_count = categories_count or 0

    -- Generate main menu with counts and show it
    self.item_table = self:generateMainMenuWithCounts(self.unread_count, self.feeds_count, self.categories_count)
    self.view_service:showMainContent()

    -- Actually show the browser
    UIManager:show(self)
end

---Fetch initial data needed for browser initialization
---@param loading_info InfoMessage Loading message to update
---@return number|nil unread_count, number|nil feeds_count, number|nil categories_count
function MinifluxBrowser:fetchInitialData(loading_info)
    -- Get unread count
    local unread_count, error_msg = self.entry_repository:getUnreadCount()
    if not unread_count then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new({
            text = _("Failed to connect to Miniflux: ") .. tostring(error_msg),
            timeout = 5,
        }))
        return nil
    end

    -- Update loading message
    UIManager:close(loading_info)
    loading_info = InfoMessage:new({
        text = _("Loading feeds data..."),
    })
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    -- Get feeds count
    local feeds_count = self.feed_repository:getCount()

    -- Update loading message
    UIManager:close(loading_info)
    loading_info = InfoMessage:new({
        text = _("Loading categories data..."),
    })
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    -- Get categories count
    local categories_count = self.category_repository:getCount()

    -- Close the loading message before returning
    UIManager:close(loading_info)

    return unread_count, feeds_count, categories_count
end

---Generate main menu with counts
---@param unread_count number Number of unread entries
---@param feeds_count number Number of feeds
---@param categories_count number Number of categories
---@return table[] Menu items for main screen
function MinifluxBrowser:generateMainMenuWithCounts(unread_count, feeds_count, categories_count)
    return {
        {
            text = _("Unread"),
            mandatory = tostring(unread_count),
            action_type = "unread",
        },
        {
            text = _("Feeds"),
            mandatory = tostring(feeds_count),
            action_type = "feeds",
        },
        {
            text = _("Categories"),
            mandatory = tostring(categories_count),
            action_type = "categories",
        },
    }
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
