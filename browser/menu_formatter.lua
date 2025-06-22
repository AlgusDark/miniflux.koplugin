--[[--
Menu Formatter for Miniflux Browser

This module handles menu item formatting and presentation logic only.
Transforms data into menu structures for display without handling data access.

@module miniflux.browser.menu_formatter
--]] --

local _ = require("gettext")

---@class MenuFormatter
---@field settings MinifluxSettings Settings instance
local MenuFormatter = {}

---@class EntryMenuConfig
---@field show_feed_names? boolean Whether to show feed names in entries (default: false)

---@class FeedMenuConfig
---@field feed_counters? FeedCounters Feed counters with reads/unreads maps

---Create a new MenuFormatter instance
---@param settings MinifluxSettings The settings instance
---@return MenuFormatter
function MenuFormatter:new(settings)
    local obj = {
        settings = settings
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- MENU ITEM FORMATTING METHODS
-- =============================================================================

---Convert entries to menu items
---@param entries table[] Array of entry data
---@param config? EntryMenuConfig Configuration options
---@return table[] Array of menu items
function MenuFormatter:entriesToMenuItems(entries, config)
    config = config or {}
    local show_feed_names = config.show_feed_names or false

    if not entries or #entries == 0 then
        local hide_read = self.settings.hide_read_entries
        return {
            {
                text = hide_read and _("There are no unread entries.") or _("There are no entries."),
                mandatory = "",
                action_type = "no_action",
            }
        }
    end

    local menu_items = {}

    for _, entry in ipairs(entries) do
        local entry_title = entry.title or _("Untitled Entry")
        local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")

        -- Add status indicator
        local status_indicator = entry.status == "read" and "○ " or "● "

        -- Build display text
        local display_text = status_indicator .. entry_title
        if show_feed_names then
            display_text = status_indicator .. entry_title .. " (" .. feed_title .. ")"
        end

        local menu_item = {
            text = display_text,
            action_type = "read_entry",
            entry_data = entry
        }

        table.insert(menu_items, menu_item)
    end

    return menu_items
end

---Convert feeds to menu items
---@param feeds table[] Array of feed data
---@param config? FeedMenuConfig Configuration options
---@return table[] Array of menu items
function MenuFormatter:feedsToMenuItems(feeds, config)
    config = config or {}
    local feed_counters = config.feed_counters

    local menu_items = {}

    for _, feed in ipairs(feeds) do
        local feed_title = feed.title or _("Untitled Feed")
        local feed_id_str = tostring(feed.id)

        -- Get counts from counters if available
        local read_count = feed_counters and feed_counters.reads and feed_counters.reads[feed_id_str] or 0
        local unread_count = feed_counters and feed_counters.unreads and feed_counters.unreads[feed_id_str] or 0
        local total_count = read_count + unread_count

        -- Format count display
        local count_info = ""
        if unread_count > 0 or total_count > 0 then
            count_info = string.format("(%d/%d)", unread_count, total_count)
        end

        local menu_item = {
            text = feed_title,
            mandatory = count_info,
            action_type = "feed_entries",
            unread_count = unread_count, -- For sorting
            feed_data = {
                id = feed.id,
                title = feed_title,
                unread_count = unread_count
            }
        }

        table.insert(menu_items, menu_item)
    end

    -- Sort by unread count
    self:sortByUnreadCount(menu_items)

    return menu_items
end

---Convert categories to menu items
---@param categories table[] Array of category data
---@return table[] Array of menu items
function MenuFormatter:categoriesToMenuItems(categories)
    local menu_items = {}

    for _, category in ipairs(categories) do
        local category_title = category.title or _("Untitled Category")
        local unread_count = category.total_unread or 0

        local menu_item = {
            text = category_title,
            mandatory = string.format("(%d)", unread_count),
            action_type = "category_entries",
            unread_count = unread_count, -- For sorting
            category_data = {
                id = category.id,
                title = category_title,
                unread_count = unread_count,
            }
        }

        table.insert(menu_items, menu_item)
    end

    -- Sort by unread count
    self:sortByUnreadCount(menu_items)

    return menu_items
end

-- =============================================================================
-- SORTING UTILITIES
-- =============================================================================

---Sort menu items by unread count
---@param items table[] Array of menu items to sort
---@return nil
function MenuFormatter:sortByUnreadCount(items)
    table.sort(items, function(a, b)
        local a_unread = self:getUnreadCountFromItem(a)
        local b_unread = self:getUnreadCountFromItem(b)
        local a_title = self:getTitleFromItem(a)
        local b_title = self:getTitleFromItem(b)

        -- Items with unread entries come first
        if a_unread > 0 and b_unread == 0 then
            return true
        elseif a_unread == 0 and b_unread > 0 then
            return false
        end

        -- If both have unread entries, sort by unread count (descending)
        if a_unread > 0 and b_unread > 0 and a_unread ~= b_unread then
            return a_unread > b_unread
        end

        -- Otherwise sort alphabetically
        return a_title:lower() < b_title:lower()
    end)
end

---Get unread count from menu item
---@param item table Menu item
---@return number Unread count
function MenuFormatter:getUnreadCountFromItem(item)
    -- Handle feeds (direct unread_count property)
    if item.unread_count then
        return item.unread_count
    end

    -- Handle categories (nested in category_data)
    if item.category_data and item.category_data.unread_count then
        return item.category_data.unread_count
    end

    -- Handle feeds (nested in feed_data)
    if item.feed_data and item.feed_data.unread_count then
        return item.feed_data.unread_count
    end

    return 0
end

---Get title from menu item
---@param item table Menu item
---@return string Title text
function MenuFormatter:getTitleFromItem(item)
    -- Try category data first
    if item.category_data and item.category_data.title then
        return item.category_data.title
    end

    -- Try feed data next
    if item.feed_data and item.feed_data.title then
        return item.feed_data.title
    end

    -- Fallback to direct text
    return item.text or ""
end

return MenuFormatter
