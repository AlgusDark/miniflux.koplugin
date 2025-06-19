--[[--
Miniflux API Client

This is the main API client that handles HTTP communication and coordinates
with specialized API modules. It provides convenient HTTP methods and manages
the connection to the Miniflux server.

@module koplugin.miniflux.api.api_client
--]] --

local http = require("socket.http")
local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")
local logger = require("logger")
local utils = require("utils/utils")

-- Load specialized API modules
local Entries = require("api/entries")
local Feeds = require("api/feeds")
local Categories = require("api/categories")

---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortDirection "asc"|"desc"

---@class MinifluxConfig
---@field server_address string The Miniflux server address
---@field api_token string The API authentication token

---@class ApiOptions
---@field limit? number Maximum number of entries to return
---@field order? "id"|"status"|"published_at"|"category_title"|"category_id" Field to sort by
---@field direction? SortDirection Sort direction
---@field status? EntryStatus[] Entry status filter
---@field category_id? number Filter by category ID
---@field feed_id? number Filter by feed ID
---@field starred? boolean Filter by starred status
---@field published_before? number Filter entries published before this timestamp
---@field published_after? number Filter entries published after this timestamp

---@class EntriesResponse
---@field entries MinifluxEntry[] Array of entries
---@field total? number Total number of entries available

---@class FeedCounters
---@field reads table<string, number> Read counts per feed ID
---@field unreads table<string, number> Unread counts per feed ID

---@class MinifluxCategory
---@field id number Category ID
---@field title string Category title
---@field total_unread? number Total unread entries in category

---@class MinifluxFeed
---@field id number Feed ID
---@field title string Feed title
---@field category_id? number Category ID this feed belongs to

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field content? string Entry content (HTML)
---@field summary? string Entry summary/excerpt
---@field url? string Entry URL
---@field published_at? string Publication timestamp
---@field status string Entry status: "read", "unread", "removed"
---@field starred boolean Whether entry is bookmarked/starred
---@field feed? MinifluxFeed Feed information

---@class MinifluxAPI
---@field server_address string Server base URL
---@field api_token string API authentication token
---@field base_url string Complete API base URL
---@field entries Entries Entry operations module
---@field feeds Feeds Feed operations module
---@field categories Categories Category operations module
local MinifluxAPI = {}

---Create a new API instance
---@param config MinifluxConfig Configuration table with server_address and api_token
---@return MinifluxAPI
function MinifluxAPI:new(config)
    config = config or {}

    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    -- Use updateConfig to set configuration (eliminates duplication)
    instance:updateConfig(config)

    -- Create module instances
    instance.entries = Entries:new(instance)
    instance.feeds = Feeds:new(instance)
    instance.categories = Categories:new(instance)

    return instance
end

-- =============================================================================
-- CONFIGURATION MANAGEMENT
-- =============================================================================

---Update the API configuration with new server address and/or API token
---@param config MinifluxConfig Configuration table with server_address and/or api_token
---@return nil
function MinifluxAPI:updateConfig(config)
    config = config or {}

    -- Update server address if provided
    if config.server_address then
        self.server_address = utils.rtrim_slashes(config.server_address)
        self.base_url = self.server_address .. "/v1"
    end

    -- Update API token if provided
    if config.api_token then
        self.api_token = config.api_token
    end
end

-- =============================================================================
-- PRIMITIVE HTTP CLIENT
-- =============================================================================

---Make an HTTP request to the API
---@param method "GET"|"POST"|"PUT"|"DELETE" HTTP method to use
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@return boolean success, any result_or_error
function MinifluxAPI:makeRequest(method, endpoint, body)
    if not self.server_address or not self.api_token or
        self.server_address == "" or self.api_token == "" then
        return false, _("Server address and API token must be configured")
    end

    local url = self.base_url .. endpoint
    local headers = {
        ["X-Auth-Token"] = self.api_token,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "KOReader-Miniflux/1.0",
    }

    local response_body = {}
    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = socketutil.table_sink(response_body),
    }

    if body then
        local request_body = JSON.encode(body)
        request.source = ltn12.source.string(request_body)
        headers["Content-Length"] = tostring(#request_body)
    end

    logger.dbg("MinifluxAPI:makeRequest:", method, url)

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- Check for network errors first
    if resp_headers == nil then
        logger.err("MinifluxAPI: network error", status or code)
        return false, _("Network error occurred")
    end

    local response_text = table.concat(response_body)

    -- Handle successful responses
    if code == 200 or code == 201 or code == 204 then
        if response_text and response_text ~= "" then
            local success, data = pcall(JSON.decode, response_text)
            if success then
                return true, data
            else
                logger.err("MinifluxAPI: invalid JSON response", response_text)
                return false, _("Invalid JSON response from server")
            end
        else
            return true, {}
        end
    end

    -- Handle error responses
    logger.err("MinifluxAPI: HTTP error", status or code, resp_headers)

    if code == 401 then
        return false, _("Unauthorized - please check your API token")
    elseif code == 403 then
        return false, _("Forbidden - access denied")
    elseif code == 400 then
        local error_msg = _("Bad request")
        if response_text and response_text ~= "" then
            local success, error_data = pcall(JSON.decode, response_text)
            if success and error_data.error_message then
                error_msg = error_data.error_message
            end
        end
        return false, error_msg
    elseif code == 500 then
        return false, _("Server error")
    else
        return false, _("Unexpected response: ") .. tostring(code)
    end
end

-- =============================================================================
-- HTTP METHODS
-- =============================================================================

---Make a GET request
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function MinifluxAPI:get(endpoint)
    return self:makeRequest("GET", endpoint)
end

---Make a POST request
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@return boolean success, any result_or_error
function MinifluxAPI:post(endpoint, body)
    return self:makeRequest("POST", endpoint, body)
end

---Make a PUT request
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@return boolean success, any result_or_error
function MinifluxAPI:put(endpoint, body)
    return self:makeRequest("PUT", endpoint, body)
end

---Make a DELETE request
---@param endpoint string API endpoint path
---@return boolean success, any result_or_error
function MinifluxAPI:delete(endpoint)
    return self:makeRequest("DELETE", endpoint)
end

-- =============================================================================
-- CONNECTION TESTING
-- =============================================================================

---Test connection to the Miniflux server
---@return boolean success, string message
function MinifluxAPI:testConnection()
    local success, result = self:get("/me")
    if success then
        return true, _("Connection successful! Logged in as: ") .. result.username
    else
        return false, result
    end
end

return MinifluxAPI
