--[[--
Miniflux Browser - Direct Repository Access

Simple browser that directly uses repositories for data access.
No intermediate services or coordinators - clean and straightforward.

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
local BrowserHistory = require("browser/browser_history")
local _ = require("gettext")

---@class ShowContentParams
---@field paths_updated? boolean Whether this is a back navigation (don't add to history)
---@field page_info? PageInfo Page information for restoration
---@field category_id? number Category ID for category-specific views
---@field feed_id? number Feed ID for feed-specific views

---@class PageInfo
---@field page number Current page number
---@field perpage number Items per page

---@alias ViewType "main" | "feeds" | "categories" | "feed_entries" | "category_entries" | "unread_entries"

---@class MinifluxBrowser : Menu
---@field close_callback function|nil Callback function to execute when closing the browser
---@field unread_count number|nil Number of unread entries (stored from initialization)
---@field feeds_count number|nil Number of feeds (stored from initialization)
---@field categories_count number|nil Number of categories (stored from initialization)
---@field history BrowserHistory Browser navigation history
---@field current_view_type ViewType Current view type for refreshing
---@field current_view_params table Current view parameters for refreshing
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

    -- Initialize repositories (direct access)
    self.entry_repository = EntryRepository:new(self.api, self.settings)
    self.feed_repository = FeedRepository:new(self.api, self.settings)
    self.category_repository = CategoryRepository:new(self.api, self.settings)

    -- Initialize other components
    self.menu_formatter = MenuFormatter:new(self.settings)
    self.entry_service = EntryService:new(self.settings, self.api)
    self.history = BrowserHistory:new()

    -- Current view tracking for refresh functionality
    self.current_view_type = "main"
    self.current_view_params = {}

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
-- MAIN CONTENT DISPLAY METHODS
-- =============================================================================

---Show main Miniflux screen with counts
---@param params? ShowContentParams Optional parameters
function MinifluxBrowser:showMainContent(params)
    params = params or {}

    -- Use stored counts from initialization
    local hide_read = self.settings and self.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    local main_items = {
        {
            text = _("Unread"),
            mandatory = tostring(self.unread_count or 0),
            action_type = "unread",
        },
        {
            text = _("Feeds"),
            mandatory = tostring(self.feeds_count or 0),
            action_type = "feeds",
        },
        {
            text = _("Categories"),
            mandatory = tostring(self.categories_count or 0),
            action_type = "categories",
        },
    }

    self:updateContent(_("Miniflux"), main_items, params)
end

---Show feeds list with counters
---@param params? ShowContentParams Optional parameters
function MinifluxBrowser:showFeeds(params)
    params = params or {}

    -- Show loading message
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feeds..."))

    -- Direct repository call
    local result, error_msg = self.feed_repository:getAllWithCounters()
    UIComponents.closeLoadingMessage(loading_info)

    if not result then
        UIComponents.showErrorMessage(_("Failed to fetch feeds: ") .. tostring(error_msg))
        return
    end

    -- Direct menu generation
    local menu_items = self.menu_formatter:feedsToMenuItems(result.feeds, {
        feed_counters = result.counters
    })

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#result.feeds, hide_read, false, "feeds")

    self:updateContent(_("Feeds"), menu_items, params, subtitle)
end

---Show categories list
---@param params? ShowContentParams Optional parameters
function MinifluxBrowser:showCategories(params)
    params = params or {}

    -- Show loading message
    local loading_info = UIComponents.showLoadingMessage(_("Fetching categories..."))

    -- Direct repository call
    local categories, error_msg = self.category_repository:getAll()
    UIComponents.closeLoadingMessage(loading_info)

    if not categories then
        UIComponents.showErrorMessage(_("Failed to fetch categories: ") .. tostring(error_msg))
        return
    end

    -- Direct menu generation
    local menu_items = self.menu_formatter:categoriesToMenuItems(categories)
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#categories, hide_read, false, "categories")

    self:updateContent(_("Categories"), menu_items, params, subtitle)
end

---Show unread entries from all feeds
---@param params? ShowContentParams Optional parameters
function MinifluxBrowser:showUnreadEntries(params)
    params = params or {}

    -- Show loading message
    local loading_info = UIComponents.showLoadingMessage(_("Fetching unread entries..."))

    -- Direct repository call
    local entries, error_msg = self.entry_repository:getUnread()
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch unread entries: ") .. tostring(error_msg))
        return
    end

    -- Direct menu generation
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = true })
    local subtitle = self:buildSubtitle(#entries, false, true) -- unread only

    self:updateContent(_("Unread Entries"), menu_items, params, subtitle)
end

---Show entries for a specific feed
---@param params ShowContentParams Required: feed_id
function MinifluxBrowser:showFeedEntries(params)
    if not params.feed_id then
        UIComponents.showErrorMessage(_("Missing feed information"))
        return
    end

    -- Show loading message
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feed entries..."))

    -- Direct repository call
    local entries, error_msg = self.entry_repository:getByFeed(params.feed_id)
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch feed entries: ") .. tostring(error_msg))
        return
    end

    -- Direct menu generation
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = false })
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    -- Use feed title from first entry if available, otherwise fallback
    local feed_title = _("Feed Entries")
    if #entries > 0 and entries[1].feed and entries[1].feed.title then
        feed_title = entries[1].feed.title
    end

    self:updateContent(feed_title, menu_items, params, subtitle)
