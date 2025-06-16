--[[--
UI Components for Miniflux Browser Screens

This module provides reusable UI components for the screen layer, including
menu item builders, subtitle formatters, and common screen patterns.

@module miniflux.browser.screens.ui_components
--]]--

local _ = require("gettext")

local ScreenUI = {}

-- =============================================================================
-- MENU ITEM COMPONENTS
-- =============================================================================

---Create a standard menu item
---@param params {text: string, mandatory?: string, action_type: string, data?: table}
---@return table Menu item
function ScreenUI.createMenuItem(params)
    return {
        text = params.text,
        mandatory = params.mandatory or "",
        action_type = params.action_type,
        entry_data = params.data and params.data.entry_data,
        feed_data = params.data and params.data.feed_data,
        category_data = params.data and params.data.category_data,
    }
end

---Create a "no entries" menu item
---@param is_unread_only? boolean Whether this is for unread-only view
---@param custom_message? string Custom message instead of default
---@return table Menu item
function ScreenUI.createNoEntriesItem(is_unread_only, custom_message)
    local message
    if custom_message then
        message = custom_message
    elseif is_unread_only then
        message = _("There are no unread entries.")
    else
        -- This would need access to settings to determine the exact message
        -- For now, we'll use a generic message
        message = _("There are no entries.")
    end
    
    return ScreenUI.createMenuItem({
        text = message,
        action_type = "no_action"
    })
end

---Create an entry menu item with status indicator
---@param entry MinifluxEntry Entry data
---@param is_category_view? boolean Whether this is for category view (shows feed title)
---@return table Menu item
function ScreenUI.createEntryMenuItem(entry, is_category_view)
    local entry_title = entry.title or _("Untitled Entry")
    local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
    
    -- Add status indicator
    local status_indicator = entry.status == "read" and "○ " or "● "
    
    -- Build display text
    local display_text = status_indicator .. entry_title
    if is_category_view then
        display_text = status_indicator .. entry_title .. " (" .. feed_title .. ")"
    end
    
    return ScreenUI.createMenuItem({
        text = display_text,
        action_type = "read_entry",
        data = { entry_data = entry }
    })
end

---Create a feed menu item
---@param feed MinifluxFeed Feed data
---@param unread_count? number Unread count for this feed
---@param total_count? number Total count for this feed
---@return table Menu item
function ScreenUI.createFeedMenuItem(feed, unread_count, total_count)
    local feed_title = feed.title or _("Untitled Feed")
    
    -- Format count display
    local count_info = ""
    if unread_count and total_count then
        count_info = string.format("(%d/%d)", unread_count, total_count)
    elseif unread_count then
        count_info = string.format("(%d)", unread_count)
    end
    
    return ScreenUI.createMenuItem({
        text = feed_title,
        mandatory = count_info,
        action_type = "feed_entries",
        data = { 
            feed_data = {
                id = feed.id,
                title = feed_title,
                unread_count = unread_count or 0
            }
        }
    })
end

---Create a category menu item
---@param category MinifluxCategory Category data
---@return table Menu item
function ScreenUI.createCategoryMenuItem(category)
    local category_title = category.title or _("Untitled Category")
    local unread_count = category.total_unread or 0
    
    return ScreenUI.createMenuItem({
        text = category_title,
        mandatory = string.format("(%d)", unread_count),
        action_type = "category_entries",
        data = {
            category_data = {
                id = category.id,
                title = category_title,
                unread_count = unread_count,
            }
        }
    })
end

---Create a main menu item (Unread, Feeds, Categories)
---@param text string Menu item text
---@param count number Count to display
---@param action_type string Action type
---@return table Menu item
function ScreenUI.createMainMenuItem(text, count, action_type)
    return ScreenUI.createMenuItem({
        text = text,
        mandatory = tostring(count),
        action_type = action_type
    })
end

-- =============================================================================
-- SUBTITLE COMPONENTS
-- =============================================================================

---Create a subtitle with status icon and count
---@param count number Item count
---@param item_type string Type of items (e.g., "feeds", "categories", "entries")
---@param hide_read_entries? boolean Whether read entries are hidden
---@param is_unread_only? boolean Whether showing unread only
---@return string Formatted subtitle
function ScreenUI.buildSubtitle(count, item_type, hide_read_entries, is_unread_only)
    -- Determine status icon
    local icon
    if is_unread_only then
        icon = "⊘ "
    else
        icon = hide_read_entries and "⊘ " or "◯ "
    end
    
    -- Build count text
    local count_text
    if is_unread_only then
        count_text = count .. " " .. _("unread " .. item_type)
    else
        count_text = count .. " " .. _(item_type)
    end
    
    return icon .. count_text
