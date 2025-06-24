--[[--
Entries View for Miniflux Browser

Handles entries list view construction with status indicators.

@module miniflux.browser.views.entries_view
--]]

local _ = require("gettext")

local EntriesView = {}

---Build entries menu items with status indicators
---@param config {entries: table[], show_feed_names: boolean, on_select_callback: function, hide_read_entries?: boolean}
---@return table[] Menu items for entries view
function EntriesView.buildItems(config)
    local entries = config.entries or {}
    local show_feed_names = config.show_feed_names
    local on_select_callback = config.on_select_callback
    local hide_read_entries = config.hide_read_entries

    local menu_items = {}

    if #entries == 0 then
        local message = hide_read_entries and _("There are no unread entries.") or _("There are no entries.")
        return { { text = message, mandatory = "", action_type = "no_action" } }
    end

    for _, entry in ipairs(entries) do
        local entry_title = entry.title or _("Untitled Entry")
        local status_indicator = entry.status == "read" and "○ " or "● "
        local display_text = status_indicator .. entry_title

        if show_feed_names and entry.feed and entry.feed.title then
            display_text = display_text .. " (" .. entry.feed.title .. ")"
        end

        table.insert(menu_items, {
            text = display_text,
            action_type = "read_entry",
            entry_data = entry,
            callback = function()
                on_select_callback(entry)
            end
        })
    end

    return menu_items
end

return EntriesView
