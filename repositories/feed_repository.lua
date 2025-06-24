--[[--
Feed Repository - Data Access Layer

Handles all feed-related data access and API interactions.
Provides a clean interface for feed data without UI concerns.

@module miniflux.browser.repositories.feed_repository
--]]

---@class FeedsWithCountersResult
---@field feeds table[] Array of feeds
---@field counters table Feed counters with reads/unreads maps

---@class FeedRepository
---@field api MinifluxAPI API client instance
---@field settings MinifluxSettings Settings instance
local FeedRepository = {}

---Create a new FeedRepository instance
---@param api MinifluxAPI The API client instance
---@param settings MinifluxSettings The settings instance
---@return FeedRepository
function FeedRepository:new(api, settings)
    local obj = {
        api = api,
        settings = settings,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- FEED DATA ACCESS
-- =============================================================================

---Get all feeds
---@param config? table Configuration with optional dialogs
---@return table[]|nil feeds Array of feeds or nil on error
---@return string|nil error Error message if failed
function FeedRepository:getAll(config)
    local success, feeds = self.api.feeds:getAll(config)
    if not success then
        return nil, feeds
    end

    return feeds, nil
end

---Get feeds with their read/unread counters
---@param config? table Configuration with optional dialogs
---@return FeedsWithCountersResult|nil result Result containing feeds and counters, or nil on error
---@return string|nil error Error message if failed
function FeedRepository:getAllWithCounters(config)
    -- Get feeds first
    local feeds, error_msg = self:getAll(config)
    if not feeds then
        return nil, error_msg
    end

    -- Get counters (optional - continue without if it fails)
    local counters_success, counters = self.api.feeds:getCounters()
    if not counters_success then
        counters = { reads = {}, unreads = {} } -- Empty counters on failure
    end

    return {
        feeds = feeds,
        counters = counters
    }, nil
end

---Get feeds count for initialization
---@return number count Count of feeds (0 if failed)
function FeedRepository:getCount()
    local feeds, error_msg = self:getAll()
    if not feeds then
        return 0 -- Continue with 0 feeds instead of failing
    end

    return #feeds
end

return FeedRepository
