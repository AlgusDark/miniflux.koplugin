--[[--
Miniflux Browser - Simplified Menu-based RSS Browser

Directly extends KOReader's Menu widget to provide Miniflux RSS reader functionality.
Replaces the over-engineered Browser abstraction with direct Menu usage.

@module miniflux.browser.miniflux_browser
--]]

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local EntryRepository = require("repositories/entry_repository")
local FeedRepository = require("repositories/feed_repository")
local CategoryRepository = require("repositories/category_repository")
local EntryService = require("services/entry_service")
local NavigationContext = require("utils/navigation_context")
local _ = require("gettext")

-- Timeout constants for consistent UI messaging
local TIMEOUTS = {
    ERROR = 5, -- Error messages
}

---@class MinifluxBrowser : Menu
---@field unread_count number|nil Number of unread entries (stored from initialization)
---@field feeds_count number|nil Number of feeds (stored from initialization)
---@field categories_count number|nil Number of categories (stored from initialization)
---@field entry_service EntryService Service handling entry display and dialog management
---@field entry_repository EntryRepository Repository for entry data access
---@field feed_repository FeedRepository Repository for feed data access
---@field category_repository CategoryRepository Repository for category data access
---@field settings table Plugin settings
---@field api table API client
---@field download_dir string Download directory path
---@field page_state_stack number[] Stack of page states for each navigation level
local MinifluxBrowser = Menu:extend({
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,

    -- Page state stack for navigation restoration
    page_state_stack = {},
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

    -- Initialize other components
    self.entry_service = EntryService:new(self.settings, self.api)

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

---Show the main Miniflux browser screen with initial data
function MinifluxBrowser:showMainScreen()
    -- Show loading message while fetching initial data
    local loading_info = InfoMessage:new({
        text = _("Loading Miniflux data..."),
    })
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    -- Fetch initial data for browser
    local success, error_msg = self:fetchInitialData(loading_info)
    if not success then
        UIManager:show(InfoMessage:new({
            text = _("Failed to load Miniflux: ") .. tostring(error_msg),
            timeout = TIMEOUTS.ERROR,
        }))
        return
    end

    -- Show main content (loading dialog already closed by fetchInitialData)
    self:showMain()

    -- Actually show the browser
    UIManager:show(self)
end

-- =============================================================================
-- NAVIGATION METHODS (SIMPLIFIED)
-- =============================================================================

---Show main Miniflux screen with counts
function MinifluxBrowser:showMain()
    local hide_read = self.settings and self.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    local main_items = {
        {
            text = _("Unread"),
            mandatory = tostring(self.unread_count or 0),
            callback = function()
                self:showUnreadEntries()
            end
        },
        {
            text = _("Feeds"),
            mandatory = tostring(self.feeds_count or 0),
            callback = function()
                self:showFeeds()
            end
        },
        {
            text = _("Categories"),
            mandatory = tostring(self.categories_count or 0),
            callback = function()
                self:showCategories()
            end
        },
    }

    -- Clear navigation stack - we're at the root (BEFORE switchItemTable)
    self.paths = {}
    self.page_state_stack = {} -- Clear page state stack too
    self.onReturn = nil

    -- Use Menu's built-in content switching
    self:switchItemTable(_("Miniflux"), main_items, nil, nil, subtitle)
end

---Show feeds list with counters
function MinifluxBrowser:showFeeds()
    -- Fetch data with API-level dialog management
    local result, error_msg = self.feed_repository:getAllWithCounters({
        dialogs = {
            loading = { text = _("Fetching feeds...") },
            error = { text = _("Failed to fetch feeds"), timeout = TIMEOUTS.ERROR }
        }
    })

    if not result then
        -- Error dialog already shown by API system
        return
    end

    -- Generate menu items
    local menu_items = {}
    local counters = result.counters

    for _, feed in ipairs(result.feeds or {}) do
        local feed_title = feed.title or _("Untitled Feed")
        local feed_id_str = tostring(feed.id or 0)

        -- Get counts
        local read_count = 0
        local unread_count = 0
        if counters then
            read_count = (counters.reads and counters.reads[feed_id_str]) or 0
            unread_count = (counters.unreads and counters.unreads[feed_id_str]) or 0
        end

        -- Format count display
        local count_info = ""
        local total_count = read_count + unread_count
        if total_count > 0 then
            count_info = string.format("(%d/%d)", unread_count, total_count)
        end

        table.insert(menu_items, {
            text = feed_title,
            mandatory = count_info,
            action_type = "feed_entries",
            unread_count = unread_count,
            feed_data = { id = feed.id, title = feed_title, unread_count = unread_count }
        })
    end

    -- Sort: unread items first, then by unread count desc, then alphabetically
    table.sort(menu_items, function(a, b)
        if a.unread_count > 0 and b.unread_count == 0 then return true end
        if a.unread_count == 0 and b.unread_count > 0 then return false end
        if a.unread_count ~= b.unread_count then return a.unread_count > b.unread_count end
        return a.text:lower() < b.text:lower()
    end)

    -- Add callbacks to feed items
    for _, item in ipairs(menu_items) do
        if item.feed_data then
            item.callback = function()
                self:showFeedEntries(item.feed_data.id)
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#result.feeds, hide_read, false, "feeds")

    -- Set up back navigation to main BEFORE calling switchItemTable
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        self:showMain()
    end

    -- Use Menu's built-in navigation with page state restoration
    local restore_to = self:popPageState()
    self:switchItemTable(_("Feeds"), menu_items, restore_to, nil, subtitle)
end

---Show categories list
function MinifluxBrowser:showCategories()
    -- Fetch data with API-level dialog management
    local categories, error_msg = self.category_repository:getAll({
        dialogs = {
            loading = { text = _("Fetching categories...") },
            error = { text = _("Failed to fetch categories"), timeout = TIMEOUTS.ERROR }
        }
    })

    if not categories then
        -- Error dialog already shown by API system
        return
    end

    -- Generate menu items
    local menu_items = {}

    for _, category in ipairs(categories or {}) do
        local category_title = category.title or _("Untitled Category")
        local unread_count = category.total_unread or 0

        table.insert(menu_items, {
            text = category_title,
            mandatory = string.format("(%d)", unread_count),
            action_type = "category_entries",
            unread_count = unread_count,
            category_data = { id = category.id, title = category_title, unread_count = unread_count }
        })
    end

    -- Sort: unread items first, then by unread count desc, then alphabetically
    table.sort(menu_items, function(a, b)
        if a.unread_count > 0 and b.unread_count == 0 then return true end
        if a.unread_count == 0 and b.unread_count > 0 then return false end
        if a.unread_count ~= b.unread_count then return a.unread_count > b.unread_count end
        return a.text:lower() < b.text:lower()
    end)

    -- Add callbacks to category items
    for _, item in ipairs(menu_items) do
        if item.category_data then
            item.callback = function()
                self:showCategoryEntries(item.category_data.id)
            end
        end
    end

    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#categories, hide_read, false, "categories")

    -- Set up back navigation to main BEFORE calling switchItemTable
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        self:showMain()
    end

    -- Use Menu's built-in navigation with page state restoration
    local restore_to = self:popPageState()
    self:switchItemTable(_("Categories"), menu_items, restore_to, nil, subtitle)
end

---Show entries with unified configuration
---@param config {type: "unread"|"feed"|"category", id?: number, title?: string, onItemSelect: function, onBack: function}
function MinifluxBrowser:showEntries(config)
    -- Push page state for feed/category navigation (unread doesn't need it)
    if config.type ~= "unread" then
        self:pushPageState(self:getCurrentItemNumber())
    end

    -- Prepare loading messages
    local loading_messages = {
        unread = _("Fetching unread entries..."),
        feed = _("Fetching feed entries..."),
        category = _("Fetching category entries...")
    }

    -- Create dialog configuration
    local dialog_config = {
        dialogs = {
            loading = { text = loading_messages[config.type] },
            error = { text = _("Failed to fetch entries"), timeout = TIMEOUTS.ERROR }
        }
    }

    -- Fetch data based on type using enhanced repositories
    local entries, error_msg
    if config.type == "unread" then
        entries, error_msg = self.entry_repository:getUnread(dialog_config)
    elseif config.type == "feed" then
        entries, error_msg = self.entry_repository:getByFeed(config.id, dialog_config)
    elseif config.type == "category" then
        entries, error_msg = self.entry_repository:getByCategory(config.id, dialog_config)
    end

    if not entries then
        -- Error dialog already shown by API system
        return
    end

    -- Generate menu items with appropriate configuration
    local show_feed_names = (config.type == "unread" or config.type == "category")
    local menu_items = {}

    if not entries or #entries == 0 then
        local hide_read = self.settings.hide_read_entries
        local message = hide_read and _("There are no unread entries.") or _("There are no entries.")
        menu_items = { { text = message, mandatory = "", action_type = "no_action" } }
    else
        for _, entry in ipairs(entries) do
            local entry_title = entry.title or _("Untitled Entry")
            local status_indicator = entry.status == "read" and "○ " or "● "
            local display_text = status_indicator .. entry_title

            if show_feed_names and entry.feed and entry.feed.title then
                display_text = display_text .. " (" .. entry.feed.title .. ")"
            end

            table.insert(menu_items, {
                text = display_text,
                action_type = "read_entry",
                entry_data = entry
            })
        end
    end

    -- Add callbacks to entry items
    for _, item in ipairs(menu_items) do
        if item.entry_data then
            item.callback = function()
                config.onItemSelect(item.entry_data)
            end
        end
    end

    -- Build subtitle based on type
    local subtitle
    if config.type == "unread" then
        subtitle = self:buildSubtitle(#entries, false, true) -- unread only
    else
        local hide_read = self.settings.hide_read_entries
        subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")
    end

    -- Determine title
    local title = config.title
    if not title then
        if config.type == "unread" then
            title = _("Unread Entries")
        elseif config.type == "feed" then
            title = _("Feed Entries")
            if #entries > 0 and entries[1].feed and entries[1].feed.title then
                title = entries[1].feed.title
            end
        elseif config.type == "category" then
            title = _("Category Entries")
            if #entries > 0 and entries[1].feed and entries[1].feed.category and entries[1].feed.category.title then
                title = entries[1].feed.category.title
            end
        end
    end

    -- Set up back navigation
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        config.onBack()
    end

    -- Use Menu's built-in navigation
    self:switchItemTable(title, menu_items, nil, nil, subtitle)
end

---Show unread entries from all feeds
function MinifluxBrowser:showUnreadEntries()
    self:showEntries({
        type = "unread",
        onItemSelect = function(entry_data)
            self:openEntry(entry_data)
        end,
        onBack = function()
            self:showMain()
        end
    })
end

---Show entries for a specific feed
---@param feed_id number Feed ID
function MinifluxBrowser:showFeedEntries(feed_id)
    self:showEntries({
        type = "feed",
        id = feed_id,
        onItemSelect = function(entry_data)
            self:openEntry(entry_data, { type = "feed", id = feed_id })
        end,
        onBack = function()
            self:showFeeds()
        end
    })
end

---Show entries for a specific category
---@param category_id number Category ID
function MinifluxBrowser:showCategoryEntries(category_id)
    self:showEntries({
        type = "category",
        id = category_id,
        onItemSelect = function(entry_data)
            self:openEntry(entry_data, { type = "category", id = category_id })
        end,
        onBack = function()
            self:showCategories()
        end
    })
end

-- =============================================================================
-- ENTRY HANDLING
-- =============================================================================

---Open an entry with optional navigation context
---@param entry_data table Entry data from API
---@param context? {type: "feed"|"category", id: number} Navigation context (nil = global)
function MinifluxBrowser:openEntry(entry_data, context)
    -- Set navigation context using unified method
    NavigationContext.setContext(entry_data.id, context)

    -- Show the entry using EntryService
    self.entry_service:readEntry(entry_data, self)
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function MinifluxBrowser:showConfigDialog()
    if not self.settings then
        UIManager:show(InfoMessage:new({
            text = _("Settings not available"),
            timeout = TIMEOUTS.ERROR,
        }))
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
        title = _("Miniflux Settings"),
        title_align = "center",
        buttons = buttons,
    })
    UIManager:show(self.config_dialog)
end

-- =============================================================================
-- DATA FETCHING & UTILITIES
-- =============================================================================

---Fetch initial data needed for browser initialization
---@param loading_info InfoMessage Loading message to close
---@return boolean success, string? error_msg
function MinifluxBrowser:fetchInitialData(loading_info)
    -- Close the initial loading message
    UIManager:close(loading_info)

    -- Get unread count with dialog
    local unread_count, error_msg = self.entry_repository:getUnreadCount({
        dialogs = {
            loading = { text = _("Loading unread count...") }
        }
    })
    if not unread_count then
        return false, error_msg
    end

    -- Get feeds count with dialog
    local feeds_count = self.feed_repository:getCount({
        dialogs = {
            loading = { text = _("Loading feeds count...") }
        }
    })

    -- Get categories count with dialog
    local categories_count = self.category_repository:getCount({
        dialogs = {
            loading = { text = _("Loading categories count...") }
        }
    })

    -- Store counts
    self.unread_count = unread_count
    self.feeds_count = feeds_count
    self.categories_count = categories_count

    return true
end

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

---Get current item number for page state restoration
---@return number Current item number (for use with switchItemTable)
function MinifluxBrowser:getCurrentItemNumber()
    -- Safely get properties with fallbacks for uninitialized Menu state
    local page = tonumber(self.page) or 1
    local perpage = tonumber(self.perpage) or 20

    -- For Menu widgets, the current item might be tracked differently
    -- Use itemnumber if available, otherwise fall back to a safe default
    local current_item = tonumber(self.itemnumber) or 1

    -- If we have valid page info, calculate the absolute item number
    if page > 1 then
        local item_number = (page - 1) * perpage + current_item
        return math.max(item_number, 1)
    end

    -- Otherwise, just return the current item or 1
    return math.max(current_item, 1)
end

---Push page state to stack (when navigating away from a paginated list)
---@param page_state number Current page/item position
---@return nil
function MinifluxBrowser:pushPageState(page_state)
    table.insert(self.page_state_stack, page_state)
end

---Pop page state from stack (when returning to a paginated list)
---@return number|nil Page state to restore to, or nil if stack is empty
function MinifluxBrowser:popPageState()
    if #self.page_state_stack > 0 then
        return table.remove(self.page_state_stack)
    end
    return 1
end

---Close the browser (for compatibility with entry service)
function MinifluxBrowser:closeAll()
    UIManager:close(self)
end

return MinifluxBrowser
