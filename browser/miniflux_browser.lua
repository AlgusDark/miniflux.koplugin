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
---@field feed_service FeedService Feed service instance
---@field category_service CategoryService Category service instance
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
    self.feed_service = self.feed_service or error("feed_service required")
    self.category_service = self.category_service or error("category_service required")

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

    -- Check if we're in a view that doesn't need filtering (unread or local entries)
    local current_path = self.paths and #self.paths > 0 and self.paths[#self.paths]
    local is_unread_view = current_path and current_path.to == "unread_entries"
    local is_local_view = current_path and current_path.to == "local_entries"
    local should_hide_filter = is_unread_view or is_local_view

    local buttons = {}

    if not should_hide_filter then
        -- Only show status toggle for non-unread views
        local hide_read_entries = self.settings.hide_read_entries
        local toggle_text = hide_read_entries and _("Show all entries") or _("Show unread entries")

        table.insert(buttons, {
            {
                text = toggle_text,
                callback = function()
                    UIManager:close(self.config_dialog)
                    self:toggleHideReadEntries()
                end,
            },
        })
    end

    -- Always show close button
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

---Toggle the hide_read_entries setting and refresh the current view
function MinifluxBrowser:toggleHideReadEntries()
    -- Toggle the setting
    self.settings.hide_read_entries = not self.settings.hide_read_entries

    -- Save the setting to disk
    self.settings:save()

    -- Show notification about the change
    local Notification = require("utils/notification")
    local status_text = self.settings.hide_read_entries and _("Now showing unread entries only") or
    _("Now showing all entries")
    Notification:info(status_text)

    -- Refresh the current view to apply the new filter
    -- This will trigger a data re-fetch with the new setting
    self:refreshCurrentViewData()
end

