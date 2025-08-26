--[[--
Entries View for Miniflux Browser

Complete React-style component for entries display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.entries_view
--]]

local EntryPaths = require('domains/utils/entry_paths')
local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local _ = require('gettext')

local EntriesView = {}

---@alias EntriesViewConfig {feeds?: Feeds, categories?: Categories, entries: Entries, settings: MinifluxSettings, entry_type: "unread"|"feed"|"category", id?: number, page_state?: number, onSelectItem: function}

---Complete entries view component - returns view data for rendering
---@param config EntriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function EntriesView.show(config)
    local entry_type = config.entry_type
    local id = config.id

    -- Validate required parameters based on entry type
    if (entry_type == 'feed' or entry_type == 'category') and not id then
        return nil -- ID is required for feed/category types
    end
    ---@cast id number

    -- Show loading message with forceRePaint before API call
    local loading_widget = InfoMessage:new({
        text = _('Loading entries...'),
    })
    UIManager:show(loading_widget)
    UIManager:forceRePaint()

    local entries, err
    if entry_type == 'unread' then
        entries, err = config.entries:getUnreadEntries({})
    elseif entry_type == 'feed' then
        if not config.feeds then
            UIManager:close(loading_widget)
            return nil -- feeds domain not provided
        end
        entries, err = config.feeds:getEntriesByFeed(id, {})
    elseif entry_type == 'category' then
        if not config.categories then
            UIManager:close(loading_widget)
            return nil -- categories domain not provided
        end
        entries, err = config.categories:getEntriesByCategory(id, {})
    else
        UIManager:close(loading_widget)
        return nil -- Invalid entry type
    end

    -- Close loading message
    UIManager:close(loading_widget)

    if err then
        UIManager:show(InfoMessage:new({
            text = _('Failed to load entries'),
            timeout = 5,
        }))
        return nil
    end

    local ViewUtils = require('features/browser/views/view_utils')
    ---@cast entries -nil

    -- Generate menu items using internal builder
    local show_feed_names = (entry_type == 'unread' or entry_type == 'category')
    local menu_items = EntriesView.buildItems({
        entries = entries,
        show_feed_names = show_feed_names,
        hide_read_entries = config.settings.hide_read_entries,
        onSelectItem = config.onSelectItem,
    })

    -- Build subtitle based on type
    local subtitle
    if entry_type == 'unread' then
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            is_unread_only = true,
        })
    else
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            hide_read = config.settings.hide_read_entries,
            item_type = 'entries',
        })
    end

    -- Determine title
    local title
    if entry_type == 'unread' then
        title = _('Unread Entries')
    elseif entry_type == 'feed' then
        title = _('Feed Entries')
        if #entries > 0 and entries[1].feed and entries[1].feed.title then
            title = entries[1].feed.title
        end
    elseif entry_type == 'category' then
        title = _('Category Entries')
        if
            #entries > 0
            and entries[1].feed
            and entries[1].feed.category
            and entries[1].feed.category.title
        then
            title = entries[1].feed.category.title
        end
    end

    -- Clean title (status shown in subtitle now)

    -- Return view data for browser to render
    return {
        title = title,
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle,
    }
end

---Build a single entry menu item with status indicators
---@param entry table Entry data
---@param config {show_feed_names: boolean, onSelectItem: function}
---@return table Menu item for single entry
function EntriesView.buildSingleItem(entry, config)
    local entry_title = entry.title or _('Untitled Entry')

    -- Check both read status and local download status
    local is_read = entry.status == 'read'

    -- Try cache first for download status, fallback to filesystem check
    local MinifluxBrowser = require('features/browser/miniflux_browser')
    local cached_entry = MinifluxBrowser.getEntryInfoCache(entry.id)
    local is_downloaded = cached_entry ~= nil
    if not cached_entry then
        is_downloaded = EntryPaths.isEntryDownloaded(entry.id)
    end

    -- Create 2x2 indicator matrix: read/unread × downloaded/not downloaded
    local status_indicator
    if is_downloaded then
        status_indicator = is_read and '◎ ' or '◉ ' -- Downloaded: ◎=read, ◉=unread
    else
        status_indicator = is_read and '○ ' or '● ' -- Not downloaded: ○=read, ●=unread
    end

    local display_text = status_indicator .. entry_title

    if config.show_feed_names and entry.feed and entry.feed.title then
        display_text = display_text .. ' (' .. entry.feed.title .. ')'
    end

    return {
        text = display_text,
        action_type = 'read_entry',
        entry_data = entry,
        callback = function()
            config.onSelectItem(entry)
        end,
    }
end

---Build entries menu items with status indicators (internal helper)
---@param config {entries: table[], show_feed_names: boolean, onSelectItem: function, hide_read_entries?: boolean}
---@return table[] Menu items for entries view
function EntriesView.buildItems(config)
    local entries = config.entries or {}
    local show_feed_names = config.show_feed_names
    local onSelectItem = config.onSelectItem
    local hide_read_entries = config.hide_read_entries

    local menu_items = {}

    if #entries == 0 then
        local message = hide_read_entries and _('There are no unread entries.')
            or _('There are no entries.')
        return { { text = message, mandatory = '', action_type = 'no_action' } }
    end

    for _, entry in ipairs(entries) do
        local item = EntriesView.buildSingleItem(entry, {
            show_feed_names = show_feed_names,
            onSelectItem = onSelectItem,
        })
        table.insert(menu_items, item)
    end

    return menu_items
end

return EntriesView
