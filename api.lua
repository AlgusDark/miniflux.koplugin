--[[--
Miniflux API client module

@module koplugin.miniflux.api
--]]
--

local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")

---@alias HttpMethod "GET"|"POST"|"PUT"|"DELETE"
---@alias EntryStatus "read"|"unread"|"removed"
---@alias SortOrder "id"|"status"|"published_at"|"category_title"|"category_id"
---@alias SortDirection "asc"|"desc"

---@class MinifluxEntry
---@field id number Entry ID
---@field title string Entry title
---@field url string Entry URL
---@field content string Entry content
---@field summary string Entry summary
---@field status EntryStatus Entry read status
---@field starred boolean Whether entry is bookmarked
---@field published_at string Publication timestamp
---@field created_at string Creation timestamp
---@field feed MinifluxFeed Associated feed information

---@class MinifluxFeed
---@field id number Feed ID
---@field title string Feed title
---@field site_url string Feed website URL
---@field feed_url string Feed RSS URL
---@field category MinifluxCategory Feed category

---@class MinifluxCategory
---@field id number Category ID
---@field title string Category title
---@field total_unread number Number of unread entries in category

---@class MinifluxUser
---@field id number User ID
---@field username string Username
---@field is_admin boolean Whether user is admin

---@class ApiOptions
---@field limit? number Maximum number of entries to fetch
---@field order? SortOrder Sort order field
---@field direction? SortDirection Sort direction
---@field status? EntryStatus[]|EntryStatus Entry status filter

---@class EntriesResponse
---@field entries MinifluxEntry[] Array of entries
---@field total number Total number of entries matching criteria

---@class FeedCounters
---@field reads table<string, number> Read counts by feed ID
---@field unreads table<string, number> Unread counts by feed ID

---@class MinifluxAPI
---@field server_address string Server base URL
---@field api_token string API authentication token
---@field base_url string Complete API base URL
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
function MinifluxAPI:makeRequest(method, endpoint, body)
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
function MinifluxAPI:testConnection()
    local success, result = self:makeRequest("GET", "/me")

    if success then
        return true, _("Connection successful! Logged in as: ") .. result.username
    else
        return false, result
    end
end

---Get entries from the server
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getEntries(options)
    options = options or {}

    local params = {}

    if options.limit then
        table.insert(params, "limit=" .. tostring(options.limit))
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    if options.status then
        if type(options.status) == "table" then
            -- Handle multiple status values
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        else
            -- Handle single status value (backward compatibility)
            table.insert(params, "status=" .. options.status)
        end
    end

    local query_string = ""
    if #params > 0 then
        query_string = "?" .. table.concat(params, "&")
    end

    local endpoint = "/entries" .. query_string

    return self:makeRequest("GET", endpoint)
end

---Mark an entry as read
---@param entry_id number The entry ID to mark as read
---@return boolean success, any result_or_error
function MinifluxAPI:markEntryAsRead(entry_id)
    local body = {
        entry_ids = { entry_id },
        status = "read",
    }

    return self:makeRequest("PUT", "/entries", body)
end

---Mark an entry as unread
---@param entry_id number The entry ID to mark as unread
---@return boolean success, any result_or_error
function MinifluxAPI:markEntryAsUnread(entry_id)
    local body = {
        entry_ids = { entry_id },
        status = "unread",
    }

    return self:makeRequest("PUT", "/entries", body)
end

---Toggle bookmark status of an entry
---@param entry_id number The entry ID to toggle bookmark
---@return boolean success, any result_or_error
function MinifluxAPI:toggleBookmark(entry_id)
    return self:makeRequest("PUT", "/entries/" .. tostring(entry_id) .. "/bookmark")
end

---Get all feeds
---@return boolean success, MinifluxFeed[]|string result_or_error
function MinifluxAPI:getFeeds()
    return self:makeRequest("GET", "/feeds")
end

