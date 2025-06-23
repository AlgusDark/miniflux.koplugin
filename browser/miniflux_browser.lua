--[[--
Miniflux Browser - Miniflux-specific Browser Implementation

Extends the generic Browser to provide Miniflux RSS reader functionality
including feeds, categories, and entry management.

@module miniflux.browser.miniflux_browser
--]]

local Browser = require("browser/browser")
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
local _ = require("gettext")

---@class MinifluxBrowser : Browser
---@field unread_count number|nil Number of unread entries (stored from initialization)
---@field feeds_count number|nil Number of feeds (stored from initialization)
---@field categories_count number|nil Number of categories (stored from initialization)
---@field entry_service EntryService Service handling entry display and dialog management
---@field entry_repository EntryRepository Repository for entry data access
---@field feed_repository FeedRepository Repository for feed data access
---@field category_repository CategoryRepository Repository for category data access
---@field menu_formatter MenuFormatter Formatter for menu items
---@field settings table Plugin settings
---@field api table API client
---@field download_dir string Download directory path
---@field new fun(self: MinifluxBrowser, o: table): MinifluxBrowser Override Browser:new to return correct type
local MinifluxBrowser = Browser:extend({})

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

    -- Set up settings button
    self.onLeftButtonTap = function()
        self:showConfigDialog()
    end

    -- Initialize parent Browser
    Browser.init(self)
end

-- =============================================================================
-- ABSTRACT METHOD IMPLEMENTATIONS
-- =============================================================================

---Get the initial location for the browser
---@return string location Initial location identifier
function MinifluxBrowser:getInitialLocation()
    return "main"
end

---Navigate to a specific location
---@param location string Target location identifier
---@param params? table Navigation parameters
function MinifluxBrowser:navigate(location, params)
    params = params or {}

    if location == "main" then
        self:showMainContent(params)
    elseif location == "feeds" then
        self:showFeeds(params)
    elseif location == "categories" then
        self:showCategories(params)
    elseif location == "unread_entries" then
        self:showUnreadEntries(params)
    elseif location == "feed_entries" then
        self:showFeedEntries(params)
    elseif location == "category_entries" then
        self:showCategoryEntries(params)
    else
        -- Fallback to main
        self:showMainContent(params)
    end
end

---Determine if this navigation should be added to history
---@param location string Target location
---@param params table Navigation parameters
---@return boolean should_add_to_history
function MinifluxBrowser:shouldAddToHistory(location, params)
    -- Don't add to history if explicitly marked as paths_updated
    if params and params.paths_updated then
        return false
    end

    -- Don't add main screen to history when navigating TO main (since it's the root)
    if location == "main" then
        return false
    end

    -- Add all other locations to history (including when navigating FROM main)
    return true
end

---Create history state for current location
---@return HistoryState|nil state State to save, or nil if shouldn't save
function MinifluxBrowser:createHistoryState()
    if not self.current_location then
        return nil
    end

    -- Always save current location state (including main) when navigating away from it
    return {
        location = self.current_location,
        params = {
            feed_id = self.current_params and self.current_params.feed_id,
            category_id = self.current_params and self.current_params.category_id,
        },
        page_info = {
            page = self.page or 1,
            perpage = self.perpage or 20,
        }
    }
end

---Show settings dialog
function MinifluxBrowser:showSettingsDialog()
    self:showConfigDialog()
end

-- =============================================================================
-- CONTENT DISPLAY METHODS
-- =============================================================================

---Show main Miniflux screen with counts
---@param params? table Optional parameters
function MinifluxBrowser:showMainContent(params)
    params = params or {}

    -- Use stored counts from initialization
    local hide_read = self.settings and self.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    local main_items = {
        {
            text = _("Unread"),
            mandatory = tostring(self.unread_count or 0),
            onSelect = function(browser, item)
                browser:navigate("unread_entries")
            end
        },
        {
            text = _("Feeds"),
            mandatory = tostring(self.feeds_count or 0),
            onSelect = function(browser, item)
                browser:navigate("feeds")
            end
        },
        {
            text = _("Categories"),
            mandatory = tostring(self.categories_count or 0),
            onSelect = function(browser, item)
                browser:navigate("categories")
            end
        },
    }

    self:updateContent({
        title = _("Miniflux"),
        items = main_items,
        params = params,
        subtitle = subtitle
    }, "main")
end

