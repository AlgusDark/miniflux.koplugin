--[[--
Feeds View for Miniflux Browser

Handles feeds list view construction with counters.

@module miniflux.browser.views.feeds_view
--]]

local ViewUtils = require("browser/views/view_utils")
local _ = require("gettext")

local FeedsView = {}

---Build feeds menu items with counters
---@param config {feeds: table[], counters: table, on_select_callback: function}
---@return table[] Menu items for feeds view
function FeedsView.buildItems(config)
    local feeds = config.feeds or {}
    local counters = config.counters
    local on_select_callback = config.on_select_callback

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
                on_select_callback(feed.id)
            end
        })
    end

    -- Sort by unread priority
    ViewUtils.sortByUnreadPriority(menu_items)

    return menu_items
end

return FeedsView
