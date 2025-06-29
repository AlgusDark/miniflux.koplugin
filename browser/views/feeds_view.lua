--[[--
Feeds View for Miniflux Browser

Complete React-style component for feeds display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.feeds_view
--]]

local ViewUtils = require("browser/views/view_utils")
local _ = require("gettext")

local FeedsView = {}

---Complete feeds view component (React-style) - returns view data for rendering
---@param config {repositories: table, settings: table, page_state?: number, onSelectItem: function}
---@return table|nil View data for browser rendering, or nil on error
function FeedsView.show(config)
    -- Fetch data with API-level dialog management
    local result, error_msg = config.repositories.feed:getAllWithCounters({
        dialogs = {
            loading = { text = _("Fetching feeds...") },
            error = { text = _("Failed to fetch feeds"), timeout = 5 }
        }
    })

    if not result then
        return nil -- Error dialog already shown by API system
    end

    -- Generate menu items using internal builder
    local menu_items = FeedsView.buildItems({
        feeds = result.feeds,
        counters = result.counters,
        onSelectItem = config.onSelectItem
    })

    local hide_read = config.settings.hide_read_entries
    local subtitle = ViewUtils.buildSubtitle({
        count = #result.feeds,
        hide_read = hide_read,
        item_type = "feeds"
    })

    -- Return view data for browser to render
    return {
        title = _("Feeds"),
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle
    }
end

---Build feeds menu items with counters (internal helper)
---@param config {feeds: table[], counters: table, onSelectItem: function}
---@return table[] Menu items for feeds view
function FeedsView.buildItems(config)
    local feeds = config.feeds or {}
    local counters = config.counters
    local onSelectItem = config.onSelectItem

    local menu_items = {}

    for _, feed in ipairs(feeds) do
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
        local count_info = ViewUtils.formatCountDisplay({
            read_count = read_count,
            unread_count = unread_count
        })

        table.insert(menu_items, {
            text = feed_title,
            mandatory = count_info,
            action_type = "feed_entries",
            unread_count = unread_count,
            feed_data = { id = feed.id, title = feed_title, unread_count = unread_count },
            callback = function()
                onSelectItem(feed.id)
            end
        })
    end

    -- Sort by unread priority
    ViewUtils.sortByUnreadPriority(menu_items)

    return menu_items
end

return FeedsView
