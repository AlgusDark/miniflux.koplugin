--[[--
Miniflux utility functions for common operations

@module koplugin.miniflux.utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local MinifluxUtils = {}

-- ============================================================================
-- ENTRY FILTERING UTILITIES
-- ============================================================================

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

function MinifluxUtils.getStatusIndicator(entry)
    return entry.status == "read" and "✓" or "●"
end

function MinifluxUtils.getBookmarkIndicator(entry)
    return entry.starred and " ⭐" or ""
end

function MinifluxUtils.getFeedTitleSuffix(entry)
    if entry.feed and entry.feed.title then
        return " [" .. entry.feed.title .. "]"
    end
    return ""
end

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

function MinifluxUtils.buildEntryMenuItems(entries, callback_generator, include_feed)
    local menu_items = {}
    
    for _, entry in ipairs(entries) do
        local callback = callback_generator(entry)
        local menu_item = MinifluxUtils.buildEntryMenuItem(entry, callback, include_feed)
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

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

function MinifluxUtils.createTodoCallback(entry)
    return function()
        UIManager:show(InfoMessage:new{
            text = "TODO: " .. tostring(entry.id),
            timeout = 3,
        })
    end
end

return MinifluxUtils