end

---Show entries for a specific category
---@param params ShowContentParams Required: category_id
function MinifluxBrowser:showCategoryEntries(params)
    if not params.category_id then
        UIComponents.showErrorMessage(_("Missing category information"))
        return
    end

    -- Show loading message
    local loading_info = UIComponents.showLoadingMessage(_("Fetching category entries..."))

    -- Direct repository call
    local entries, error_msg = self.entry_repository:getByCategory(params.category_id)
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch category entries: ") .. tostring(error_msg))
        return
    end

    -- Direct menu generation
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = true })
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    -- Use category title from first entry if available, otherwise fallback
    local category_title = _("Category Entries")
    if #entries > 0 and entries[1].feed and entries[1].feed.category and entries[1].feed.category.title then
        category_title = entries[1].feed.category.title
    end

    self:updateContent(category_title, menu_items, params, subtitle)
end

-- =============================================================================
-- MENU HANDLING
-- =============================================================================

function MinifluxBrowser:onMenuSelect(item)
    if not item or not item.action_type then
        return
    end

    if item.action_type == "unread" then
        self:showUnreadEntries()
    elseif item.action_type == "feeds" then
        self:showFeeds()
    elseif item.action_type == "categories" then
        self:showCategories()
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id then
            self:showFeedEntries({
                feed_id = feed_data.id
            })
        end
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id then
            self:showCategoryEntries({
                category_id = category_data.id
            })
        end
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data then
            self:openEntry(entry_data)
        end
    end
end

function MinifluxBrowser:openEntry(entry_data)
    -- Set navigation context directly using NavigationContext
    if self.current_view_type == "feed_entries" and self.current_view_params.feed_id then
        NavigationContext.setFeedContext(self.current_view_params.feed_id, entry_data.id)
    elseif self.current_view_type == "category_entries" and self.current_view_params.category_id then
        NavigationContext.setCategoryContext(self.current_view_params.category_id, entry_data.id)
    else
        -- For unread_entries or any other context, use global
        NavigationContext.setGlobalContext(entry_data.id)
    end

    -- Show the entry using EntryService instance
    self.entry_service:showEntry({
        entry = entry_data,
        api = self.api,
        download_dir = self.download_dir,
        browser = self,
    })
end

-- =============================================================================
-- NAVIGATION METHODS
-- =============================================================================

---Navigate back in history
---@return boolean success True if navigation was successful
function MinifluxBrowser:goBack()
    local restore_params = self.history:goBack()
    if not restore_params then
        return false
    end

    -- Direct method calls based on type with error handling
    local success = pcall(function()
        if restore_params.type == "main" then
            self:showMainContent({ paths_updated = true })
        elseif restore_params.type == "feeds" then
            self:showFeeds({ paths_updated = true, page_info = restore_params.page_info })
        elseif restore_params.type == "categories" then
            self:showCategories({ paths_updated = true, page_info = restore_params.page_info })
        elseif restore_params.type == "feed_entries" then
            self:showFeedEntries({
                feed_id = restore_params.feed_id,
                paths_updated = true
            })
        elseif restore_params.type == "category_entries" then
            self:showCategoryEntries({
                category_id = restore_params.category_id,
                paths_updated = true
            })
        elseif restore_params.type == "unread_entries" then
            self:showUnreadEntries({ paths_updated = true })
        else
            self:showMainContent({ paths_updated = true })
        end
    end)

    if not success then
        UIComponents.showErrorMessage(_("Navigation failed"))
        self:showMainContent({ paths_updated = true })
        return false
    end

    self:updateBackButton()
    return true
end

---Push current state to history for back navigation
---@param params HistoryParams Parameters to save for restoration
function MinifluxBrowser:pushToHistory(params)
    if not params or not params.type then
        return
    end

    self.history:push(params)
    self:updateBackButton()
end

---Clear all navigation history
function MinifluxBrowser:clearHistory()
    self.history:clear()
    self:updateBackButton()
end

---Check if back navigation is possible
---@return boolean can_go_back True if there's history to go back to
function MinifluxBrowser:canGoBack()
    return self.history:canGoBack()
end

-- =============================================================================
-- INTERNAL METHODS
-- =============================================================================

