--[[--
View Utilities for Miniflux Browser

Shared utilities for view formatting and common view operations.

@module miniflux.browser.views.view_utils
--]]

local _ = require("gettext")

local ViewUtils = {}

---Build subtitle for content views
---@param config {count: number, hide_read?: boolean, is_unread_only?: boolean, item_type?: string}
---@return string Formatted subtitle
function ViewUtils.buildSubtitle(config)
    local count = config.count
    local hide_read = config.hide_read
    local is_unread_only = config.is_unread_only
    local item_type = config.item_type

    if is_unread_only then
        return "⊘ " .. count .. " " .. _("unread entries")
    end

    local icon = hide_read and "⊘ " or "◯ "

    if item_type == "entries" then
        if hide_read then
            return icon .. count .. " " .. _("unread entries")
        else
            return icon .. count .. " " .. _("entries")
        end
    elseif item_type == "feeds" then
        return icon .. count .. " " .. _("feeds")
    elseif item_type == "categories" then
        return icon .. count .. " " .. _("categories")
    else
        return icon .. count .. " " .. _("items")
    end
end

---Sort items by unread priority (unread first, then by count desc, then alphabetically)
---@param items table[] Array of items with unread_count property
---@return nil Sorts in place
function ViewUtils.sortByUnreadPriority(items)
    table.sort(items, function(a, b)
        if a.unread_count > 0 and b.unread_count == 0 then return true end
        if a.unread_count == 0 and b.unread_count > 0 then return false end
        if a.unread_count ~= b.unread_count then return a.unread_count > b.unread_count end
        return a.text:lower() < b.text:lower()
    end)
end

---Format count display for feeds/categories
---@param config {read_count: number, unread_count: number}
---@return string Formatted count like "(5/10)" or ""
function ViewUtils.formatCountDisplay(config)
    local read_count = config.read_count or 0
    local unread_count = config.unread_count or 0
    local total_count = read_count + unread_count

    if total_count > 0 then
        return string.format("(%d/%d)", unread_count, total_count)
    else
        return ""
    end
end

return ViewUtils
