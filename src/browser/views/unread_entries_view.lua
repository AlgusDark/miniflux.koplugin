--[[--
Unread Entries View for Miniflux Browser

Specialized view for displaying unread entries that leverages EntriesView
but with specific behavior for unread-only content.

@module miniflux.browser.views.unread_entries_view
--]]

local EntriesView = require('browser/views/entries_view')
local _ = require('gettext')

local UnreadEntriesView = {}

---@alias UnreadEntriesViewConfig {cache_service: CacheService, settings: MinifluxSettings, page_state?: number, onSelectItem: function}

---Complete unread entries view component - returns view data for rendering
---@param config UnreadEntriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function UnreadEntriesView.show(config)
    -- Fetch unread entries with API-level dialog management
    local entries, err = config.cache_service:getUnreadEntries({
        dialogs = {
            loading = { text = _('Fetching unread entries...') },
            error = { text = _('Failed to fetch unread entries'), timeout = 5 },
        },
    })

    if err then
        return nil -- Error dialog already shown by API system
    end
    ---@cast entries -nil

    -- Generate menu items using EntriesView builder
    -- For unread entries: always show feed names and ignore hide_read_entries
    local menu_items = EntriesView.buildItems({
        entries = entries,
        show_feed_names = true, -- Always show feed names for unread entries
        hide_read_entries = true, -- Always true for unread entries (affects empty message)
        onSelectItem = config.onSelectItem,
    })

    -- Build clean title (status shown in subtitle now)
    local ViewUtils = require('browser/views/view_utils')
    local title = _('Unread Entries')
    local subtitle = ViewUtils.buildSubtitle({
        count = #entries,
        is_unread_only = true,
    })

    -- Return view data for browser to render
    return {
        title = title,
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle,
    }
end

return UnreadEntriesView
