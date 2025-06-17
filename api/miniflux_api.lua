--[[--
Miniflux API Client

This is the main API client that handles HTTP communication and coordinates
with specialized API modules. It consolidates the functionality from base_client
and api_client into a single, more maintainable class.

@module koplugin.miniflux.api.miniflux_api
--]]--

local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local _ = require("gettext")

---@alias HttpMethod "GET"|"POST"|"PUT"|"DELETE"
---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortOrder "id"|"status"|"published_at"|"category_title"|"category_id"
---@alias SortDirection "asc"|"desc"

---@class ApiOptions
---@field limit? number Maximum number of entries to return
---@field order? SortOrder Field to sort by
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
---@param config table Configuration table with server_address and api_token
---@param config.server_address string The Miniflux server address
---@param config.api_token string The API authentication token
---@return MinifluxAPI
function MinifluxAPI:new(config)
    config = config or {}
    
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    -- Initialize with server details if provided
    if config.server_address and config.api_token then
        o.server_address = config.server_address
        o.api_token = config.api_token
        o.base_url = config.server_address .. "/v1"

        -- Remove trailing slash if present
        if o.server_address:sub(-1) == "/" then
            o.server_address = o.server_address:sub(1, -2)
            o.base_url = o.server_address .. "/v1"
        end

        -- Initialize specialized modules
        o:_initializeModules()
    end
    
    return o
end

---Initialize the specialized API modules
---@private
function MinifluxAPI:_initializeModules()
    -- Only initialize if not already done
    if self.entries then
        return
    end
    
    -- Load modules on demand to avoid circular dependencies
    local Entries = require("api/entries")
    local Feeds = require("api/feeds") 
    local Categories = require("api/categories")
    
    self.entries = Entries:new(self)
    self.feeds = Feeds:new(self)
    self.categories = Categories:new(self)
end

-- =============================================================================
-- HTTP CLIENT FUNCTIONALITY (Consolidated from base_client)
-- =============================================================================

---Make an HTTP request to the API
---@param method HttpMethod HTTP method to use
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

    local request_body = ""
    if body then
        request_body = json.encode(body)
        headers["Content-Length"] = tostring(#request_body)
    end

    local response_body = {}
    local request_func = http.request

    -- Use HTTPS if URL starts with https
    if url:match("^https://") then
        request_func = https.request
    end

    -- Set timeouts to prevent hanging requests
    local timeout, maxtime = 15, 30
    socketutil:set_timeout(timeout, maxtime)

    local result, status_code, response_headers
    local network_success = pcall(function()
        result, status_code, response_headers = request_func({
            url = url,
            method = method,
            headers = headers,
            source = ltn12.source.string(request_body),
            sink = socketutil.table_sink(response_body),
            protocol = "tlsv1_2",
        })
    end)

    -- Reset timeout after request
    socketutil:reset_timeout()

    if not network_success then
        return false, _("Network error occurred")
    end

    if not result then
        if status_code == socketutil.TIMEOUT_CODE then
            return false, _("Request timed out")
        elseif status_code == socketutil.SSL_HANDSHAKE_CODE then
            return false, _("SSL handshake failed")
        else
            return false, _("Network request failed: ") .. tostring(status_code)
        end
    end

    local response_text = table.concat(response_body)

    -- Handle different status codes
    if status_code == 200 or status_code == 201 or status_code == 204 then
        if response_text and response_text ~= "" then
            local success, data = pcall(json.decode, response_text)
            if success then
                return true, data
            else
                return false, _("Invalid JSON response from server")
            end
        else
            return true, {}
        end
    elseif status_code == 401 then
        return false, _("Unauthorized - please check your API token")
    elseif status_code == 403 then
        return false, _("Forbidden - access denied")
    elseif status_code == 400 then
        local error_msg = _("Bad request")
        if response_text and response_text ~= "" then
            local success, error_data = pcall(json.decode, response_text)
            if success and error_data.error_message then
                error_msg = error_data.error_message
            end
        end
        return false, error_msg
    elseif status_code == 500 then
        return false, _("Server error")
    else
        return false, _("Unexpected response: ") .. tostring(status_code)
    end
end

---Test connection to the Miniflux server
---@return boolean success, string message
function MinifluxAPI:testConnection()
    local success, result = self:makeRequest("GET", "/me")
    if success then
        return true, _("Connection successful! Logged in as: ") .. result.username
    else
        return false, result
    end
end

-- =============================================================================
-- UTILITY METHODS
-- =============================================================================

---Check if the API client is properly configured
---@return boolean True if server address and API token are set
function MinifluxAPI:isConfigured()
    return self.server_address ~= nil and self.api_token ~= nil and
           self.server_address ~= "" and self.api_token ~= ""
end

---Get the base URL for API requests
---@return string The base API URL
function MinifluxAPI:getBaseUrl()
    return self.base_url or ""
end

---Get the server address
---@return string The server address
function MinifluxAPI:getServerAddress()
    return self.server_address or ""
end

---Get the API token (masked for security)
---@return string Masked API token
function MinifluxAPI:getApiTokenMasked()
    if not self.api_token or self.api_token == "" then
        return ""
    end
    
    local token = self.api_token
    if #token > 8 then
        return token:sub(1, 4) .. "****" .. token:sub(-4)
    else
        return "****"
    end
end



return MinifluxAPI 