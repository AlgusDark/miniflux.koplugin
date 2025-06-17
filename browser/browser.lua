--[[--
Miniflux Browser - Consolidated Implementation

Single-file browser that handles all browsing functionality for Miniflux.
Combines what was previously split across 10+ files into one maintainable module.

@module miniflux.browser.browser
--]]--

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local BrowserData = require("browser/browser_data") 
local EntryHandler = require("browser/entry_handler")
local UIComponents = require("browser/ui_components")
local _ = require("gettext")

---@class MinfluxBrowser : Menu
local MinifluxBrowser = Menu:extend{
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MinifluxBrowser:init()
    -- Required properties from constructor
    self.settings = self.settings or {}
    self.api = self.api or {}
    self.download_dir = self.download_dir
    
    -- Initialize data handler
    self.data = BrowserData:new(self.api, self.settings)
    
    -- Initialize entry handler
    self.entry_handler = EntryHandler:new(self.api, self.settings, self.download_dir)
    
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
        self:showUnreadEntries()
    elseif item.action_type == "feeds" then
        self:showFeeds()
    elseif item.action_type == "categories" then
        self:showCategories()
    elseif item.action_type == "feed_entries" then
        local feed_data = item.feed_data
        if feed_data and feed_data.id and feed_data.title then
            self:showFeedEntries(feed_data.id, feed_data.title)
        end
    elseif item.action_type == "category_entries" then
        local category_data = item.category_data
        if category_data and category_data.id and category_data.title then
            self:showCategoryEntries(category_data.id, category_data.title)
        end
    elseif item.action_type == "read_entry" then
        local entry_data = item.entry_data
        if entry_data then
            self:openEntry(entry_data)
        end
    end
end

-- =============================================================================
-- CONTENT DISPLAY METHODS
-- =============================================================================

function MinifluxBrowser:showUnreadEntries(paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching unread entries..."))
    
    local entries = self.data:getUnreadEntries()
    UIComponents.closeLoadingMessage(loading_info)
    
    if not entries then
        return
    end
    
    local menu_items = self.data:entriesToMenuItems(entries, true) -- show feed names
    local subtitle = self:buildSubtitle(#entries, false, true) -- unread only
    
    self.current_context = { type = "unread_entries" }
    self:updateBrowser(_("Unread Entries"), menu_items, subtitle, self:createNavData(paths_updated, "main"))
end

function MinifluxBrowser:showFeeds(paths_updated, page_info)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feeds..."))
    
    local feeds, counters = self.data:getFeedsWithCounters()
    UIComponents.closeLoadingMessage(loading_info)
    
    if not feeds then
        return
    end
    
    local menu_items = self.data:feedsToMenuItems(feeds, counters)
    local hide_read = self.settings:getHideReadEntries()
    local subtitle = self:buildSubtitle(#feeds, hide_read, false, "feeds")
    
    self.current_context = { type = "feeds" }
    local nav_data = self:createNavData(paths_updated, "main", nil, page_info)
    self:updateBrowser(_("Feeds"), menu_items, subtitle, nav_data)
end

function MinifluxBrowser:showCategories(paths_updated, page_info)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching categories..."))
    
    local categories = self.data:getCategories()
    UIComponents.closeLoadingMessage(loading_info)
    
    if not categories then
        return
    end
    
    local menu_items = self.data:categoriesToMenuItems(categories)
    local hide_read = self.settings:getHideReadEntries()
    local subtitle = self:buildSubtitle(#categories, hide_read, false, "categories")
    
    self.current_context = { type = "categories" }
    local nav_data = self:createNavData(paths_updated, "main", nil, page_info)
    self:updateBrowser(_("Categories"), menu_items, subtitle, nav_data)
end

function MinifluxBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feed entries..."))
    
    local entries = self.data:getFeedEntries(feed_id)
    UIComponents.closeLoadingMessage(loading_info)
    
    if not entries then
        return
    end
    
    local menu_items = self.data:entriesToMenuItems(entries, false) -- don't show feed names
    local hide_read = self.settings:getHideReadEntries()
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")
    
    self.current_context = { 
        type = "feed_entries",
        feed_id = feed_id,
        feed_title = feed_title 
    }
    
    local nav_data = self:createNavData(paths_updated, "feeds", {
        feed_id = feed_id,
        feed_title = feed_title
    })
    
    self:updateBrowser(feed_title, menu_items, subtitle, nav_data)
end

function MinifluxBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching category entries..."))
    
    local entries = self.data:getCategoryEntries(category_id)
    UIComponents.closeLoadingMessage(loading_info)
    
    if not entries then
        return
    end
    
    local menu_items = self.data:entriesToMenuItems(entries, true) -- show feed names
    local hide_read = self.settings:getHideReadEntries()
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")
    
    self.current_context = { 
        type = "category_entries",
        category_id = category_id,
        category_title = category_title 
    }
    
    local nav_data = self:createNavData(paths_updated, "categories", {
        category_id = category_id,
        category_title = category_title
    })
    
    self:updateBrowser(category_title, menu_items, subtitle, nav_data)
end

function MinifluxBrowser:openEntry(entry_data)
    -- Set entry navigation context
    self.entry_handler:setNavigationContext(self.current_context, entry_data.id)
    
    -- Show the entry
    self.entry_handler:showEntry(entry_data, self)
end

function MinifluxBrowser:showMainContent()
    local main_items = self:generateMainMenu()
    local hide_read = self.settings and self.settings:getHideReadEntries()
    local subtitle = hide_read and "⊘ " or "◯ "
    
    self.current_context = { type = "main" }
    self:updateBrowser(_("Miniflux"), main_items, subtitle, {paths_updated = true})
end

-- =============================================================================
-- NAVIGATION MANAGEMENT
-- =============================================================================

function MinifluxBrowser:createNavData(paths_updated, parent_type, current_data, page_info)
    local nav_data = {
        paths_updated = paths_updated or false,
        current_type = parent_type,
        current_data = current_data,
    }
    
    -- Capture current page info for back navigation
    if not paths_updated then
        nav_data.page_info = {
            page = self.page or 1,
            perpage = self.perpage or 20,
        }
        nav_data.current_title = self.title
    end
    
    -- Add page restoration if provided
    if page_info then
        nav_data.restore_page_info = page_info
    end
    
    return nav_data
end

function MinifluxBrowser:updateBrowser(title, items, subtitle, nav_data)
    -- Handle navigation paths
    if nav_data and not nav_data.paths_updated then
        -- Add current location to navigation history
        local current_path = {
            title = nav_data.current_title or self.title,
            type = nav_data.current_type or "main",
            page_info = nav_data.page_info,
            nav_data = nav_data.current_data
        }
        table.insert(self.navigation_paths, current_path)
    end
    
    -- Update back navigation
    self:updateBackButton()
    
    -- Handle page restoration for back navigation
    local select_number = 1
    if nav_data and nav_data.restore_page_info then
        local target_page = nav_data.restore_page_info.page
        if target_page and target_page >= 1 then
            local perpage = self.perpage or 20
            select_number = (target_page - 1) * perpage + 1
            if select_number > #items then
                select_number = #items > 0 and #items or 1
            end
        end
    end
    
    -- Update browser content
    self.title = title
    self.subtitle = subtitle or ""
    self:switchItemTable(title, items, select_number, nil, subtitle)
end

function MinifluxBrowser:updateBackButton()
    if #self.navigation_paths > 0 then
        self.onReturn = function()
            return self:goBack()
        end
        -- Sync with Menu widget's paths for back button
        if not self.paths then
            self.paths = {}
        end
        while #self.paths < #self.navigation_paths do
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

function MinifluxBrowser:goBack()
    if #self.navigation_paths == 0 then
        return false
    end
    
    local target_path = table.remove(self.navigation_paths)
    
    if target_path.type == "main" then
        self:showMainContent()
    elseif target_path.type == "categories" then
        self:showCategories(true, target_path.page_info)
    elseif target_path.type == "feeds" then
        self:showFeeds(true, target_path.page_info)
    else
        self:showMainContent()
    end
    
    return true
end

-- =============================================================================
-- SETTINGS DIALOG
-- =============================================================================

function MinifluxBrowser:showConfigDialog()
    if not self.settings or not self.settings.getHideReadEntries then
        UIComponents.showErrorMessage(_("Settings not available"))
        return
    end
    
    local is_entry_view = self:isInEntryView()
    local is_unread_view = self.current_context.type == "unread_entries"
    
    local buttons = {}
    
    -- Show toggle only for non-unread entry views
    if is_entry_view and not is_unread_view then
        local hide_read = self.settings:getHideReadEntries()
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
    
    self.config_dialog = ButtonDialogTitle:new{
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
    self:refreshCurrentView()
end

function MinifluxBrowser:isInEntryView()
    if not self.title then
        return false
    end
    
    local main_titles = {
        [_("Miniflux")] = true,
        [_("Feeds")] = true,
        [_("Categories")] = true
    }
    
    return not main_titles[self.title]
end

function MinifluxBrowser:refreshCurrentView()
    local context = self.current_context
    if not context or not context.type then
        self:showMainContent()
        return
    end
    
    if context.type == "main" then
        self:showMainContent()
    elseif context.type == "feeds" then
        self:showFeeds(true)
    elseif context.type == "categories" then
        self:showCategories(true)
    elseif context.type == "feed_entries" then
        self:showFeedEntries(context.feed_id, context.feed_title, true)
    elseif context.type == "category_entries" then
        self:showCategoryEntries(context.category_id, context.category_title, true)
    elseif context.type == "unread_entries" then
        self:showUnreadEntries(true)
    else
        self:showMainContent()
    end
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

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