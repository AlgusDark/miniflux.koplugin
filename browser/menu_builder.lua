--[[--
Menu Builder for Miniflux Browser

This module handles menu item creation and data formatting for the browser.
Fetches data from API and transforms it into menu structures for display.

@module miniflux.browser.menu_builder
--]] --

local UIComponents = require("utils/ui_components")
local _ = require("gettext")

---@class MenuBuilder
---@field api MinifluxAPI
---@field settings MinifluxSettings
local MenuBuilder = {}

---Create a new MenuBuilder instance
---@param api MinifluxAPI The API client instance
---@param settings MinifluxSettings The settings instance
---@return MenuBuilder
function MenuBuilder:new(api, settings)
    local obj = {
        api = api,
        settings = settings
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- API OPTIONS BUILDING
-- =============================================================================

function MenuBuilder:getApiOptions()
    local options = {
        limit = self.settings.limit,
        order = self.settings.order,
        direction = self.settings.direction,
    }

    -- Server-side filtering based on settings
    local hide_read_entries = self.settings.hide_read_entries
    if hide_read_entries then
        options.status = { "unread" }
    else
        options.status = { "unread", "read" }
    end

    return options
end

-- =============================================================================
-- DATA FETCHING METHODS
-- =============================================================================

function MenuBuilder:getUnreadEntries()
    local options = {
        status = { "unread" }, -- Always unread only for this view
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
    }

    local success, result = self.api.entries:getEntries(options)
    if not success then
        UIComponents.showErrorMessage(_("Failed to fetch unread entries: ") .. tostring(result))
        return nil
    end

    return result.entries or {}
end

function MenuBuilder:getFeedsWithCounters()
    -- Get feeds
    local success, feeds = self.api.feeds:getAll()
    if not success then
        UIComponents.showErrorMessage(_("Failed to fetch feeds: ") .. tostring(feeds))
        return nil
    end

    -- Get counters (optional)
    local counters_success, counters = self.api.feeds:getCounters()
    if not counters_success then
        counters = { reads = {}, unreads = {} } -- Empty counters on failure
    end

    return feeds, counters
end

function MenuBuilder:getCategories()
    local success, categories = self.api.categories:getAll(true) -- include counts
    if not success then
        UIComponents.showErrorMessage(_("Failed to fetch categories: ") .. tostring(categories))
        return nil
    end

    return categories
end

function MenuBuilder:getFeedEntries(feed_id)
    local options = self:getApiOptions()
    options.feed_id = feed_id

    local success, result = self.api.feeds:getEntries(feed_id, options)
    if not success then
        UIComponents.showErrorMessage(_("Failed to fetch feed entries: ") .. tostring(result))
        return nil
    end

    return result.entries or {}
end

function MenuBuilder:getCategoryEntries(category_id)
    local options = self:getApiOptions()
    options.category_id = category_id

    local success, result = self.api.categories:getEntries(category_id, options)
    if not success then
        UIComponents.showErrorMessage(_("Failed to fetch category entries: ") .. tostring(result))
        return nil
    end

    return result.entries or {}
end

-- =============================================================================
-- MENU ITEM BUILDING METHODS
-- =============================================================================

function MenuBuilder:entriesToMenuItems(entries, show_feed_names)
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

function MenuBuilder:feedsToMenuItems(feeds, feed_counters)
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

function MenuBuilder:categoriesToMenuItems(categories)
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

function MenuBuilder:sortByUnreadCount(items)
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

function MenuBuilder:getUnreadCountFromItem(item)
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

function MenuBuilder:getTitleFromItem(item)
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

return MenuBuilder
