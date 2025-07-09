--[[--
Main View for Miniflux Browser

Complete React-style component for main screen display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.main_view
--]]

local _ = require("gettext")
local ViewUtils = require("browser/views/view_utils")

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

    -- Build title with status indicator using ViewUtils
    local title = ViewUtils.addStatusIndicator(_("Miniflux"), config.settings)

    -- Return view data for browser to render
    return {
        title = title,
        items = main_items,
        page_state = nil,
        subtitle = nil,
        is_root = true -- Signals browser to clear navigation history
    }
end

---Load initial data needed for main screen (internal helper)
---@param config {repositories: MinifluxRepositories}
---@return table|nil result, string|nil error
function MainView.loadData(config)
    local repositories = config.repositories

    local Notification = require("utils/notification")
    local loading_notification = Notification:info(_("Loading..."))

    -- Get unread count
    local unread_count, unread_err = repositories.entry:getUnreadCount()
    if unread_err then
        loading_notification:close()
        return nil, unread_err.message
    end
    ---@cast unread_count -nil

    -- Get feeds count
    local feeds_count, feeds_err = repositories.feed:getCount()
    if feeds_err then
        loading_notification:close()
        return nil, feeds_err.message
    end
    ---@cast feeds_count -nil

    -- Get categories count
    local categories_count, categories_err = repositories.category:getCount()
    if categories_err then
        loading_notification:close()
        return nil, categories_err.message
    end
    ---@cast categories_count -nil

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