end

---Create a status icon based on settings
---@param hide_read_entries boolean Whether read entries are hidden
---@return string Status icon
function ScreenUI.getStatusIcon(hide_read_entries)
    return hide_read_entries and "⊘ " or "◯ "
end

---Create an entries subtitle for entries list
---@param count number Number of entries
---@param hide_read_entries boolean Whether read entries are hidden
---@param is_unread_only? boolean Whether this is unread-only view
---@return string Formatted subtitle
function ScreenUI.buildEntriesSubtitle(count, hide_read_entries, is_unread_only)
    if is_unread_only then
        return "⊘ " .. count .. " " .. _("unread entries")
    else
        local icon = ScreenUI.getStatusIcon(hide_read_entries)
        if hide_read_entries then
            return icon .. count .. " " .. _("unread entries")
        else
            return icon .. count .. " " .. _("entries")
        end
    end
end

-- =============================================================================
-- BATCH OPERATIONS
-- =============================================================================

---Convert a list of entries to menu items
---@param entries MinifluxEntry[] List of entries
---@param is_category_view? boolean Whether this is for category view
---@return table[] Menu items
function ScreenUI.entriesToMenuItems(entries, is_category_view)
    local menu_items = {}
    
    for _, entry in ipairs(entries) do
        table.insert(menu_items, ScreenUI.createEntryMenuItem(entry, is_category_view))
    end
    
    return menu_items
end

---Convert a list of feeds to menu items with counts
---@param feeds MinifluxFeed[] List of feeds
---@param feed_counters? table Feed counters (reads/unreads)
---@param entry_counts? table Accurate entry counts per feed
---@return table[] Menu items
function ScreenUI.feedsToMenuItems(feeds, feed_counters, entry_counts)
    local menu_items = {}
    
    for _, feed in ipairs(feeds) do
        local feed_id_str = tostring(feed.id)
        local read_count = feed_counters and feed_counters.reads and feed_counters.reads[feed_id_str] or 0
        local unread_count = feed_counters and feed_counters.unreads and feed_counters.unreads[feed_id_str] or 0
        
        -- Try to get accurate total count from cache, fall back to read+unread
        local total_count
        if entry_counts then
            local cache_key = "feed_" .. feed_id_str .. "_count"
            total_count = entry_counts[cache_key]
        end
        if not total_count then
            total_count = read_count + unread_count
        end
        
        local menu_item = ScreenUI.createFeedMenuItem(feed, unread_count, total_count)
        -- Add unread count for sorting
        menu_item.unread_count = unread_count
        
        table.insert(menu_items, menu_item)
    end
    
    return menu_items
end

---Convert a list of categories to menu items
---@param categories MinifluxCategory[] List of categories
---@return table[] Menu items
function ScreenUI.categoriesToMenuItems(categories)
    local menu_items = {}
    
    for _, category in ipairs(categories) do
        table.insert(menu_items, ScreenUI.createCategoryMenuItem(category))
    end
    
    return menu_items
end

-- =============================================================================
-- VALIDATION HELPERS
-- =============================================================================

---Check if entries list is empty and create appropriate items
---@param entries MinifluxEntry[] List of entries (may be empty)
---@param is_category_view? boolean Whether this is for category view
---@param is_unread_only? boolean Whether this is unread-only view
---@return table[] Menu items (entries or no-entries message)
---@return boolean has_no_entries_message Whether a no-entries message was created
function ScreenUI.processEntriesList(entries, is_category_view, is_unread_only)
    if #entries == 0 then
        return { ScreenUI.createNoEntriesItem(is_unread_only) }, true
    else
        return ScreenUI.entriesToMenuItems(entries, is_category_view), false
    end
end

---Create fallback menu items when no data is available
---@param message string Fallback message
---@return table[] Menu items with fallback message
function ScreenUI.createFallbackItems(message)
    return {
        ScreenUI.createMenuItem({
            text = message,
            action_type = "none"
        })
    }
end

return ScreenUI 