---Refresh current view data to apply setting changes
function MinifluxBrowser:refreshCurrentViewData()
    -- Get current view info without manipulating navigation stack
    local current_path = self.paths and self.paths[#self.paths]
    if current_path then
        -- Get view handlers and refresh data directly
        local nav_config = {
            view_name = current_path.to,
            page_state = self:getCurrentItemNumber(),
        }
        if current_path.context then
            nav_config.context = current_path.context
        end
        
        local view_handlers = self:getRouteHandlers(nav_config)
        local handler = view_handlers[current_path.to]
        if handler then
            -- Get fresh view data
            local view_data = handler()
            if view_data then
                -- Update view data without changing navigation
                self.view_data = view_data
                
                -- Re-render with fresh data
                self:switchItemTable(
                    view_data.title,
                    view_data.items,
                    view_data.page_state,
                    view_data.menu_title,
                    view_data.subtitle
                )
            end
        end
    end
end

---Open an entry with optional navigation context (implements Browser:openItem)
---@param entry_data table Entry data from API
---@param context? {type: "feed"|"category", id: number} Navigation context (nil = global)
function MinifluxBrowser:openItem(entry_data, context)
    -- Set browser context before opening entry (preserve all context fields)
    self.miniflux_plugin:setBrowserContext(context or { type = "global" })

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
                onSelectLocal = function()
                    self:goForward({ from = "main", to = "local_entries" })
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
            local UnreadEntriesView = require("browser/views/unread_entries_view")
            return UnreadEntriesView.show({
                repositories = self.repositories,
                settings = self.settings,
                page_state = nav_config.page_state,
                onSelectItem = function(entry_data)
                    self:openItem(entry_data, nil) -- No context for global unread
                end
            })
        end,
        local_entries = function()
            local LocalEntriesView = require("browser/views/local_entries_view")
            local EntryEntity = require("entities/entry_entity")
            
            -- Get lightweight navigation entries (5x less memory than full metadata)
            local nav_entries = EntryEntity.getLocalEntriesForNavigation({settings = self.settings})
            
            return LocalEntriesView.show({
                settings = self.settings,
                page_state = nav_config.page_state,
                onSelectItem = function(entry_data)
                    -- Create local navigation context with pre-sorted entries
                    local local_context = {
                        type = "local",
                        ordered_entries = nav_entries
                    }
                    self:openItem(entry_data, local_context)
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
    -- Check what type of items are selected to determine available actions
    local selected_items = self:getSelectedItems()
    if #selected_items == 0 then
        return {}
    end

    -- Check if selected items are entries (only entries can be marked as unread)
    local item_type = self:getItemType(selected_items[1])
    local actions = {}

    if item_type == "entry" then
        -- Check if we're in local entries view (entries already downloaded)
        local current_path = self.paths and #self.paths > 0 and self.paths[#self.paths]
        local is_local_view = current_path and current_path.to == "local_entries"
        
        -- For entries: show download (unless in local view), mark as unread, and mark as read actions
        if not is_local_view then
            table.insert(actions, {
                text = _("Download Selected"),
                callback = function(selected_items)
                    self:downloadSelectedEntries(selected_items)
                end,
            })
        end
        table.insert(actions, {
            text = _("Mark as Unread"),
            callback = function(selected_items)
                self:markSelectedAsUnread(selected_items)
            end,
        })
        table.insert(actions, {
            text = _("Mark as Read"),
            callback = function(selected_items)
                self:markSelectedAsRead(selected_items)
            end,
        })
    else
        -- For feeds and categories: only show "Mark as read"
        table.insert(actions, {
            text = _("Mark as Read"),
            callback = function(selected_items)
                self:markSelectedAsRead(selected_items)
            end,
        })
    end

    return actions
end

-- =============================================================================
-- SELECTION ACTIONS IMPLEMENTATION
-- =============================================================================

---Mark selected items as read with immediate visual feedback
---@param selected_items table Array of selected item objects
function MinifluxBrowser:markSelectedAsRead(selected_items)
    if #selected_items == 0 then
        return
    end

    -- Determine item type from first item (all items same type in a view)
    local item_type = self:getItemType(selected_items[1])
    if not item_type then
        return
    end

    local success = false

    if item_type == "entry" then
        -- Extract entry IDs and use existing EntryService
        local entry_ids = {}
        for _, item in ipairs(selected_items) do
            table.insert(entry_ids, item.entry_data.id)
        end
        success = self.entry_service:markEntriesAsRead(entry_ids)
    elseif item_type == "feed" then
        -- TODO: Implement batch notifications - show loading, track success/failed feeds, show summary
        success = false
        for _, item in ipairs(selected_items) do
            local feed_id = item.feed_data.id
            local result = self.feed_service:markAsRead(feed_id)
            if result then
                success = true -- At least one succeeded, keep as true even if others fail
            end
        end
    elseif item_type == "category" then
        -- TODO: Implement batch notifications - show loading, track success/failed categories, show summary
        success = false
        for _, item in ipairs(selected_items) do
            local category_id = item.category_data.id
            local result = self.category_service:markAsRead(category_id)
            if result then
                success = true -- At least one succeeded, keep as true even if others fail
            end
        end
    end

    if success then
        -- Update status in current item_table for immediate visual feedback
        self:updateItemTableStatus(selected_items, "read", item_type)
        
        -- For feed/category operations, refresh data to show updated counts
        if item_type == "feed" or item_type == "category" then
            self:refreshCurrentViewData()
        end
    end

    -- Clear selection and exit selection mode
    self:transitionTo(BrowserMode.NORMAL)

    -- Refresh visual state to show updated read/unread indicators
    self:refreshCurrentView()
end

---Mark selected entries as unread with immediate visual feedback
---@param selected_items table Array of selected item objects
function MinifluxBrowser:markSelectedAsUnread(selected_items)
    if #selected_items == 0 then
        return
    end

    -- Only entries can be marked as unread
    local item_type = self:getItemType(selected_items[1])
    if item_type ~= "entry" then
        return
    end

    -- Extract entry IDs
    local entry_ids = {}
    for _, item in ipairs(selected_items) do
        table.insert(entry_ids, item.entry_data.id)
    end

    -- Use EntryService for batch processing
    local success = self.entry_service:markEntriesAsUnread(entry_ids)

    if success then
        -- Update status in current item_table for immediate visual feedback
        self:updateItemTableStatus(selected_items, "unread", item_type)
    end

    -- Clear selection and exit selection mode
    self:transitionTo(BrowserMode.NORMAL)

    -- Refresh visual state to show updated read/unread indicators
    self:refreshCurrentView()
end

---Download selected entries without opening them
---@param selected_items table Array of selected entry items
function MinifluxBrowser:downloadSelectedEntries(selected_items)
    if #selected_items == 0 then
        return
    end
    
    -- Extract entry data from selected items
    local entry_data_list = {}
    for _, item in ipairs(selected_items) do
        table.insert(entry_data_list, item.entry_data)
    end
    
    -- Call batch download service with completion callback
    self.entry_service:downloadEntries(entry_data_list, function(status)
        -- Refresh view data to rebuild menu items with updated download status indicators
        self:refreshCurrentViewData()
        
        -- Only transition to normal mode if download completed successfully
        -- Keep selection mode for cancelled downloads so user can modify and retry
        if status == "completed" then
            self:transitionTo(BrowserMode.NORMAL)
        end
        -- For "cancelled" status, stay in selection mode to preserve user's selection
    end)
    
    -- Don't transition immediately - wait for completion callback
end

---Get configuration for rebuilding entry items
---@return table Configuration for EntriesView.buildSingleItem
function MinifluxBrowser:getEntryItemConfig()
    -- Determine if we should show feed names based on current view
    local show_feed_names = false
    local current_path = self.paths and self.paths[#self.paths]
    if current_path then
        show_feed_names = (current_path.to == "unread_entries" or current_path.to == "category_entries")
    end

    return {
        show_feed_names = show_feed_names,
        onSelectItem = function(entry_data)
            self:openItem(entry_data)
        end
    }
end

---Update item status in current item_table for immediate visual feedback
---@param selected_items table Array of selected item objects
---@param new_status string New status ("read" or "unread")
---@param item_type string Type of items ("entry", "feed", "category")
function MinifluxBrowser:updateItemTableStatus(selected_items, new_status, item_type)
    if not self.item_table then
        return
    end

    if item_type == "entry" then
        local EntriesView = require("browser/views/entries_view")
        local item_config = self:getEntryItemConfig()

        -- Create lookup table for faster searching
        local ids_to_update = {}
        for _, item in ipairs(selected_items) do
            ids_to_update[item.entry_data.id] = true
        end

        -- Selective updates - only rebuild changed items (O(k) where k = selected items)
        for _, item in ipairs(self.item_table) do
            if item.entry_data and item.entry_data.id and ids_to_update[item.entry_data.id] then
                -- Update underlying data
                item.entry_data.status = new_status

                -- Rebuild this item using view logic
                local updated_item = EntriesView.buildSingleItem(item.entry_data, item_config)

                -- Replace item properties with updated display
                item.text = updated_item.text
                -- Keep other properties unchanged (callback, action_type, etc.)
            end
        end
    elseif item_type == "feed" then
        -- Update feed unread count to 0 for visual feedback
        for _, item in ipairs(self.item_table) do
            if item.feed_data and item.feed_data.id == selected_items[1].feed_data.id then
                item.feed_data.unread_count = 0
                -- Update display text if it includes count
                if item.mandatory and item.mandatory:match("%(") then
                    item.mandatory = item.mandatory:gsub("%(%d+%)", "(0)")
                end
            end
        end
    elseif item_type == "category" then
        -- Update category unread count to 0 for visual feedback
        for _, item in ipairs(self.item_table) do
            if item.category_data and item.category_data.id == selected_items[1].category_data.id then
                item.category_data.unread_count = 0
                -- Update display text if it includes count
                if item.mandatory and item.mandatory:match("%(") then
                    item.mandatory = item.mandatory:gsub("%(%d+%)", "(0)")
                end
            end
        end
    end
end

return MinifluxBrowser
