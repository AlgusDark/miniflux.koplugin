--[[--
View Utilities for Miniflux Browser

Shared utilities for view formatting and common view operations.

@module miniflux.browser.views.view_utils
--]]

local _ = require('gettext')

local ViewUtils = {}

---Build subtitle for content views
---@param config {count: number, hide_read?: boolean, is_unread_only?: boolean, is_local_only?: boolean, item_type?: string}
---@return string Formatted subtitle
function ViewUtils.buildSubtitle(config)
    local count = config.count
    local hide_read = config.hide_read
    local is_unread_only = config.is_unread_only
    local is_local_only = config.is_local_only
    local item_type = config.item_type

    if is_unread_only then
        return '⊘ ' .. count .. ' ' .. _('unread entries')
    end

    if is_local_only then
        return '⌂ ' .. count .. ' ' .. _('local entries')
    end

    local icon = hide_read and '⊘ ' or '◯ '

    if item_type == 'entries' then
        if hide_read then
            return icon .. count .. ' ' .. _('unread entries')
        else
            return icon .. count .. ' ' .. _('entries')
        end
    elseif item_type == 'feeds' then
        return icon .. count .. ' ' .. _('feeds')
    elseif item_type == 'categories' then
        return icon .. count .. ' ' .. _('categories')
    else
        return icon .. count .. ' ' .. _('items')
    end
end

---Sort items by unread priority (unread first, then by count desc, then alphabetically)
---@param items table[] Array of items with unread_count property
---@return nil Sorts in place
function ViewUtils.sortByUnreadPriority(items)
    table.sort(items, function(a, b)
        if a.unread_count > 0 and b.unread_count == 0 then
            return true
        end
        if a.unread_count == 0 and b.unread_count > 0 then
            return false
        end
        if a.unread_count ~= b.unread_count then
            return a.unread_count > b.unread_count
        end
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
        return string.format('(%d/%d)', unread_count, total_count)
    else
        return ''
    end
end

---@class StatusIndicatorOptions
---@field settings? MinifluxSettings Settings instance
---@field force_unread_indicator? boolean Force unread indicator (●) regardless of setting

---Add status indicator to title for consistent display across all views
---@param title string Base title text
---@param opts StatusIndicatorOptions Options for status indicator
---@return string title_with_indicator
function ViewUtils.addStatusIndicator(title, opts)
    local settings = opts.settings
    local force_unread_indicator = opts.force_unread_indicator

    if force_unread_indicator then
        return title .. ' ●'
    end

    -- Safety check for settings
    if not settings then
        return title .. ' ◯' -- Default to show all entries indicator
    end

    local hide_read = settings.hide_read_entries
    local status_indicator = hide_read and '⊘' or '◯'
    return title .. ' ' .. status_indicator
end

---Build filter mode subtitle for displaying current filter setting
---@param settings? MinifluxSettings Settings instance
---@return string filter_mode_subtitle
function ViewUtils.buildFilterModeSubtitle(settings)
    if not settings then
        return '◯ Show all entries' -- Default to show all entries
    end

    local hide_read = settings.hide_read_entries
    return hide_read and '⊘ Showing unread entries only' or '◯ Show all entries'
end

return ViewUtils
