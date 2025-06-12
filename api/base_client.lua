--[[--
Base HTTP Client for Miniflux API

This module provides the foundational HTTP communication functionality for all
Miniflux API operations. It handles authentication, request/response processing,
error handling, and connection testing.

@module koplugin.miniflux.api.base_client
--]]--

local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local _ = require("gettext")

---@class BaseClient
---@field server_address string Server base URL
---@field api_token string API authentication token
---@field base_url string Complete API base URL
local BaseClient = {}

---Create a new base client instance
---@param o? table Optional initialization table
---@return BaseClient
function BaseClient:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Initialize the HTTP client with server details
---@param server_address string The Miniflux server address
---@param api_token string The API authentication token
---@return BaseClient self for method chaining
function BaseClient:init(server_address, api_token)
    self.server_address = server_address
    self.api_token = api_token
    self.base_url = server_address .. "/v1"

    -- Remove trailing slash if present
    if self.server_address:sub(-1) == "/" then
        self.server_address = self.server_address:sub(1, -2)
        self.base_url = self.server_address .. "/v1"
    end

    return self
end

---Make an HTTP request to the API
---@param method HttpMethod HTTP method to use
---@param endpoint string API endpoint path
---@param body? table Request body to encode as JSON
---@return boolean success, any result_or_error
function BaseClient:makeRequest(method, endpoint, body)
    if not self.server_address or not self.api_token then
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
    local timeout, maxtime = 15, 30 -- 15 second connection timeout, 30 second max time
    socketutil:set_timeout(timeout, maxtime)

    local result, status_code, response_headers
    local network_success = pcall(function()
        result, status_code, response_headers = request_func({
            url = url,
            method = method,
            headers = headers,
            source = ltn12.source.string(request_body),
            sink = socketutil.table_sink(response_body), -- Use socketutil sink for timeout support
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
function BaseClient:testConnection()
    local success, result = self:makeRequest("GET", "/me")

    if success then
        return true, _("Connection successful! Logged in as: ") .. result.username
    else
        return false, result
    end
end

---Check if the client is properly configured
---@return boolean True if server address and API token are set
function BaseClient:isConfigured()
    return self.server_address ~= nil and self.api_token ~= nil and
           self.server_address ~= "" and self.api_token ~= ""
end

---Get the base URL for API requests
---@return string The base API URL
function BaseClient:getBaseUrl()
    return self.base_url or ""
end

---Get the server address
---@return string The server address
function BaseClient:getServerAddress()
    return self.server_address or ""
end

---Get the API token (masked for security)
---@return string Masked API token
function BaseClient:getApiTokenMasked()
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

return BaseClient 