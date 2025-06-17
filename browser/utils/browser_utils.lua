--[[--
General Browser Utilities for Miniflux Browser

This utility module provides general browser functionality like API options building
and common browser operations.

@module miniflux.browser.utils.browser_utils
--]]--

local _ = require("gettext")

local BrowserUtils = {}

---Get API options based on current settings
---@param settings MinifluxSettings Settings instance
---@return ApiOptions Options for API calls
function BrowserUtils.getApiOptions(settings)
    local options = {
        limit = settings:getLimit(),
        order = settings:getOrder(),
        direction = settings:getDirection(),
    }
    
    -- Use server-side filtering based on settings
    local hide_read_entries = settings:getHideReadEntries()
    if hide_read_entries then
        -- Only fetch unread entries
        options.status = {"unread"}
    else
        -- Fetch both read and unread entries, but never "removed" ones
        options.status = {"unread", "read"}
    end
    
    return options
end

---Convert table to string representation for serialization
---@param tbl table Table to convert
---@param indent? number Current indentation level
---@return string String representation of table
function BrowserUtils.tableToString(tbl, indent)
    indent = indent or 0
    local result = {}
    local spaces = string.rep("  ", indent)
    
    table.insert(result, "{\n")
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
        local value
        if type(v) == "string" then
            value = string.format('"%s"', v:gsub('"', '\\"'))
        elseif type(v) == "table" then
            value = BrowserUtils.tableToString(v, indent + 1)
        else
            value = tostring(v)
        end
        table.insert(result, string.format("%s  [%s] = %s,\n", spaces, key, value))
    end
    table.insert(result, spaces .. "}")
    
    return table.concat(result)
end

---Create a no entries found message item
---@param hide_read_entries boolean Whether read entries are hidden
---@return BrowserMenuItem No entries message item
function BrowserUtils.createNoEntriesItem(hide_read_entries)
    return {
        text = hide_read_entries and _("There are no unread entries.") or _("There are no entries."),
        mandatory = "",
        action_type = "no_action",
    }
end

---Build subtitle with status icon and count
---@param hide_read_entries boolean Whether read entries are hidden
---@param count number Number of items
---@param item_type string Type of items ("entries", "feeds", "categories")
---@param is_unread_view? boolean Whether this is specifically an unread entries view
---@return string Formatted subtitle
function BrowserUtils.buildSubtitle(hide_read_entries, count, item_type, is_unread_view)
    -- For unread entries view, always show the "show only unread" icon (⊘)
    if is_unread_view then
        return "⊘ " .. count .. " " .. _("unread entries")
    end
    
    -- For other views, follow normal logic
    local eye_icon = hide_read_entries and "⊘ " or "◯ "
    
    if item_type == "entries" then
        if hide_read_entries then
            return eye_icon .. count .. " " .. _("unread entries")
        else
            return eye_icon .. count .. " " .. _("entries")
        end
    else
        return eye_icon .. count .. " " .. _(item_type)
    end
end

---Add status indicator to entry title
---@param entry MinifluxEntry Entry to get title for
---@param include_feed_name? boolean Whether to include feed name
---@return string Formatted entry title with status indicator
function BrowserUtils.formatEntryTitle(entry, include_feed_name)
    local entry_title = entry.title or _("Untitled Entry")
    
    -- Add read/unread status indicator
    local status_indicator = ""
    if entry.status == "read" then
        status_indicator = "○ "  -- Open circle for read entries
    else
        status_indicator = "● "  -- Filled circle for unread entries
    end
    
    local display_text = status_indicator .. entry_title
    
    if include_feed_name then
        local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
        display_text = display_text .. " (" .. feed_title .. ")"
    end
    
    return display_text
end



return BrowserUtils 