---Get entries for a specific feed
---@param feed_id number The feed ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getFeedEntries(feed_id, options)
    options = options or {}

    local params = {}

    if options.limit then
        table.insert(params, "limit=" .. tostring(options.limit))
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    if options.status then
        if type(options.status) == "table" then
            -- Handle multiple status values
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        else
            -- Handle single status value (backward compatibility)
            table.insert(params, "status=" .. options.status)
        end
    end

    local query_string = ""
    if #params > 0 then
        query_string = "?" .. table.concat(params, "&")
    end

    local endpoint = "/feeds/" .. tostring(feed_id) .. "/entries" .. query_string

    return self:makeRequest("GET", endpoint)
end

---Get feed counters (read/unread counts)
---@return boolean success, FeedCounters|string result_or_error
function MinifluxAPI:getFeedCounters()
    return self:makeRequest("GET", "/feeds/counters")
end

---Get all categories
---@param include_counts? boolean Whether to include entry counts
---@return boolean success, MinifluxCategory[]|string result_or_error
function MinifluxAPI:getCategories(include_counts)
    local endpoint = "/categories"
    if include_counts then
        endpoint = endpoint .. "?counts=true"
    end
    return self:makeRequest("GET", endpoint)
end

---Get entries for a specific category
---@param category_id number The category ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getCategoryEntries(category_id, options)
    options = options or {}

    local params = {}

    if options.limit then
        table.insert(params, "limit=" .. tostring(options.limit))
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    if options.status then
        if type(options.status) == "table" then
            -- Handle multiple status values
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        else
            -- Handle single status value (backward compatibility)
            table.insert(params, "status=" .. options.status)
        end
    end

    local query_string = ""
    if #params > 0 then
        query_string = "?" .. table.concat(params, "&")
    end

    local endpoint = "/categories/" .. tostring(category_id) .. "/entries" .. query_string

    return self:makeRequest("GET", endpoint)
end

---Get a single entry by ID
---@param entry_id number The entry ID
---@return boolean success, MinifluxEntry|string result_or_error
function MinifluxAPI:getEntry(entry_id)
    local endpoint = "/entries/" .. tostring(entry_id)

    return self:makeRequest("GET", endpoint)
end

---Get the entry before a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getPreviousEntry(entry_id, options)
    options = options or {}

    local params = {}

    -- Add before_entry_id to get entries before this one
    table.insert(params, "before_entry_id=" .. tostring(entry_id))

    -- We only want 1 entry (the immediate previous)
    table.insert(params, "limit=1")

    -- Add other filter options if provided
    if options.status then
        if type(options.status) == "table" then
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        else
            table.insert(params, "status=" .. options.status)
        end
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    local query_string = ""
    if #params > 0 then
        query_string = "?" .. table.concat(params, "&")
    end

    local endpoint = "/entries" .. query_string

    return self:makeRequest("GET", endpoint)
end

---Get the entry after a given entry ID
---@param entry_id number The reference entry ID
---@param options? ApiOptions Query options for filtering and sorting
---@return boolean success, EntriesResponse|string result_or_error
function MinifluxAPI:getNextEntry(entry_id, options)
    options = options or {}

    local params = {}

    -- Add after_entry_id to get entries after this one
    table.insert(params, "after_entry_id=" .. tostring(entry_id))

    -- We only want 1 entry (the immediate next)
    table.insert(params, "limit=1")

    -- Add other filter options if provided
    if options.status then
        if type(options.status) == "table" then
            local status_array = options.status ---@type EntryStatus[]
            for _, status in ipairs(status_array) do
                table.insert(params, "status=" .. status)
            end
        else
            table.insert(params, "status=" .. options.status)
        end
    end

    if options.order then
        table.insert(params, "order=" .. options.order)
    end

    if options.direction then
        table.insert(params, "direction=" .. options.direction)
    end

    local query_string = ""
    if #params > 0 then
        query_string = "?" .. table.concat(params, "&")
    end

    local endpoint = "/entries" .. query_string

    return self:makeRequest("GET", endpoint)
end

return MinifluxAPI

