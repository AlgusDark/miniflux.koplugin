--[[--
View Service - Content Display and State Management

Handles all view-related operations for the Miniflux browser including content display,
view transitions, subtitle building, and browser update orchestration.

@module miniflux.services.view_service
--]]

local UIComponents = require("utils/ui_components")
local _ = require("gettext")

---@class ViewService
---@field browser MinifluxBrowser Reference to the MinifluxBrowser instance
---@field entry_repository EntryRepository Repository for entry data access
---@field feed_repository FeedRepository Repository for feed data access
---@field category_repository CategoryRepository Repository for category data access
---@field menu_formatter MenuFormatter Formatter for menu items
---@field settings table Reference to settings
---@field path_service PathService|nil Reference to PathService (injected after creation)
local ViewService = {}
ViewService.__index = ViewService

function ViewService:new(browser, entry_repository, feed_repository, category_repository, menu_formatter, settings)
    local obj = setmetatable({}, ViewService)
    obj.browser = browser
    obj.entry_repository = entry_repository
    obj.feed_repository = feed_repository
    obj.category_repository = category_repository
    obj.menu_formatter = menu_formatter
    obj.settings = settings
    obj.path_service = nil -- Will be injected after PathService creation
    return obj
end

function ViewService:setPathService(path_service)
    self.path_service = path_service
end

-- =============================================================================
-- CONTENT DISPLAY METHODS
-- =============================================================================

function ViewService:showUnreadEntries(paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching unread entries..."))

    local entries, error_msg = self.entry_repository:getUnread()
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch unread entries: ") .. tostring(error_msg))
        return
    end

    local menu_items = self.menu_formatter:entriesToMenuItems(entries, true) -- show feed names
    local subtitle = self:buildSubtitle(#entries, false, true) -- unread only

    self.browser.current_context = { type = "unread_entries" }
    local nav_data = self.path_service and self.path_service:createNavData(paths_updated, "main") or {}
    self:updateBrowser(_("Unread Entries"), menu_items, subtitle, nav_data)
end

function ViewService:showFeeds(paths_updated, page_info)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feeds..."))

    local feeds, counters, error_msg = self.feed_repository:getAllWithCounters()
    UIComponents.closeLoadingMessage(loading_info)

    if not feeds then
        UIComponents.showErrorMessage(_("Failed to fetch feeds: ") .. tostring(error_msg))
        return
    end

    local menu_items = self.menu_formatter:feedsToMenuItems(feeds, counters)
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#feeds, hide_read, false, "feeds")

    self.browser.current_context = { type = "feeds" }
    local nav_data = self.path_service and self.path_service:createNavData(paths_updated, "main", nil, page_info) or {}
    self:updateBrowser(_("Feeds"), menu_items, subtitle, nav_data)
end

function ViewService:showCategories(paths_updated, page_info)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching categories..."))

    local categories, error_msg = self.category_repository:getAll()
    UIComponents.closeLoadingMessage(loading_info)

    if not categories then
        UIComponents.showErrorMessage(_("Failed to fetch categories: ") .. tostring(error_msg))
        return
    end

    local menu_items = self.menu_formatter:categoriesToMenuItems(categories)
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#categories, hide_read, false, "categories")

    self.browser.current_context = { type = "categories" }
    local nav_data = self.path_service and self.path_service:createNavData(paths_updated, "main", nil, page_info) or {}
    self:updateBrowser(_("Categories"), menu_items, subtitle, nav_data)
end

function ViewService:showFeedEntries(feed_id, feed_title, paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching feed entries..."))

    local entries, error_msg = self.entry_repository:getByFeed(feed_id)
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch feed entries: ") .. tostring(error_msg))
        return
    end

    local menu_items = self.menu_formatter:entriesToMenuItems(entries, false) -- don't show feed names
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    self.browser.current_context = {
        type = "feed_entries",
        feed_id = feed_id,
        feed_title = feed_title,
    }

    local nav_data = self.path_service
            and self.path_service:createNavData(paths_updated, "feeds", {
                feed_id = feed_id,
                feed_title = feed_title,
            })
        or {}

    self:updateBrowser(feed_title, menu_items, subtitle, nav_data)
end

function ViewService:showCategoryEntries(category_id, category_title, paths_updated)
    local loading_info = UIComponents.showLoadingMessage(_("Fetching category entries..."))

    local entries, error_msg = self.entry_repository:getByCategory(category_id)
    UIComponents.closeLoadingMessage(loading_info)

    if not entries then
        UIComponents.showErrorMessage(_("Failed to fetch category entries: ") .. tostring(error_msg))
        return
    end

    local menu_items = self.menu_formatter:entriesToMenuItems(entries, true) -- show feed names
    local hide_read = self.settings.hide_read_entries
    local subtitle = self:buildSubtitle(#entries, hide_read, false, "entries")

    self.browser.current_context = {
        type = "category_entries",
        category_id = category_id,
        category_title = category_title,
    }

    local nav_data = self.path_service
            and self.path_service:createNavData(paths_updated, "categories", {
                category_id = category_id,
                category_title = category_title,
            })
        or {}

    self:updateBrowser(category_title, menu_items, subtitle, nav_data)
end

function ViewService:showMainContent()
    -- When going back to main, use the stored counts from browser initialization
    local hide_read = self.settings and self.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    self.browser.current_context = { type = "main" }

    local main_items = {
        {
            text = _("Unread"),
            mandatory = tostring(self.browser.unread_count),
            action_type = "unread",
        },
        {
            text = _("Feeds"),
            mandatory = tostring(self.browser.feeds_count),
            action_type = "feeds",
        },
        {
            text = _("Categories"),
            mandatory = tostring(self.browser.categories_count),
            action_type = "categories",
        },
    }

    self:updateBrowser(_("Miniflux"), main_items, subtitle, { paths_updated = true })
end

-- =============================================================================
-- BROWSER UPDATE ORCHESTRATION
-- =============================================================================

function ViewService:updateBrowser(title, items, subtitle, nav_data)
    -- Handle navigation paths via PathService
    if self.path_service then
        self.path_service:addToNavigationHistory(nav_data)
        self.path_service:updateBackButton()
    end

    -- Handle page restoration for back navigation
    local select_number = 1
    if nav_data and nav_data.restore_page_info then
        local target_page = nav_data.restore_page_info.page
        if target_page and target_page >= 1 then
            local perpage = self.browser.perpage or 20
            select_number = (target_page - 1) * perpage + 1
            if select_number > #items then
                select_number = #items > 0 and #items or 1
            end
        end
    end

    -- Update browser content
    self.browser.title = title
    self.browser.subtitle = subtitle or ""
    self.browser:switchItemTable(title, items, select_number, nil, subtitle)
end

-- =============================================================================
-- VIEW STATE MANAGEMENT
-- =============================================================================

function ViewService:refreshCurrentView()
    local context = self.browser.current_context
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

function ViewService:isInEntryView()
    if not self.browser.title then
        return false
    end

    local main_titles = {
        [_("Miniflux")] = true,
        [_("Feeds")] = true,
        [_("Categories")] = true,
    }

    return not main_titles[self.browser.title]
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

function ViewService:buildSubtitle(count, hide_read, is_unread_only, item_type)
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

return ViewService
