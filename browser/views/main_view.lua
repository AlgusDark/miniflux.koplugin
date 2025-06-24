--[[--
Main View for Miniflux Browser

Handles main screen data loading and menu item construction.

@module miniflux.browser.views.main_view
--]]

local _ = require("gettext")

local MainView = {}

---Load initial data needed for main screen
---@param config {repositories: {entry: EntryRepository, feed: FeedRepository, category: CategoryRepository}}
---@return table|nil result Data with counts or nil on error
---@return string|nil error Error message if failed
function MainView.loadData(config)
    local repositories = config.repositories

    -- Get unread count with dialog
    local unread_count, error_msg = repositories.entry:getUnreadCount({
        dialogs = {
            loading = { text = _("Loading unread count...") }
        }
    })
    if not unread_count then
        return nil, error_msg
    end

    -- Get feeds count with dialog
    local feeds_count = repositories.feed:getCount({
        dialogs = {
            loading = { text = _("Loading feeds count...") }
        }
    })

    -- Get categories count with dialog
    local categories_count = repositories.category:getCount({
        dialogs = {
            loading = { text = _("Loading categories count...") }
        }
    })

    return {
        unread_count = unread_count,
        feeds_count = feeds_count,
        categories_count = categories_count,
    }
end

---Build main menu items
---@param config {counts: table, callbacks: {on_unread: function, on_feeds: function, on_categories: function}}
---@return table[] Menu items for main screen
function MainView.buildItems(config)
    local counts = config.counts
    local callbacks = config.callbacks

    return {
        {
            text = _("Unread"),
            mandatory = tostring(counts.unread_count or 0),
            callback = callbacks.on_unread
        },
        {
            text = _("Feeds"),
            mandatory = tostring(counts.feeds_count or 0),
            callback = callbacks.on_feeds
        },
        {
            text = _("Categories"),
            mandatory = tostring(counts.categories_count or 0),
            callback = callbacks.on_categories
        },
    }
end

return MainView
