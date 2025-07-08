local Browser = require("browser/browser")
local BrowserMode = Browser.BrowserMode
local EntryRepository = require("repositories/entry_repository")
local FeedRepository = require("repositories/feed_repository")
local CategoryRepository = require("repositories/category_repository")

local _ = require("gettext")

-- Import view modules
local MainView = require("browser/views/main_view")
local FeedsView = require("browser/views/feeds_view")
local CategoriesView = require("browser/views/categories_view")
local EntriesView = require("browser/views/entries_view")

-- Type aliases for cleaner annotations
---@alias MinifluxRepositories {entry: EntryRepository, feed: FeedRepository, category: CategoryRepository}

-- **Miniflux Browser** - RSS Browser for Miniflux
--
-- Extends Browser with Miniflux-specific functionality.
-- Handles RSS feeds, categories, and entries from Miniflux API.
---@class MinifluxBrowser : Browser
---@field repositories MinifluxRepositories Repository instances for data access
---@field settings MinifluxSettings Plugin settings
---@field miniflux_api MinifluxAPI Miniflux API
---@field download_dir string Download directory path
---@field entry_service EntryService Entry service instance
---@field miniflux_plugin Miniflux Plugin instance for context management
---@field new fun(self: MinifluxBrowser, o: BrowserOptions): MinifluxBrowser Create new MinifluxBrowser instance
local MinifluxBrowser = Browser:extend({})

---@alias MinifluxNavigationContext {feed_id?: number, category_id?: number}

function MinifluxBrowser:init()
    -- Initialize Miniflux-specific dependencies
    self.settings = self.settings or {}
    self.miniflux_api = self.miniflux_api or {}
    self.download_dir = self.download_dir
    self.miniflux_plugin = self.miniflux_plugin or error("miniflux_plugin required")
    self.entry_service = self.entry_service or error("entry_service required")

    -- Create Miniflux-specific repository instances
    self.repositories = {
        entry = EntryRepository:new({ miniflux_api = self.miniflux_api, settings = self.settings }),
        feed = FeedRepository:new({ miniflux_api = self.miniflux_api, settings = self.settings }),
        category = CategoryRepository:new({ miniflux_api = self.miniflux_api, settings = self.settings }),
    }

    -- Initialize Browser parent (handles generic setup)
    Browser.init(self)
end

-- =============================================================================
-- MINIFLUX-SPECIFIC FUNCTIONALITY
-- =============================================================================

---Override settings dialog with Miniflux-specific implementation
function MinifluxBrowser:onLeftButtonTap()
    if not self.settings then
        local Notification = require("utils/notification")
        Notification:error(_("Settings not available"))
        return
    end

    local UIManager = require("ui/uimanager")
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")

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

---Open an entry with optional navigation context (implements Browser:openItem)
---@param entry_data table Entry data from API
---@param context? {type: "feed"|"category", id: number} Navigation context (nil = global)
function MinifluxBrowser:openItem(entry_data, context)
    -- Set browser context before opening entry
    self.miniflux_plugin:setBrowserContext({
        type = context and context.type or "global"
    })

    self.entry_service:readEntry(entry_data, self)
end

---Get Miniflux-specific route handlers (implements Browser:getRouteHandlers)
---@param nav_config RouteConfig<MinifluxNavigationContext> Navigation configuration
---@return table<string, function> Route handlers lookup table
function MinifluxBrowser:getRouteHandlers(nav_config)
    return {
        main = function()
            return MainView.show({
                repositories = self.repositories,
                settings = self.settings,
                onSelectUnread = function()
                    self:goForward({ from = "main", to = "unread_entries" })
                end,
                onSelectFeeds = function()
                    self:goForward({ from = "main", to = "feeds" })
                end,
                onSelectCategories = function()
                    self:goForward({ from = "main", to = "categories" })
                end,
            })
        end,
        feeds = function()
            return FeedsView.show({
                repositories = self.repositories,
                settings = self.settings,
                page_state = nav_config.page_state,
                onSelectItem = function(feed_id)
                    self:goForward({ from = "feeds", to = "feed_entries", context = { feed_id = feed_id } })
                end
            })
        end,
        categories = function()
            return CategoriesView.show({
                repositories = self.repositories,
                settings = self.settings,
                page_state = nav_config.page_state,
                onSelectItem = function(category_id)
                    self:goForward({ from = "categories", to = "category_entries", context = { category_id = category_id } })
                end
            })
        end,
        feed_entries = function()
            return EntriesView.show({
                repositories = self.repositories,
                settings = self.settings,
                entry_type = "feed",
                id = nav_config.context and nav_config.context.feed_id,
                page_state = nav_config.page_state,
                onSelectItem = function(entry_data)
                    local context = {
                        type = "feed",
                        id = nav_config.context and nav_config.context.feed_id
                    }
                    self:openItem(entry_data, context)
                end
            })
        end,
        category_entries = function()
            return EntriesView.show({
                repositories = self.repositories,
                settings = self.settings,
                entry_type = "category",
                id = nav_config.context and nav_config.context.category_id,
                page_state = nav_config.page_state,
                onSelectItem = function(entry_data)
                    local context = {
                        type = "category",
                        id = nav_config.context and nav_config.context.category_id
                    }
                    self:openItem(entry_data, context)
                end
            })
        end,
        unread_entries = function()
            return EntriesView.show({
                repositories = self.repositories,
                settings = self.settings,
                entry_type = "unread",
                page_state = nav_config.page_state,
                onSelectItem = function(entry_data)
                    self:openItem(entry_data, nil) -- No context for global unread
                end
            })
        end,
    }
end

-- =============================================================================
-- SELECTION MODE IMPLEMENTATION
-- =============================================================================

---Get unique identifier for an item (implements Browser:getItemId)
---@param item_data table Menu item data
---@return number|nil Entry/Feed/Category ID, or nil if item is not selectable
function MinifluxBrowser:getItemId(item_data)
    -- Check for entry data (most common case for selection)
    if item_data.entry_data and item_data.entry_data.id then
        return item_data.entry_data.id
    end

    -- Check for feed data
    if item_data.feed_data and item_data.feed_data.id then
        return item_data.feed_data.id
    end

    -- Check for category data
    if item_data.category_data and item_data.category_data.id then
        return item_data.category_data.id
    end

    -- Navigation items (Unread, Feeds, Categories) or items without data
    -- should not be selectable - return nil
    return nil
end

---Get selection actions available for RSS entries (implements Browser:getSelectionActions)
---@return table[] Array of action objects with text and callback properties
function MinifluxBrowser:getSelectionActions()
    return {
        {
            text = _("Mark as Read"),
            callback = function(selected_items)
                self:markSelectedAsRead(selected_items)
            end,
        },
        -- Future actions can be added here:
        -- {
        --     text = _("Delete Local Files"),
        --     callback = function(selected_items)
        --         self:deleteSelectedLocalFiles(selected_items)
        --     end,
        -- },
    }
end

-- =============================================================================
-- SELECTION ACTIONS IMPLEMENTATION
-- =============================================================================

---Mark selected entries as read (placeholder implementation)
---@param selected_item_ids table Array of selected entry IDs
function MinifluxBrowser:markSelectedAsRead(selected_item_ids)
    -- For now, just show notification with the selected IDs as requested
    local Notification = require("utils/notification")
    local message = _("Mark as Read called with entry IDs: ") .. table.concat(selected_item_ids, ", ")
    Notification:info(message)

    -- Clear selection and exit selection mode
    self:transitionTo(BrowserMode.NORMAL)
end

return MinifluxBrowser
