--[[--
Entries View for Miniflux Browser

Complete React-style component for entries display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.entries_view
--]]

local ViewUtils = require("browser/views/view_utils")
local _ = require("gettext")

local EntriesView = {}

---@alias EntriesViewConfig {repositories: MinifluxRepositories, settings: MinifluxSettings, entry_type: "unread"|"feed"|"category", id?: number, page_state?: number, onSelectItem: function}

---Complete entries view component (React-style) - returns view data for rendering
---@param config EntriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function EntriesView.show(config)
    local entry_type = config.entry_type
    local id = config.id

    -- Validate required parameters based on entry type
    if (entry_type == "feed" or entry_type == "category") and not id then
        error("ID is required for " .. entry_type .. " entry type")
    end
    ---@cast id -nil

    -- Prepare loading messages
    local loading_messages = {
        unread = _("Fetching unread entries..."),
        feed = _("Fetching feed entries..."),
        category = _("Fetching category entries...")
    }

    -- Create dialog configuration
    local dialog_config = {
        dialogs = {
            loading = { text = loading_messages[entry_type] },
            error = { text = _("Failed to fetch entries"), timeout = 5 }
        }
    }

    -- Fetch data based on type
    local entries, err
    if entry_type == "unread" then
        entries, err = config.repositories.entry:getUnread(dialog_config)
    elseif entry_type == "feed" then
        entries, err = config.repositories.entry:getByFeed(id, dialog_config)
    elseif entry_type == "category" then
        entries, err = config.repositories.entry:getByCategory(id, dialog_config)
    end

    if err then
        return nil -- Error dialog already shown by API system
    end
    ---@cast entries -nil

    -- Generate menu items using internal builder
    local show_feed_names = (entry_type == "unread" or entry_type == "category")
    local menu_items = EntriesView.buildItems({
        entries = entries,
        show_feed_names = show_feed_names,
        hide_read_entries = config.settings.hide_read_entries,
        onSelectItem = config.onSelectItem
    })

    -- Build subtitle based on type
    local subtitle
    if entry_type == "unread" then
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            is_unread_only = true
        })
    else
        subtitle = ViewUtils.buildSubtitle({
            count = #entries,
            hide_read = config.settings.hide_read_entries,
            item_type = "entries"
        })
    end

    -- Determine title
    local title
    if entry_type == "unread" then
        title = _("Unread Entries")
    elseif entry_type == "feed" then
        title = _("Feed Entries")
        if #entries > 0 and entries[1].feed and entries[1].feed.title then
            title = entries[1].feed.title
        end
    elseif entry_type == "category" then
        title = _("Category Entries")
        if #entries > 0 and entries[1].feed and entries[1].feed.category and entries[1].feed.category.title then
            title = entries[1].feed.category.title
        end
    end

    -- Add status indicator to title using ViewUtils
    local force_unread = (entry_type == "unread")
    title = ViewUtils.addStatusIndicator(title, config.settings, force_unread)

    -- Return view data for browser to render
    return {
        title = title,
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle
    }
end

---Build a single entry menu item with status indicators
---@param entry table Entry data
---@param config {show_feed_names: boolean, onSelectItem: function}
---@return table Menu item for single entry
function EntriesView.buildSingleItem(entry, config)
    local entry_title = entry.title or _("Untitled Entry")
    local status_indicator = entry.status == "read" and "○ " or "● "
    local display_text = status_indicator .. entry_title

    if config.show_feed_names and entry.feed and entry.feed.title then
        display_text = display_text .. " (" .. entry.feed.title .. ")"
    end

    return {
        text = display_text,
        action_type = "read_entry",
        entry_data = entry,
        callback = function()
            config.onSelectItem(entry)
        end
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
        local message = hide_read_entries and _("There are no unread entries.") or _("There are no entries.")
        return { { text = message, mandatory = "", action_type = "no_action" } }
    end

    for _, entry in ipairs(entries) do
        local item = EntriesView.buildSingleItem(entry, {
            show_feed_names = show_feed_names,
            onSelectItem = onSelectItem
        })
        table.insert(menu_items, item)
    end

    return menu_items
end

return EntriesView
