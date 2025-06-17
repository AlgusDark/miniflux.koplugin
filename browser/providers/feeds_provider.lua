--[[--
Feeds Provider for Miniflux Browser

Simple provider that fetches and formats feeds data for the browser.

@module miniflux.browser.providers.feeds_provider
--]]--

local _ = require("gettext")

---@class FeedsProvider
local FeedsProvider = {}

---Create a new feeds provider
---@return FeedsProvider
function FeedsProvider:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get feeds list
---@param api MinifluxAPI API client instance
---@return boolean success, MinifluxFeed[]|string result_or_error
function FeedsProvider:getFeeds(api)
    return api.feeds:getFeeds()
end

---Get feed counters
---@param api MinifluxAPI API client instance
---@return boolean success, FeedCounters|string result_or_error
function FeedsProvider:getCounters(api)
    return api.feeds:getCounters()
end

---Convert feeds to menu items for browser
---@param feeds MinifluxFeed[] Feeds data
---@param feed_counters? FeedCounters Feed counters (reads/unreads)
---@return table[] Menu items array
function FeedsProvider:toMenuItems(feeds, feed_counters)
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
    
    return menu_items
end

---Get subtitle for feeds list
---@param count number Number of feeds
---@param hide_read_entries boolean Whether read entries are hidden
---@return string Formatted subtitle
function FeedsProvider:getSubtitle(count, hide_read_entries)
    local icon = hide_read_entries and "⊘ " or "◯ "
    return icon .. count .. " " .. _("feeds")
end

return FeedsProvider 