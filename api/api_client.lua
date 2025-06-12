--[[--
Miniflux API Client

This is the main API coordinator that provides a unified interface to all
Miniflux API operations. It acts as a facade that composes specialized API modules
and maintains backward compatibility with the existing API interface.

@module koplugin.miniflux.api.api_client
--]]--

local BaseClient = require("api/base_client")
local EntriesAPI = require("api/entries_api")
local FeedsAPI = require("api/feeds_api")
local CategoriesAPI = require("api/categories_api")

---@class MinifluxAPI
---@field server_address string Server base URL
---@field api_token string API authentication token
---@field base_url string Complete API base URL
---@field client BaseClient Base HTTP client instance
---@field entries EntriesAPI Entries API module
---@field feeds FeedsAPI Feeds API module
---@field categories CategoriesAPI Categories API module
local MinifluxAPI = {}

---Create a new API instance
---@param o? table Optional initialization table
---@return MinifluxAPI
function MinifluxAPI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the API client with server details
---@param server_address string The Miniflux server address
---@param api_token string The API authentication token
---@return MinifluxAPI self for method chaining
function MinifluxAPI:init(server_address, api_token)
    -- Store configuration for backward compatibility
    self.server_address = server_address
    self.api_token = api_token
    self.base_url = server_address .. "/v1"

    -- Remove trailing slash if present
    if self.server_address:sub(-1) == "/" then
        self.server_address = self.server_address:sub(1, -2)
        self.base_url = self.server_address .. "/v1"
    end

    -- Initialize base client
    self.client = BaseClient:new()
    self.client:init(server_address, api_token)

    -- Initialize specialized API modules
    self.entries = EntriesAPI:new()
    self.entries:init(self.client)

    self.feeds = FeedsAPI:new()
    self.feeds:init(self.client)

    self.categories = CategoriesAPI:new()
    self.categories:init(self.client)

    return self
end

-- =============================================================================
-- BACKWARD COMPATIBILITY LAYER
-- These methods maintain the exact same interface as the original api.lua
-- =============================================================================

---Make an HTTP request to the API (backward compatibility)
---@param method HttpMethod HTTP method to use
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@return boolean success, any result_or_error
function MinifluxAPI:makeRequest(method, endpoint, body)
    return self.client:makeRequest(method, endpoint, body)
end

---Test connection to the Miniflux server (backward compatibility)
---@return boolean success, string message
function MinifluxAPI:testConnection()
    return self.client:testConnection()
end

-- =============================================================================
-- ENTRIES API - Delegate to EntriesAPI module
-- =============================================================================

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getEntries(options)
    return self.entries:getEntries(options)
end

---Get a single entry by ID
---@param entry_id number The entry ID
---@return boolean success, MinifluxEntry|string result_or_error
function MinifluxAPI:getEntry(entry_id)
    return self.entries:getEntry(entry_id)
end

---Mark an entry as read
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function MinifluxAPI:markEntryAsRead(entry_id)
    return self.entries:markEntryAsRead(entry_id)
end

---Mark an entry as unread
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function MinifluxAPI:markEntryAsUnread(entry_id)
    return self.entries:markEntryAsUnread(entry_id)
end

---Toggle bookmark status of an entry
---@param entry_id number The entry ID to toggle bookmark
---@return boolean success, any result_or_error
function MinifluxAPI:toggleBookmark(entry_id)
    return self.entries:toggleBookmark(entry_id)
end

---Get the entry before a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getPreviousEntry(entry_id, options)
    return self.entries:getPreviousEntry(entry_id, options)
end

---Get the entry after a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getNextEntry(entry_id, options)
    return self.entries:getNextEntry(entry_id, options)
end

-- =============================================================================
-- FEEDS API - Delegate to FeedsAPI module
-- =============================================================================

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function MinifluxAPI:getFeeds()
    return self.feeds:getFeeds()
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getFeedEntries(feed_id, options)
    return self.feeds:getFeedEntries(feed_id, options)
end

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function MinifluxAPI:getFeedCounters()
    return self.feeds:getFeedCounters()
end

-- =============================================================================
-- CATEGORIES API - Delegate to CategoriesAPI module
-- =============================================================================

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function MinifluxAPI:getCategories(include_counts)
    return self.categories:getCategories(include_counts)
end

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getCategoryEntries(category_id, options)
    return self.categories:getCategoryEntries(category_id, options)
end

-- =============================================================================
-- EXTENDED API - Additional convenience methods not in original API
-- =============================================================================

---Get unread entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getUnreadEntries(options)
    return self.entries:getUnreadEntries(options)
end

---Get read entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getReadEntries(options)
    return self.entries:getReadEntries(options)
end

---Get starred entries (convenience method)
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getStarredEntries(options)
    return self.entries:getStarredEntries(options)
end

---Mark multiple entries as read
---@param entry_ids number[] Array of entry IDs to mark as read
---@return boolean success, any result_or_error
function MinifluxAPI:markEntriesAsRead(entry_ids)
    return self.entries:markEntriesAsRead(entry_ids)
end

---Mark multiple entries as unread
---@param entry_ids number[] Array of entry IDs to mark as unread
---@return boolean success, any result_or_error
function MinifluxAPI:markEntriesAsUnread(entry_ids)
    return self.entries:markEntriesAsUnread(entry_ids)
end

---Get a specific feed by ID
---@param feed_id number The feed ID
---@return boolean success, MinifluxFeed|string result_or_error
function MinifluxAPI:getFeed(feed_id)
    return self.feeds:getFeed(feed_id)
end

---Get a specific category by ID
---@param category_id number The category ID
---@return boolean success, MinifluxCategory|string result_or_error
function MinifluxAPI:getCategory(category_id)
    return self.categories:getCategory(category_id)
end

-- =============================================================================
-- UTILITY METHODS
-- =============================================================================

---Check if the API client is properly configured
---@return boolean True if server address and API token are set
function MinifluxAPI:isConfigured()
    return self.client and self.client:isConfigured()
end

---Get the base URL for API requests
---@return string The base API URL
function MinifluxAPI:getBaseUrl()
    return self.client and self.client:getBaseUrl() or ""
end

---Get the server address
---@return string The server address
function MinifluxAPI:getServerAddress()
    return self.client and self.client:getServerAddress() or ""
end

---Get the API token (masked for security)
---@return string Masked API token
function MinifluxAPI:getApiTokenMasked()
    return self.client and self.client:getApiTokenMasked() or ""
end

return MinifluxAPI 