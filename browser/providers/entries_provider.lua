--[[--
Entries Provider for Miniflux Browser

Reusable provider that fetches and formats entries data for the browser.
Can handle unread entries, feed entries, and category entries based on context.

@module miniflux.browser.providers.entries_provider
--]]--

local BrowserUtils = require("browser/utils/browser_utils")
local _ = require("gettext")

---@class EntriesProvider
local EntriesProvider = {}

---Create a new entries provider
---@return EntriesProvider
function EntriesProvider:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get entries for unread view (always unread only)
---@param api MinifluxAPI API client instance
---@param settings any Settings instance
---@return boolean success, table|string result_or_error
function EntriesProvider:getUnreadEntries(api, settings)
    local options = {
        status = {"unread"}, -- Always unread only
        order = settings:getOrder(),
        direction = settings:getDirection(),
        limit = settings:getLimit(),
    }
    
    return api.entries:getEntries(options)
end

---Get entries for a specific feed
---@param api MinifluxAPI API client instance
---@param settings any Settings instance
---@param feed_id number Feed ID
---@return boolean success, table|string result_or_error
function EntriesProvider:getFeedEntries(api, settings, feed_id)
    local options = BrowserUtils.getApiOptions(settings)
    -- Add feed-specific filter
    options.feed_id = feed_id
    
    return api.feeds:getEntries(feed_id, options)
end

---Get entries for a specific category
---@param api MinifluxAPI API client instance
---@param settings any Settings instance
---@param category_id number Category ID
---@return boolean success, table|string result_or_error
function EntriesProvider:getCategoryEntries(api, settings, category_id)
    local options = BrowserUtils.getApiOptions(settings)
    -- Add category-specific filter
    options.category_id = category_id
    
    return api.categories:getEntries(category_id, options)
end

---Convert entries to menu items for browser
---@param entries MinifluxEntry[] Entries data
---@param is_category_view? boolean Whether this is for category view (shows feed title)
---@return table[] Menu items array
function EntriesProvider:toMenuItems(entries, is_category_view)
    local menu_items = {}
    
    for _, entry in ipairs(entries) do
        local entry_title = entry.title or _("Untitled Entry")
        local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
        
        -- Add status indicator
        local status_indicator = entry.status == "read" and "○ " or "● "
        
        -- Build display text
        local display_text = status_indicator .. entry_title
        if is_category_view then
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

---Create "no entries" menu item
---@param is_unread_only? boolean Whether this is for unread-only view
---@return table Menu item
function EntriesProvider:createNoEntriesItem(is_unread_only)
    local message
    if is_unread_only then
        message = _("There are no unread entries.")
    else
        message = _("There are no entries.")
    end
    
    return {
        text = message,
        mandatory = "",
        action_type = "no_action",
    }
end

---Get subtitle for entries list
---@param count number Number of entries
---@param hide_read_entries boolean Whether read entries are hidden
---@param is_unread_only? boolean Whether this is unread-only view
---@return string Formatted subtitle
function EntriesProvider:getSubtitle(count, hide_read_entries, is_unread_only)
    if is_unread_only then
        return "⊘ " .. count .. " " .. _("unread entries")
    else
        local icon = hide_read_entries and "⊘ " or "◯ "
        if hide_read_entries then
            return icon .. count .. " " .. _("unread entries")
        else
            return icon .. count .. " " .. _("entries")
        end
    end
end

return EntriesProvider 