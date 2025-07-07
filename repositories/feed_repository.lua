---@class MinifluxFeedsWithCountersResult
---@field feeds MinifluxFeed[] Array of feeds
---@field counters MinifluxFeedCounters Feed counters with reads/unreads maps

-- **Feed Repository** - Data Access Layer
--
-- Handles all feed-related data access and API interactions.
-- Provides a clean interface for feed data without UI concerns.
---@class FeedRepository
---@field miniflux_api MinifluxAPI Miniflux API instance
---@field settings MinifluxSettings Settings instance
local FeedRepository = {}

---Create a new FeedRepository instance
---@param deps {miniflux_api: MinifluxAPI, settings: MinifluxSettings} Dependencies table
---@return FeedRepository
function FeedRepository:new(deps)
    local obj = {
        miniflux_api = deps.miniflux_api,
        settings = deps.settings,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Get all feeds
---@param config? table Configuration with optional dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function FeedRepository:getAll(config)
    local feeds, err = self.miniflux_api:getFeeds(config)
    if err then
        return nil, err
    end
    ---@cast feeds -nil

    return feeds, nil
end

---Get feeds with their read/unread counters
---@param config? table Configuration with optional dialogs
---@return MinifluxFeedsWithCountersResult|nil result, Error|nil error
function FeedRepository:getAllWithCounters(config)
    -- Get feeds first
    local feeds, err = self:getAll(config)
    if err then
        return nil, err
    end

    -- Get counters (optional - continue without if it fails)
    local counters, counters_err = self.miniflux_api:getFeedCounters()
    if counters_err then
        counters = { reads = {}, unreads = {} } -- Empty counters on failure
    end

    return {
        feeds = feeds,
        counters = counters
    }, nil
end

---Get feeds count for initialization
---@param config? table Configuration with optional dialogs
---@return number count Count of feeds (0 if failed)
function FeedRepository:getCount(config)
    local feeds, err = self:getAll(config)
    if err then
        return 0 -- Continue with 0 feeds instead of failing
    end

    return #feeds
end

return FeedRepository
