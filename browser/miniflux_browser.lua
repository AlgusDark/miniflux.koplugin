--[[--
Miniflux Browser - RSS Browser for Miniflux

Extends generic Browser with Miniflux-specific functionality.
Handles RSS feeds, categories, and entries from Miniflux API.

@module miniflux.browser.miniflux_browser
--]]

local Browser = require("browser/browser")
local EntryRepository = require("repositories/entry_repository")
local FeedRepository = require("repositories/feed_repository")
local CategoryRepository = require("repositories/category_repository")

local _ = require("gettext")

-- Import view modules
local MainView = require("browser/views/main_view")
local FeedsView = require("browser/views/feeds_view")
local CategoriesView = require("browser/views/categories_view")
local EntriesView = require("browser/views/entries_view")

---@class MinifluxBrowser : Browser
---@field repositories table Repository instances for data access
---@field new fun(self: MinifluxBrowser, o: BrowserOptions): MinifluxBrowser Create new MinifluxBrowser instance
local MinifluxBrowser = Browser:extend({})

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MinifluxBrowser:init()
    -- Create Miniflux-specific repository instances
    self.repositories = {
        entry = EntryRepository:new(self.api, self.settings),
        feed = FeedRepository:new(self.api, self.settings),
        category = CategoryRepository:new(self.api, self.settings),
    }

    -- Initialize Browser parent (handles generic setup)
    Browser.init(self)
end

-- =============================================================================
-- MINIFLUX-SPECIFIC FUNCTIONALITY
-- =============================================================================

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
---@param nav_config RouteConfig Navigation configuration
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

return MinifluxBrowser
