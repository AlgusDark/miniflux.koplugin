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
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local Files = require("utils/files")
local util = require("util")
local Notification = require("utils/notification")

-- No timeout constants needed - handled by Notification utility

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

---@class ApiDialogConfig
---@field loading? {text?: string, timeout?: number|nil} Loading notification (timeout=nil for manual close)
---@field error? {text?: string, timeout?: number|nil} Error notification (defaults to 5s)
---@field success? {text?: string, timeout?: number|nil} Success notification (defaults to 2s)

---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortDirection "asc"|"desc"

---@class ApiOptions
---@field limit? number Maximum number of entries to return
---@field order? "id"|"status"|"published_at"|"category_title"|"category_id" Field to sort by
---@field direction? SortDirection Sort direction
---@field status? EntryStatus[] Entry status filter
---@field category_id? number Filter by category ID
---@field feed_id? number Filter by feed ID
---@field published_before? number Filter entries published before this timestamp
---@field published_after? number Filter entries published after this timestamp

---@class APIBody
---@field status? EntryStatus Entry status to update

---@class APIClientConfig
---@field body? APIBody Request body data
---@field query? ApiOptions Query parameters
---@field dialogs? ApiDialogConfig Dialog configuration for loading/error/success messages

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

---Add a URL-encoded query parameter to the query parts array
---@param query_parts table Array to append the parameter to
---@param key string Parameter key
---@param value string|number Parameter value
local function addQueryParam(query_parts, key, value)
    local encoded_key = util.urlEncode(tostring(key))
    local encoded_value = util.urlEncode(tostring(value))
    table.insert(query_parts, encoded_key .. "=" .. encoded_value)
end

---Build error message from HTTP response code and body
---@param code number HTTP status code
---@param response_text string Response body text
---@return string Error message
local function buildErrorMessage(code, response_text)
    -- Try to extract error message from JSON response first (all error responses should follow this format)
    local api_error_message = nil
    if response_text and response_text ~= "" then
        local success, error_data = pcall(JSON.decode, response_text)
        if success and error_data and error_data.error_message then
            api_error_message = error_data.error_message
        end
    end

    -- Return API error message if available, otherwise use appropriate fallback
    if code == 400 then
        return api_error_message or _("Bad request")
    elseif code == 401 then
        return api_error_message or _("Unauthorized - please check your API token")
    elseif code == 403 then
        return api_error_message or _("Forbidden - access denied")
    elseif code == 500 then
        return api_error_message or _("Internal server error")
    else
        return api_error_message or (_("HTTP error: ") .. tostring(code))
    end
end

-- =============================================================================
-- PRIMITIVE HTTP CLIENT
-- =============================================================================

---Make an HTTP request to the API with optional dialog support
---@param method "GET"|"POST"|"PUT"|"DELETE" HTTP method to use
---@param endpoint string API endpoint path
---@param config? APIClientConfig Configuration including body, query, and dialogs
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:makeRequest(method, endpoint, config)
    config = config or {}
    local dialogs = config.dialogs

    -- Get fresh configuration values (VALIDATION FIRST)
    local server_address = self.getServerAddress()
    local api_token = self.getAPIToken()

    if not server_address or not api_token or
        server_address == "" or api_token == "" then
        -- Show error dialog if requested (no loading was shown yet)
        if dialogs and dialogs.error then
            local error_text = dialogs.error.text or _("Server address and API token must be configured")
            Notification:error({
                text = error_text,
                timeout = dialogs.error.timeout
            })
        end
        return false, _("Server address and API token must be configured")
    end

    -- Handle loading dialog (AFTER validation passes)
    local loading_notification
    if dialogs and dialogs.loading and dialogs.loading.text then
        loading_notification = Notification:info({
            text = dialogs.loading.text,
            timeout = dialogs.loading.timeout
        })
    end

    local base_url = Files.rtrimSlashes(server_address) .. "/v1"
    local url = base_url .. endpoint

    -- Build query string from config.query
    if config.query and next(config.query) then
        local query_parts = {}
        for key, value in pairs(config.query) do
            if type(value) == "table" then
                -- Handle array values (like status filters)
                for _, v in ipairs(value) do
                    addQueryParam(query_parts, key, v)
                end
            else
                addQueryParam(query_parts, key, value)
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

    if config.body then
        local request_body = JSON.encode(config.body)
        request.source = ltn12.source.string(request_body)
        headers["Content-Length"] = tostring(#request_body)
    end

    logger.dbg("MinifluxAPI:makeRequest:", method, url)

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- Close loading dialog
    if loading_notification then
        loading_notification:close()
    end

    -- Check for network errors first
    if resp_headers == nil then
        logger.err("MinifluxAPI: network error", status or code)
        local error_message = _("Network error occurred")
        if dialogs and dialogs.error then
            local error_text = dialogs.error.text or error_message
            Notification:error({
                text = error_text,
                timeout = dialogs.error.timeout
            })
        end
        return false, error_message
    end

    local response_text = table.concat(response_body)

    -- Handle successful responses
    if code == 200 or code == 201 or code == 204 then
        -- Show success message if provided
        if dialogs and dialogs.success and dialogs.success.text then
            Notification:success({
                text = dialogs.success.text,
                timeout = dialogs.success.timeout
            })
        end

        if response_text and response_text ~= "" then
            local success, data = pcall(JSON.decode, response_text)
            if success then
                return true, data
            else
                logger.err("MinifluxAPI: invalid JSON response", response_text)
                local error_message = _("Invalid JSON response from server")
                if dialogs and dialogs.error then
                    local error_text = dialogs.error.text or error_message
                    Notification:error({
                        text = error_text,
                        timeout = dialogs.error.timeout
                    })
                end
                return false, error_message
            end
        else
            return true, {}
        end
    end

    -- Handle error responses
    logger.err("MinifluxAPI: HTTP error", status or code, resp_headers)
    local error_message = buildErrorMessage(code, response_text)

    if dialogs and dialogs.error then
        local error_text = dialogs.error.text or error_message
        Notification:error({
            text = error_text,
            timeout = dialogs.error.timeout
        })
    end

    return false, error_message
end

-- =============================================================================
-- HTTP METHODS
-- =============================================================================

---Make a GET request
---@param endpoint string API endpoint path
---@param config? APIClientConfig Configuration with optional query, dialogs
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:get(endpoint, config)
    config = config or {}
    return self:makeRequest("GET", endpoint, config)
end

---Make a POST request
---@param endpoint string API endpoint path
---@param config? APIClientConfig Configuration with optional body, query, dialogs
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:post(endpoint, config)
    config = config or {}
    return self:makeRequest("POST", endpoint, config)
end

---Make a PUT request
---@param endpoint string API endpoint path
---@param config? APIClientConfig Configuration with optional body, query, dialogs
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:put(endpoint, config)
    config = config or {}
    return self:makeRequest("PUT", endpoint, config)
end

---Make a DELETE request
---@param endpoint string API endpoint path
---@param config? APIClientConfig Configuration with optional query, dialogs
---@return boolean success True if request succeeded
---@return table|string result_or_error Decoded JSON table on success, error string on failure
function MinifluxAPI:delete(endpoint, config)
    config = config or {}
    return self:makeRequest("DELETE", endpoint, config)
end

return MinifluxAPI
