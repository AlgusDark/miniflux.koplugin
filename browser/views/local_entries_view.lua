--[[--
Local Entries View for Miniflux Browser

Complete React-style component for local entries display.
Shows downloaded entries without network dependency.

@module miniflux.browser.views.local_entries_view
--]]

local ViewUtils = require("browser/views/view_utils")
local EntryEntity = require("entities/entry_entity")
local EntriesView = require("browser/views/entries_view")
local _ = require("gettext")

local LocalEntriesView = {}

---@alias LocalEntriesViewConfig {settings: MinifluxSettings, page_state?: number, onSelectItem: function}

---Complete local entries view component (React-style) - returns view data for rendering
---@param config LocalEntriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function LocalEntriesView.show(config)
    -- Get local entries (no network required)
    local entries = EntryEntity.getLocalEntries()
    
    -- Generate menu items using existing EntriesView logic
    -- Note: Local entries ignore hide_read_entries setting for simplicity
    local menu_items = LocalEntriesView.buildItems({
        entries = entries,
        show_feed_names = true, -- Show feed names like in unread view
        onSelectItem = config.onSelectItem
    })

    -- Build subtitle showing count
    local subtitle = ViewUtils.buildSubtitle({
        count = #entries,
        is_local_only = true -- Special flag for local entries
    })

    -- Return view data for browser to render
    return {
        title = _("Local Entries"),
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle
    }
end

---Build local entries menu items (internal helper)
---@param config {entries: table[], show_feed_names: boolean, onSelectItem: function}
---@return table[] Menu items for local entries view
function LocalEntriesView.buildItems(config)
    local entries = config.entries or {}
    local show_feed_names = config.show_feed_names
    local onSelectItem = config.onSelectItem

    local menu_items = {}

    if #entries == 0 then
        return { { text = _("No downloaded entries found."), mandatory = "", action_type = "no_action" } }
    end

    -- Reuse existing EntriesView.buildSingleItem for consistency
    for _, entry in ipairs(entries) do
        local item = EntriesView.buildSingleItem(entry, {
            show_feed_names = show_feed_names,
            onSelectItem = onSelectItem
        })
        table.insert(menu_items, item)
    end

    return menu_items
end

return LocalEntriesView