---Update browser content and handle history
---@param title string Browser title
---@param menu_items table[] Menu items to display
---@param params ShowContentParams Parameters for history and page restoration
---@param subtitle? string Optional subtitle
function MinifluxBrowser:updateContent(title, menu_items, params, subtitle)
    params = params or {}

    -- Determine view type from title and params
    local view_type = "main"
    if title == _("Feeds") then
        view_type = "feeds"
    elseif title == _("Categories") then
        view_type = "categories"
    elseif title == _("Unread Entries") then
        view_type = "unread_entries"
    elseif params.feed_id then
        view_type = "feed_entries"
    elseif params.category_id then
        view_type = "category_entries"
    end

    -- Update current view tracking
    self.current_view_type = view_type
    self.current_view_params = params

    -- Handle navigation history
    if not params.paths_updated then
        -- Determine previous view type for history
        local previous_type = "main"
        if view_type == "feed_entries" then
            previous_type = "feeds"
        elseif view_type == "category_entries" then
            previous_type = "categories"
        end

        if view_type ~= "main" then
            self:pushToHistory({
                type = previous_type,
                page_info = params.page_info or {
                    page = self.page or 1,
                    perpage = self.perpage or 20,
                },
            })
        end
    end

    -- Handle page restoration for back navigation
    local select_number = 1
    if params.page_info then
        local target_page = params.page_info.page
        if target_page and target_page >= 1 then
            local perpage = self.perpage or 20
            select_number = (target_page - 1) * perpage + 1
            if select_number > #menu_items then
                select_number = #menu_items > 0 and #menu_items or 1
            end
        end
    end

    -- Update browser content
    self.title = title
    self.subtitle = subtitle or ""
    self:switchItemTable(title, menu_items, select_number, nil, subtitle)
end

---Update back button state based on navigation stack
function MinifluxBrowser:updateBackButton()
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

---Refresh current view (after settings changes)
function MinifluxBrowser:refreshCurrentView()
    local view_type = self.current_view_type
    local params = self.current_view_params or {}
    params.paths_updated = true -- Don't add to history

    if view_type == "main" then
        self:showMainContent(params)
    elseif view_type == "feeds" then
        self:showFeeds(params)
    elseif view_type == "categories" then
        self:showCategories(params)
    elseif view_type == "feed_entries" then
        self:showFeedEntries(params)
    elseif view_type == "category_entries" then
        self:showCategoryEntries(params)
    elseif view_type == "unread_entries" then
        self:showUnreadEntries(params)
    else
        self:showMainContent(params)
    end
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function MinifluxBrowser:showConfigDialog()
    if not self.settings then
        UIComponents.showErrorMessage(_("Settings not available"))
        return
    end

    local is_entry_view = (self.current_view_type == "feed_entries" or
        self.current_view_type == "category_entries")
    local is_unread_view = self.current_view_type == "unread_entries"

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
    self:refreshCurrentView()
end

-- =============================================================================
-- INITIALIZATION AND DATA FETCHING
-- =============================================================================

---Show the main Miniflux browser screen with initial data
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
    UIManager:forceRePaint()

    -- Fetch initial data for browser
    local success, error_msg = self:fetchInitialData(loading_info)
    if not success then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new({
            text = _("Failed to load Miniflux: ") .. tostring(error_msg),
            timeout = 5,
        }))
        return
    end

    -- Close loading message and show main content
    UIManager:close(loading_info)
    self:showMainContent()

    -- Actually show the browser
    UIManager:show(self)
end

---Fetch initial data needed for browser initialization
---@param loading_info InfoMessage Loading message to update
---@return boolean success, string? error_msg
function MinifluxBrowser:fetchInitialData(loading_info)
    -- Get unread count
    local unread_count, error_msg = self.entry_repository:getUnreadCount()
    if not unread_count then
        return false, error_msg
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

    -- Close the final loading message
    UIManager:close(loading_info)

    -- Store counts
    self.unread_count = unread_count
    self.feeds_count = feeds_count
    self.categories_count = categories_count

    return true
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

---Build subtitle for content views
---@param count number Number of items
---@param hide_read boolean Whether read entries are hidden
---@param is_unread_only boolean Whether this is unread-only view
---@param item_type? string Type of items ("feeds", "categories", "entries")
---@return string subtitle Formatted subtitle
function MinifluxBrowser:buildSubtitle(count, hide_read, is_unread_only, item_type)
    if is_unread_only then
        return "⊘ " .. count .. " " .. _("unread entries")
    end

    local icon = hide_read and "⊘ " or "◯ "

    if item_type == "entries" then
        if hide_read then
            return icon .. count .. " " .. _("unread entries")
        else
            return icon .. count .. " " .. _("entries")
        end
    elseif item_type == "feeds" then
        return icon .. count .. " " .. _("feeds")
    elseif item_type == "categories" then
        return icon .. count .. " " .. _("categories")
    else
        return icon .. count .. " " .. _("items")
    end
end

function MinifluxBrowser:closeAll()
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
end

return MinifluxBrowser
