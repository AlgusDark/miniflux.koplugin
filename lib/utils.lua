--[[--
Miniflux utility functions for common operations

@module koplugin.miniflux.utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

---@class FilterResult
---@field [1] MinifluxEntry[] Filtered entries
---@field [2] number Unread count
---@field [3] number Read count

---@class EntryMenuItem
---@field text string Menu item display text
---@field callback function Function to call when item is selected
---@field entry_data MinifluxEntry Associated entry data

local MinifluxUtils = {}

-- ============================================================================
-- ENTRY FILTERING UTILITIES
-- ============================================================================

---Filter entries by read status
---@param entries MinifluxEntry[] Array of entries to filter
---@param show_read boolean Whether to include read entries
---@return MinifluxEntry[] filtered_entries, number unread_count, number read_count
function MinifluxUtils.filterEntriesByReadStatus(entries, show_read)
    if not entries or #entries == 0 then
        return {}, 0, 0
    end
    
    show_read = show_read == true -- default to false (show only unread)
    
    local filtered_entries = {}
    local unread_count = 0
    local read_count = 0
    
    for _, entry in ipairs(entries) do
        if entry.status == "unread" then
            unread_count = unread_count + 1
            table.insert(filtered_entries, entry)
        elseif entry.status == "read" then
            read_count = read_count + 1
            if show_read then
                table.insert(filtered_entries, entry)
            end
        end
    end
    
    return filtered_entries, unread_count, read_count
end

---Format entry publication date
---@param published_at string|nil ISO date string from entry
---@return string Formatted date string
function MinifluxUtils.formatEntryDate(published_at)
    if not published_at then
        return ""
    end
    
    local year, month, day = published_at:match("(%d+)-(%d+)-(%d+)")
    if year and month and day then
        return string.format("%s/%s/%s", month, day, year:sub(-2))
    end
    
    return ""
end

---Get status indicator for entry
---@param entry MinifluxEntry The entry to get status for
---@return string Status indicator character
function MinifluxUtils.getStatusIndicator(entry)
    return entry.status == "read" and "✓" or "●"
end

---Get bookmark indicator for entry
---@param entry MinifluxEntry The entry to get bookmark status for
---@return string Bookmark indicator or empty string
function MinifluxUtils.getBookmarkIndicator(entry)
    return entry.starred and " ⭐" or ""
end

---Get feed title suffix for entry
---@param entry MinifluxEntry The entry to get feed title for
---@return string Feed title suffix or empty string
function MinifluxUtils.getFeedTitleSuffix(entry)
    if entry.feed and entry.feed.title then
        return " [" .. entry.feed.title .. "]"
    end
    return ""
end

---Build a menu item for an entry
---@param entry MinifluxEntry The entry to create menu item for
---@param callback function Function to call when item is selected
---@param include_feed? boolean Whether to include feed name (default: true)
---@return EntryMenuItem Menu item data
function MinifluxUtils.buildEntryMenuItem(entry, callback, include_feed)
    include_feed = include_feed ~= false -- default to true
    
    local status_indicator = MinifluxUtils.getStatusIndicator(entry)
    local bookmark_indicator = MinifluxUtils.getBookmarkIndicator(entry)
    local entry_title = entry.title or _("Untitled")
    local feed_suffix = include_feed and MinifluxUtils.getFeedTitleSuffix(entry) or ""
    local date_str = MinifluxUtils.formatEntryDate(entry.published_at)
    
    return {
        text = status_indicator .. " " .. entry_title .. bookmark_indicator .. feed_suffix .. "\n" .. date_str,
        callback = callback,
        entry_data = entry,
    }
end

---Build menu items for multiple entries
---@param entries MinifluxEntry[] Array of entries
---@param callback_generator function Function that takes entry and returns callback
---@param include_feed? boolean Whether to include feed names (default: true)
---@return EntryMenuItem[] Array of menu items
function MinifluxUtils.buildEntryMenuItems(entries, callback_generator, include_feed)
    local menu_items = {}
    
    for _, entry in ipairs(entries) do
        local callback = callback_generator(entry)
        local menu_item = MinifluxUtils.buildEntryMenuItem(entry, callback, include_feed)
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

---Create toggle title with entry counts
---@param base_title string Base title text
---@param unread_count number Number of unread entries
---@param read_count number Number of read entries
---@param show_read boolean Whether read entries are being shown
---@param total_entries number Total number of entries
---@return string Formatted title with counts
function MinifluxUtils.createToggleTitle(base_title, unread_count, read_count, show_read, total_entries)
    local count_line
    if show_read then
        -- Showing both unread and read
        count_line = string.format("%d entries (%d unread, %d read)", 
            total_entries, unread_count, read_count)
    else
        -- Showing only unread (default)
        count_line = string.format("%d unread entries", unread_count)
    end
    
    return base_title .. "\n" .. count_line
end

---Create a placeholder TODO callback for development
---@param entry MinifluxEntry The entry for the TODO action
---@return function Callback function that shows TODO message
function MinifluxUtils.createTodoCallback(entry)
    return function()
        UIManager:show(InfoMessage:new{
            text = "TODO: " .. tostring(entry.id),
            timeout = 3,
        })
    end
end

return MinifluxUtils