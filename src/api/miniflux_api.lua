local EventListener = require('ui/widget/eventlistener')

---@class MinifluxEntriesResponse
---@field entries MinifluxEntry[] Array of entries
---@field total? number Total number of entries available

---@class MinifluxFeedCategory
---@field id number Category ID
---@field title string Category title

---@class MinifluxEntryFeed
---@field id number Feed ID
---@field title string Feed title
---@field category MinifluxFeedCategory Category information

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field content? string Entry content (HTML)
---@field summary? string Entry summary/excerpt
---@field url? string Entry URL
---@field published_at? string Publication timestamp
---@field status string Entry status: "read", "unread", "removed"
---@field feed MinifluxEntryFeed Feed information

---@class MinifluxFeed
---@field id number Feed ID
---@field user_id number User ID
---@field title string Feed title
---@field site_url string Site URL
---@field feed_url string Feed URL
---@field checked_at string Last check timestamp
---@field category MinifluxFeedCategory Category information
---@field disabled boolean Whether feed is disabled
---@field parsing_error_message string Parsing error message if any

---@class MinifluxFeedCounters
---@field reads table<string, number> Read counts per feed ID
---@field unreads table<string, number> Unread counts per feed ID

---@class MinifluxCategory
---@field id number Category ID
---@field title string Category title
---@field total_unread? number Total unread entries in category

-- Domain-specific API that provides all Miniflux operations.
-- Uses the generic APIClient for HTTP communication while adding
-- Miniflux-specific endpoint knowledge and request building.
---@class MinifluxAPI : EventListener
---@field api_client APIClient Generic HTTP API client
---@field api_token string API token for authentication
---@field server_address string Server address for API calls
local MinifluxAPI = EventListener:extend({})

---Initialize the API instance with configuration
function MinifluxAPI:init()
    local APIClient = require('core/api_client')
    self.api_client = APIClient:new({
        server_address = self.server_address,
        api_token = self.api_token,
    })
end

---Handle server configuration change event
---@param args {api_token: string, server_address: string} New server configuration
function MinifluxAPI:onMinifluxServerConfigChange(args)
    self.api_token = args.api_token
    self.server_address = args.server_address

    -- Recreate APIClient with new settings
    local APIClient = require('core/api_client')
    self.api_client = APIClient:new({
        server_address = self.server_address,
        api_token = self.api_token,
    })
end

-- =============================================================================
-- ENTRIES
-- =============================================================================

---Build full URL for entries endpoint with query parameters (for caching)
---@param options? ApiOptions Query options for filtering and sorting
---@return string url Full URL with query parameters
function MinifluxAPI:buildEntriesUrl(options)
    local base_url = self.server_address .. '/v1/entries'
    if not options then
        return base_url
    end

    -- Build query string from options (similar to newsdownloader URL caching)
    local query_parts = {}

    if options.status then
        -- Handle status parameter: can be repeated for multiple statuses (Miniflux >= 2.0.24)
        -- If all statuses are requested (unread + read), omit parameter for default behavior
        local has_unread = false
        local has_read = false
        for _, status in ipairs(options.status) do
            if status == 'unread' then
                has_unread = true
            elseif status == 'read' then
                has_read = true
            end
        end

        -- Only add status parameters if not requesting all entries
        if not (has_unread and has_read and #options.status == 2) then
            for _, status in ipairs(options.status) do
                table.insert(query_parts, 'status=' .. tostring(status))
            end
        end
    end

    if options.order then
        table.insert(query_parts, 'order=' .. tostring(options.order))
    end

    if options.direction then
        table.insert(query_parts, 'direction=' .. tostring(options.direction))
    end

    if options.limit then
        table.insert(query_parts, 'limit=' .. tostring(options.limit))
    end

    if options.feed_id then
        table.insert(query_parts, 'feed_id=' .. tostring(options.feed_id))
    end

    if options.category_id then
        table.insert(query_parts, 'category_id=' .. tostring(options.category_id))
    end

    if #query_parts > 0 then
        return base_url .. '?' .. table.concat(query_parts, '&')
    end

    return base_url
end

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@param config? table Configuration including optional dialogs
---@return MinifluxEntriesResponse|nil result, Error|nil error
function MinifluxAPI:getEntries(options, config)
    config = config or {}
    return self.api_client:get('/entries', {
        query = options,
        dialogs = config.dialogs,
    })
end

---Update entry status for one or multiple entries
---@param entry_ids number|number[] Entry ID or array of entry IDs to update
---@param config? table Configuration with body containing status and dialogs
---@return table|nil result, Error|nil error
function MinifluxAPI:updateEntries(entry_ids, config)
    config = config or {}

    -- Convert single ID to array
    local ids_array = type(entry_ids) == 'table' and entry_ids or { entry_ids }

    -- Start with entry_ids
    local request_body = { entry_ids = ids_array }

    -- Merge additional properties from config.body
    if config.body then
        for key, value in pairs(config.body) do
            request_body[key] = value
        end
    end

    return self.api_client:put('/entries', {
        body = request_body,
        dialogs = config.dialogs,
    })
end

-- =============================================================================
-- FEEDS
-- =============================================================================

---Get all feeds
---@param config? table Configuration including optional dialogs
---@return MinifluxFeed[]|nil result, Error|nil error
function MinifluxAPI:getFeeds(config)
    config = config or {}
    return self.api_client:get('/feeds', config)
end

---Get feed counters (read/unread counts)
---@return MinifluxFeedCounters|nil result, Error|nil error
function MinifluxAPI:getFeedCounters()
    return self.api_client:get('/feeds/counters')
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@param config? table Configuration including optional dialogs
---@return MinifluxEntriesResponse|nil result, Error|nil error
function MinifluxAPI:getFeedEntries(feed_id, options, config)
    config = config or {}
    local endpoint = '/feeds/' .. tostring(feed_id) .. '/entries'

    return self.api_client:get(endpoint, {
        query = options,
        dialogs = config.dialogs,
    })
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function MinifluxAPI:markFeedAsRead(feed_id, config)
    config = config or {}
    local endpoint = '/feeds/' .. tostring(feed_id) .. '/mark-all-as-read'

    return self.api_client:put(endpoint, {
        dialogs = config.dialogs,
    })
end

-- =============================================================================
-- CATEGORIES
-- =============================================================================

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@param config? table Configuration with optional query, dialogs
---@return MinifluxCategory[]|nil result, Error|nil error
function MinifluxAPI:getCategories(include_counts, config)
    config = config or {}
    local query_params = {}
    if include_counts then
        query_params.counts = 'true'
    end

    return self.api_client:get('/categories', {
        query = query_params,
        dialogs = config.dialogs,
    })
end

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@param config? table Configuration including optional dialogs
---@return MinifluxEntriesResponse|nil result, Error|nil error
function MinifluxAPI:getCategoryEntries(category_id, options, config)
    config = config or {}
    local endpoint = '/categories/' .. tostring(category_id) .. '/entries'

    return self.api_client:get(endpoint, {
        query = options,
        dialogs = config.dialogs,
    })
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function MinifluxAPI:markCategoryAsRead(category_id, config)
    config = config or {}
    local endpoint = '/categories/' .. tostring(category_id) .. '/mark-all-as-read'

    return self.api_client:put(endpoint, {
        dialogs = config.dialogs,
    })
end

-- =============================================================================
-- USER INFO
-- =============================================================================

---Get current user information (useful for connection testing)
---@param config? table Configuration including optional dialogs
---@return table|nil result, Error|nil error
function MinifluxAPI:getMe(config)
    config = config or {}
    return self.api_client:get('/me', config)
end

return MinifluxAPI
