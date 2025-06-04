--[[--
Miniflux API client module

@module koplugin.miniflux.api
--]]--

local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local _ = require("gettext")

local MinifluxAPI = {}

function MinifluxAPI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

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

function MinifluxAPI:makeRequest(method, endpoint, body)
    if not self.server_address or not self.api_token then
        return false, _("Server address and API token must be configured")
    end
    
    local url = self.base_url .. endpoint
    local headers = {
        ["X-Auth-Token"] = self.api_token,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "KOReader-Miniflux/1.0"
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
    local timeout, maxtime = 15, 30  -- 15 second connection timeout, 30 second max time
    socketutil:set_timeout(timeout, maxtime)
    
    local result, status_code, response_headers
    local network_success = pcall(function()
        result, status_code, response_headers = request_func{
            url = url,
            method = method,
            headers = headers,
            source = ltn12.source.string(request_body),
            sink = socketutil.table_sink(response_body),  -- Use socketutil sink for timeout support
            protocol = "tlsv1_2"
        }
    end)
    
    -- Reset timeout after request
    socketutil:reset_timeout()
    
    if not network_success then
        logger.warn("Miniflux API network error")
        return false, _("Network error occurred")
    end
    
    if not result then
        logger.warn("Miniflux API request failed:", status_code)
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
                logger.warn("Failed to parse JSON response:", response_text)
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

function MinifluxAPI:testConnection()
    logger.info("Testing Miniflux connection to:", self.server_address)
    local success, result = self:makeRequest("GET", "/me")
    
    if success then
        logger.info("Connection test successful. User:", result.username)
        return true, _("Connection successful! Logged in as: ") .. result.username
    else
        logger.warn("Connection test failed:", result)
        return false, result
    end
end

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
            for _, status in ipairs(options.status) do
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
    logger.info("Fetching entries from:", endpoint)
    
    return self:makeRequest("GET", endpoint)
end

function MinifluxAPI:markEntryAsRead(entry_id)
    local body = {
        entry_ids = {entry_id},
        status = "read"
    }
    
    return self:makeRequest("PUT", "/entries", body)
end

function MinifluxAPI:markEntryAsUnread(entry_id)
    local body = {
        entry_ids = {entry_id},
        status = "unread"
    }
    
    return self:makeRequest("PUT", "/entries", body)
end

function MinifluxAPI:toggleBookmark(entry_id)
    return self:makeRequest("PUT", "/entries/" .. tostring(entry_id) .. "/bookmark")
end

function MinifluxAPI:getFeeds()
    logger.info("Fetching feeds")
    return self:makeRequest("GET", "/feeds")
end

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
            for _, status in ipairs(options.status) do
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
    
    -- COMPREHENSIVE DEBUGGING
    logger.info("=== MINIFLUX API CALL DEBUG ===")
    logger.info("Feed ID:", feed_id)
    logger.info("Full endpoint:", endpoint)
    logger.info("Raw options received:")
    for k, v in pairs(options) do
        if k == "status" and type(v) == "table" then
            logger.info("  " .. k .. " = {" .. table.concat(v, ", ") .. "}")
        else
            logger.info("  " .. k .. " = " .. tostring(v))
        end
    end
    logger.info("Query parameters:")
    for i, param in ipairs(params) do
        logger.info("  " .. i .. ": " .. param)
    end
    logger.info("================================")
    
    local success, result = self:makeRequest("GET", endpoint)
    
    -- DEBUG THE RESPONSE
    if success and result then
        logger.info("=== MINIFLUX API RESPONSE DEBUG ===")
        logger.info("Success: true")
        if result.entries then
            logger.info("Total entries returned:", #result.entries)
            
            -- Count read vs unread
            local unread_count = 0
            local read_count = 0
            for _, entry in ipairs(result.entries) do
                if entry.status == "unread" then
                    unread_count = unread_count + 1
                elseif entry.status == "read" then
                    read_count = read_count + 1
                end
            end
            
            logger.info("Unread entries:", unread_count)
            logger.info("Read entries:", read_count)
            logger.info("Total count field:", tostring(result.total))
            
            -- Show first few entries for debugging
            logger.info("First 3 entries (for debugging):")
            for i = 1, math.min(3, #result.entries) do
                local entry = result.entries[i]
                logger.info("  " .. i .. ": " .. tostring(entry.title) .. " [status: " .. tostring(entry.status) .. ", id: " .. tostring(entry.id) .. "]")
            end
        else
            logger.info("No entries field in response")
        end
        
        -- Show other response fields
        logger.info("Other response fields:")
        for k, v in pairs(result) do
            if k ~= "entries" then
                logger.info("  " .. k .. " = " .. tostring(v))
            end
        end
        logger.info("=====================================")
    else
        logger.warn("=== MINIFLUX API RESPONSE DEBUG ===")
        logger.warn("Success: false")
        logger.warn("Error:", tostring(result))
        logger.warn("=====================================")
    end
    
    return success, result
end

function MinifluxAPI:getFeedCounters()
    logger.info("Fetching feed counters")
    return self:makeRequest("GET", "/feeds/counters")
end

function MinifluxAPI:getCategories(include_counts)
    local endpoint = "/categories"
    if include_counts then
        endpoint = endpoint .. "?counts=true"
    end
    logger.info("Fetching categories from:", endpoint)
    return self:makeRequest("GET", endpoint)
end

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
            for _, status in ipairs(options.status) do
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
    logger.info("Fetching entries for category", category_id, "from:", endpoint)
    
    return self:makeRequest("GET", endpoint)
end

function MinifluxAPI:getEntry(entry_id)
    local endpoint = "/entries/" .. tostring(entry_id)
    logger.info("Fetching single entry:", endpoint)
    
    return self:makeRequest("GET", endpoint)
end

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
            for _, status in ipairs(options.status) do
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
    logger.info("Fetching previous entry:", endpoint)
    
    return self:makeRequest("GET", endpoint)
end

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
            for _, status in ipairs(options.status) do
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
    logger.info("Fetching next entry:", endpoint)
    
    return self:makeRequest("GET", endpoint)
end

return MinifluxAPI 