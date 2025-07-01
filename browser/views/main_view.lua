--[[--
Main View for Miniflux Browser

Complete React-style component for main screen display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.main_view
--]]

local _ = require("gettext")

local MainView = {}

---@alias MainViewConfig {repositories: MinifluxRepositories, settings: MinifluxSettings, onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function}

---Complete main view component (React-style) - returns view data for rendering
---@param config MainViewConfig
---@return table|nil View data for browser rendering, or nil on error
function MainView.show(config)
    -- Load initial data
    local counts, error_msg = MainView.loadData({ repositories = config.repositories })
    if not counts then
        local Notification = require("utils/notification")
        Notification:error(_("Failed to load Miniflux: ") .. tostring(error_msg))
        return nil
    end

    -- Generate menu items using internal builder
    local main_items = MainView.buildItems({
        counts = counts,
        callbacks = {
            onSelectUnread = config.onSelectUnread,
            onSelectFeeds = config.onSelectFeeds,
            onSelectCategories = config.onSelectCategories,
        }
    })

    -- Build subtitle
    local hide_read = config.settings and config.settings.hide_read_entries
    local subtitle = hide_read and "⊘ " or "◯ "

    -- Return view data for browser to render
    return {
        title = _("Miniflux"),
        items = main_items,
        page_state = nil,
        subtitle = subtitle,
        is_root = true -- Signals browser to clear navigation history
    }
end

---Load initial data needed for main screen (internal helper)
---@param config {repositories: MinifluxRepositories}
---@return table|nil result, string|nil error
function MainView.loadData(config)
    local repositories = config.repositories

    local Notification = require("utils/notification")
    local loading_notification = Notification:info({
        text = _("Loading..."),
        timeout = nil,
    })

    -- Get unread count with dialog
    local unread_count, unread_err = repositories.entry:getUnreadCount()
    if unread_err then
        loading_notification:close()
        return nil, unread_err.message
    end
    ---@cast unread_count -nil

    -- Get feeds count with dialog
    local feeds_count = repositories.feed:getCount()

    -- Get categories count with dialog
    local categories_count = repositories.category:getCount()

    loading_notification:close()

    return {
        unread_count = unread_count or 0,
        feeds_count = feeds_count or 0,
        categories_count = categories_count or 0,
    }
end

---Build main menu items (internal helper)
---@param config {counts: table, callbacks: {onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function}}
---@return table[] Menu items for main screen
function MainView.buildItems(config)
    local counts = config.counts
    local callbacks = config.callbacks

    return {
        {
            text = _("Unread"),
            mandatory = tostring(counts.unread_count or 0),
            callback = callbacks.onSelectUnread
        },
        {
            text = _("Feeds"),
            mandatory = tostring(counts.feeds_count or 0),
            callback = callbacks.onSelectFeeds
        },
        {
            text = _("Categories"),
            mandatory = tostring(counts.categories_count or 0),
            callback = callbacks.onSelectCategories
        },
    }
end

return MainView
