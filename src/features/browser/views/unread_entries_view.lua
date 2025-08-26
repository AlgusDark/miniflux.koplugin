--[[--
Unread Entries View for Miniflux Browser

Specialized view for displaying unread entries that leverages EntriesView
but with specific behavior for unread-only content.

@module miniflux.browser.views.unread_entries_view
--]]

local EntriesView = require('features/browser/views/entries_view')
local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local _ = require('gettext')

local UnreadEntriesView = {}

---@alias UnreadEntriesViewConfig {entries: Entries, settings: MinifluxSettings, page_state?: number, onSelectItem: function}

---Complete unread entries view component - returns view data for rendering
---@param config UnreadEntriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function UnreadEntriesView.show(config)
    local ViewUtils = require('features/browser/views/view_utils')

    -- Show loading message with forceRePaint before API call
    local loading_widget = InfoMessage:new({
        text = _('Loading unread entries...'),
    })
    UIManager:show(loading_widget)
    UIManager:forceRePaint()

    -- Get entries directly from entries domain
    local entries, err = config.entries:getUnreadEntries({})

    -- Close loading message
    UIManager:close(loading_widget)

    if err then
        UIManager:show(InfoMessage:new({
            text = _('Failed to load unread entries'),
            timeout = 5,
        }))
        return nil
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
