--[[--
Entry Repository - Data Access Layer

Handles all entry-related data access and API interactions.
Provides a clean interface for entry data without UI concerns.

@module miniflux.browser.repositories.entry_repository
--]]

---@class EntryRepository
---@field api MinifluxAPI API client instance
---@field settings MinifluxSettings Settings instance
local EntryRepository = {}

---Create a new EntryRepository instance
---@param api MinifluxAPI The API client instance
---@param settings MinifluxSettings The settings instance
---@return EntryRepository
function EntryRepository:new(api, settings)
    local obj = {
        api = api,
        settings = settings,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- API OPTIONS BUILDING
-- =============================================================================

---Build API options based on current settings
---@return table API options for entry queries
function EntryRepository:getApiOptions()
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
-- ENTRY DATA ACCESS
-- =============================================================================

---Get unread entries
---@return table[]|nil Array of unread entries or nil on error
---@return string|nil Error message if failed
function EntryRepository:getUnread()
    local options = {
        status = { "unread" }, -- Always unread only for this view
        order = self.settings.order,
        direction = self.settings.direction,
        limit = self.settings.limit,
    }

    local success, result = self.api.entries:getEntries(options)
    if not success then
        return nil, result
    end

    return result.entries or {}
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@return table[]|nil Array of feed entries or nil on error
---@return string|nil Error message if failed
function EntryRepository:getByFeed(feed_id)
    local options = self:getApiOptions()
    options.feed_id = feed_id

    local success, result = self.api.feeds:getEntries(feed_id, options)
    if not success then
        return nil, result
    end

    return result.entries or {}
end

---Get entries for a specific category
---@param category_id number The category ID
---@return table[]|nil Array of category entries or nil on error
---@return string|nil Error message if failed
function EntryRepository:getByCategory(category_id)
    local options = self:getApiOptions()
    options.category_id = category_id

    local success, result = self.api.categories:getEntries(category_id, options)
    if not success then
        return nil, result
    end

    return result.entries or {}
end

---Get unread count for initialization
---@return number|nil Unread count or nil on error
---@return string|nil Error message if failed
function EntryRepository:getUnreadCount()
    local options = {
        order = self.settings.order,
        direction = self.settings.direction,
        limit = 1, -- We only need one entry to get the total count
        status = { "unread" }, -- Only unread for count
    }

    local success, result = self.api.entries:getEntries(options)
    if not success then
        return nil, result
    end

    return (result and result.total) and result.total or 0
end

return EntryRepository