---Show feeds list with counters
---@param params? table Optional parameters
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

    -- Direct menu generation with onSelect functions
    local menu_items = self.menu_formatter:feedsToMenuItems(result.feeds, {
        feed_counters = result.counters
    })

    -- Add onSelect functions to feed items
    for _, item in ipairs(menu_items) do
        if item.feed_data then
            item.onSelect = function(browser, item_data)
                browser:navigate("feed_entries", { feed_id = item_data.feed_data.id })
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#result.feeds, hide_read, false, "feeds")

    self:updateContent({
        title = _("Feeds"),
        items = menu_items,
        params = params,
        subtitle = subtitle
    }, "feeds")
end

---Show categories list
---@param params? table Optional parameters
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

    -- Direct menu generation with onSelect functions
    local menu_items = self.menu_formatter:categoriesToMenuItems(categories)

    -- Add onSelect functions to category items
    for _, item in ipairs(menu_items) do
        if item.category_data then
            item.onSelect = function(browser, item_data)
                browser:navigate("category_entries", { category_id = item_data.category_data.id })
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#categories, hide_read, false, "categories")

    self:updateContent({
        title = _("Categories"),
        items = menu_items,
        params = params,
        subtitle = subtitle
    }, "categories")
end

---Show unread entries from all feeds
---@param params? table Optional parameters
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

    -- Direct menu generation with onSelect functions
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = true })

    -- Add onSelect functions to entry items
    for _, item in ipairs(menu_items) do
        if item.entry_data then
            item.onSelect = function(browser, item_data)
                browser:openEntry(item_data.entry_data)
            end
        end
    end

    local subtitle = self:buildSubtitle(#entries, false, true) -- unread only

    self:updateContent({
        title = _("Unread Entries"),
        items = menu_items,
        params = params,
        subtitle = subtitle
    }, "unread_entries")
end

---Show entries for a specific feed
---@param params table Required: feed_id
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

    -- Direct menu generation with onSelect functions
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = false })

    -- Add onSelect functions to entry items
    for _, item in ipairs(menu_items) do
        if item.entry_data then
            item.onSelect = function(browser, item_data)
                browser:openEntry(item_data.entry_data)
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    -- Use feed title from first entry if available, otherwise fallback
    local feed_title = _("Feed Entries")
    if #entries > 0 and entries[1].feed and entries[1].feed.title then
        feed_title = entries[1].feed.title
    end

    self:updateContent({
        title = feed_title,
        items = menu_items,
        params = params,
        subtitle = subtitle
    }, "feed_entries")
end

---Show entries for a specific category
---@param params table Required: category_id
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

    -- Direct menu generation with onSelect functions
    local menu_items = self.menu_formatter:entriesToMenuItems(entries, { show_feed_names = true })

    -- Add onSelect functions to entry items
    for _, item in ipairs(menu_items) do
        if item.entry_data then
            item.onSelect = function(browser, item_data)
                browser:openEntry(item_data.entry_data)
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    -- Use category title from first entry if available, otherwise fallback
    local category_title = _("Category Entries")
    if #entries > 0 and entries[1].feed and entries[1].feed.category and entries[1].feed.category.title then
        category_title = entries[1].feed.category.title
    end

    self:updateContent({
        title = category_title,
        items = menu_items,
        params = params,
        subtitle = subtitle
    }, "category_entries")
end

-- =============================================================================
-- ENTRY HANDLING
-- =============================================================================

function MinifluxBrowser:openEntry(entry_data)
    -- Set navigation context directly using NavigationContext
    if self.current_location == "feed_entries" and self.current_params.feed_id then
        NavigationContext.setFeedContext(self.current_params.feed_id, entry_data.id)
    elseif self.current_location == "category_entries" and self.current_params.category_id then
        NavigationContext.setCategoryContext(self.current_params.category_id, entry_data.id)
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
-- BACKWARD COMPATIBILITY - LEGACY ITEM HANDLING
-- =============================================================================

---Handle item actions for backward compatibility
---@param item table Menu item
function MinifluxBrowser:handleItemAction(item)
    if not item or not item.action_type then
        return
    end

    if item.action_type == "unread" then
        self:navigate("unread_entries")
    elseif item.action_type == "feeds" then
        self:navigate("feeds")
    elseif item.action_type == "categories" then
        self:navigate("categories")
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id then
            self:navigate("feed_entries", { feed_id = feed_data.id })
        end
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id then
            self:navigate("category_entries", { category_id = category_data.id })
        end
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data then
            self:openEntry(entry_data)
        end
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

    local is_entry_view = (self.current_location == "feed_entries" or
        self.current_location == "category_entries")
    local is_unread_view = self.current_location == "unread_entries"

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
    self:navigate("main")

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

return MinifluxBrowser
