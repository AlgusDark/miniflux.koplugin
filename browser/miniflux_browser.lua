--[[--
Miniflux Browser - Clean Menu-based RSS Browser

Extends KOReader's Menu widget with modular view system.
Acts as coordinator between views and repositories.

@module miniflux.browser.miniflux_browser
--]]

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local EntryRepository = require("repositories/entry_repository")
local FeedRepository = require("repositories/feed_repository")
local CategoryRepository = require("repositories/category_repository")

local Notification = require("utils/notification")
local _ = require("gettext")

-- Import view modules
local MainView = require("browser/views/main_view")
local FeedsView = require("browser/views/feeds_view")
local CategoriesView = require("browser/views/categories_view")
local EntriesView = require("browser/views/entries_view")
local ViewUtils = require("browser/views/view_utils")

-- No timeout constants needed - handled by Notification utility

---@class MinifluxBrowserOptions : MenuOptions
---@field settings MinifluxSettings Plugin settings
---@field api MinifluxAPI API client
---@field download_dir string Download directory path
---@field entry_service EntryService Service handling entry display and dialog management
---@field miniflux_plugin Miniflux Plugin instance for context management

---@class MinifluxBrowser : Menu
---@field counts table Cached counts from initialization
---@field entry_service EntryService Service handling entry display and dialog management
---@field repositories table Repository instances for data access
---@field settings table Plugin settings
---@field api table API client
---@field download_dir string Download directory path
---@field miniflux_plugin Miniflux Plugin instance for context management
---@field page_state_stack number[] Stack of page states for each navigation level
---@field new fun(self: MinifluxBrowser, o: MinifluxBrowserOptions): MinifluxBrowser Create new MinifluxBrowser instance
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
    self.miniflux_plugin = self.miniflux_plugin or error("miniflux_plugin required")

    -- Require shared EntryService
    self.entry_service = self.entry_service or error("entry_service required")

    -- Create repository instances
    self.repositories = {
        entry = EntryRepository:new(self.api, self.settings),
        feed = FeedRepository:new(self.api, self.settings),
        category = CategoryRepository:new(self.api, self.settings),
    }

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
    local loading_notification = Notification:info({
        text = _("Loading Miniflux data..."),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Close loading dialog and load data
    loading_notification:close()

    local counts, error_msg = MainView.loadData({ repositories = self.repositories })
    if not counts then
        Notification:error(_("Failed to load Miniflux: ") .. tostring(error_msg))
        return
    end

    -- Cache counts for use in views
    self.counts = counts

    -- Show main content
    self:showMain()

    -- Actually show the browser
    UIManager:show(self)
end

-- =============================================================================
-- NAVIGATION METHODS
-- =============================================================================

---Show main Miniflux screen with counts
function MinifluxBrowser:showMain()
    local hide_read = self.settings and self.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    local main_items = MainView.buildItems({
        counts = self.counts,
        callbacks = {
            on_unread = function() self:showUnreadEntries() end,
            on_feeds = function() self:showFeeds() end,
            on_categories = function() self:showCategories() end,
        }
    })

    -- Clear navigation stack - we're at the root
    self.paths = {}
    self.page_state_stack = {}
    self.onReturn = nil

    self:switchItemTable(_("Miniflux"), main_items, nil, nil, subtitle)
end

---Show feeds list with counters
function MinifluxBrowser:showFeeds()
    -- Fetch data with API-level dialog management
    local result, error_msg = self.repositories.feed:getAllWithCounters({
        dialogs = {
            loading = { text = _("Fetching feeds...") },
            error = { text = _("Failed to fetch feeds"), timeout = 5 }
        }
    })

    if not result then
        return -- Error dialog already shown by API system
    end

    -- Generate menu items using view
    local menu_items = FeedsView.buildItems({
        feeds = result.feeds,
        counters = result.counters,
        on_select_callback = function(feed_id)
            self:showFeedEntries(feed_id)
        end
    })

    local hide_read = self.settings.hide_read_entries
    local subtitle = ViewUtils.buildSubtitle({
        count = #result.feeds,
        hide_read = hide_read,
        item_type = "feeds"
    })

    -- Set up navigation
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        self:showMain()
    end

    local restore_to = self:popPageState()
    self:switchItemTable(_("Feeds"), menu_items, restore_to, nil, subtitle)
end

---Show categories list
function MinifluxBrowser:showCategories()
    -- Fetch data with API-level dialog management
    local categories, error_msg = self.repositories.category:getAll({
        dialogs = {
            loading = { text = _("Fetching categories...") },
            error = { text = _("Failed to fetch categories"), timeout = 5 }
        }
    })

    if not categories then
        return -- Error dialog already shown by API system
    end

    -- Generate menu items using view
    local menu_items = CategoriesView.buildItems({
        categories = categories,
        on_select_callback = function(category_id)
            self:showCategoryEntries(category_id)
        end
    })

    local hide_read = self.settings.hide_read_entries
    local subtitle = ViewUtils.buildSubtitle({
        count = #categories,
        hide_read = hide_read,
        item_type = "categories"
    })

    -- Set up navigation
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        self:showMain()
    end

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
            error = { text = _("Failed to fetch entries"), timeout = 5 }
        }
    }

    -- Fetch data based on type
    local entries, error_msg
    if config.type == "unread" then
        entries, error_msg = self.repositories.entry:getUnread(dialog_config)
    elseif config.type == "feed" then
        entries, error_msg = self.repositories.entry:getByFeed(config.id, dialog_config)
    elseif config.type == "category" then
        entries, error_msg = self.repositories.entry:getByCategory(config.id, dialog_config)
    end

    if not entries then
        return -- Error dialog already shown by API system
    end

    -- Generate menu items using view
    local show_feed_names = (config.type == "unread" or config.type == "category")
    local menu_items = EntriesView.buildItems({
        entries = entries,
        show_feed_names = show_feed_names,
        hide_read_entries = self.settings.hide_read_entries,
        on_select_callback = config.onItemSelect
    })

    -- Build subtitle based on type
    local subtitle
    if config.type == "unread" then
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            is_unread_only = true
        })
    else
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            hide_read = self.settings.hide_read_entries,
            item_type = "entries"
        })
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

    -- Set up navigation
    table.insert(self.paths, true)
    self.onReturn = function()
        table.remove(self.paths)
        config.onBack()
    end

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
    -- Set browser context before opening entry
    self.miniflux_plugin:setBrowserContext({
        type = context and context.type or "global"
    })

    self.entry_service:readEntry(entry_data, self)
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function MinifluxBrowser:showConfigDialog()
    if not self.settings then
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
        title = _("Miniflux Settings"),
        title_align = "center",
        buttons = buttons,
    })
    UIManager:show(self.config_dialog)
end

-- =============================================================================
-- PAGE STATE MANAGEMENT
-- =============================================================================

---Get current item number for page state restoration
---@return number Current item number (for use with switchItemTable)
function MinifluxBrowser:getCurrentItemNumber()
    local page = tonumber(self.page) or 1
    local perpage = tonumber(self.perpage) or 20
    local current_item = tonumber(self.itemnumber) or 1

    if page > 1 then
        local item_number = (page - 1) * perpage + current_item
        return math.max(item_number, 1)
    end

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
