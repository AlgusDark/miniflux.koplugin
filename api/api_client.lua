--[[--
Miniflux API Client

This is the main API client that handles HTTP communication and coordinates
with specialized API modules. It provides convenient HTTP methods and manages
the connection to the Miniflux server.

@module koplugin.miniflux.api.api_client
--]]

local http = require("socket.http")
local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")
local logger = require("logger")
local utils = require("utils/utils")
local util = require("util")

-- Load specialized API modules
local Entries = require("api/entries")
local Feeds = require("api/feeds")
local Categories = require("api/categories")

---@class MinifluxAPI
---@field getServerAddress function Function to get server address
---@field getAPIToken function Function to get API token
---@field entries Entries Entry operations module
---@field feeds Feeds Feed operations module
---@field categories Categories Category operations module
local MinifluxAPI = {}

---@class MinifluxConfig
---@field getServerAddress fun(): string Server base URL
---@field getAPIToken fun(): string API authentication token

---Create a new API instance
---@param config MinifluxConfig Configuration table with getter functions
---@return MinifluxAPI
function MinifluxAPI:new(config)
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    -- Store getter functions
    instance.getServerAddress = config.getServerAddress
    instance.getAPIToken = config.getAPIToken

    -- Create module instances
    instance.entries = Entries:new(instance)
    instance.feeds = Feeds:new(instance)
    instance.categories = Categories:new(instance)

    return instance
end

-- =============================================================================
-- PRIMITIVE HTTP CLIENT
-- =============================================================================

---Make an HTTP request to the API
---@param method "GET"|"POST"|"PUT"|"DELETE" HTTP method to use
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@param params? table Query parameters to append to URL
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:makeRequest(method, endpoint, body, params)
    -- Get fresh configuration values
    local server_address = self.getServerAddress()
    local api_token = self.getAPIToken()

    if not server_address or not api_token or
        server_address == "" or api_token == "" then
        return false, _("Server address and API token must be configured")
    end

    local base_url = utils.rtrim_slashes(server_address) .. "/v1"
    local url = base_url .. endpoint

    -- Build query string from params
    if params and next(params) then
        local query_parts = {}
        for key, value in pairs(params) do
            if type(value) == "table" then
                -- Handle array values (like status filters)
                for _, v in ipairs(value) do
                    local encoded_key = util.urlEncode(tostring(key))
                    local encoded_value = util.urlEncode(tostring(v))
                    table.insert(query_parts, encoded_key .. "=" .. encoded_value)
                end
            else
                local encoded_key = util.urlEncode(tostring(key))
                local encoded_value = util.urlEncode(tostring(value))
                table.insert(query_parts, encoded_key .. "=" .. encoded_value)
            end
        end
        url = url .. "?" .. table.concat(query_parts, "&")
    end

    local headers = {
        ["X-Auth-Token"] = api_token,
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
---@param config? table Configuration with optional query params
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:get(endpoint, config)
    config = config or {}
    return self:makeRequest("GET", endpoint, nil, config.query)
end

---Make a POST request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional body and query params
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:post(endpoint, config)
    config = config or {}
    return self:makeRequest("POST", endpoint, config.body, config.query)
end

---Make a PUT request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional body and query params
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:put(endpoint, config)
    config = config or {}
    return self:makeRequest("PUT", endpoint, config.body, config.query)
end

---Make a DELETE request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional query params
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:delete(endpoint, config)
    config = config or {}
    return self:makeRequest("DELETE", endpoint, nil, config.query)
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
