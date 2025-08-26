local http = require('socket.http')
local JSON = require('json')
local ltn12 = require('ltn12')
local socket = require('socket')
local socketutil = require('socketutil')
local _ = require('gettext')
local Files = require('shared/files')
local util = require('util')
local Error = require('shared/error')
local logger = require('logger')

-- This is the main Http client that handles HTTP communication.
--It provides convenient HTTP methods
---@class HttpClient
---@field server_address string Server address for API calls
---@field api_token string API token for authentication
local HttpClient = {}

---@class HttpClientConfig
---@field server_address string Server address for API calls
---@field api_token string API token for authentication

---@class HttpClientOptions<Body, QueryParams>: {body?: Body, query?: QueryParams}
--@field body? Body Request body
--@field query? QueryParams Query parameters

---Create a new API instance
---@param config HttpClientConfig Configuration table with server address and API token
---@return HttpClient
function HttpClient:new(config)
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    instance.server_address = config.server_address
    instance.api_token = config.api_token

    return instance
end

---@class QueryParam
---@field key string|number Parameter key
---@field value string|number|table Parameter value

---Add a URL-encoded query parameter to the query parts array
---@param query_parts table Array to append the parameter to
---@param query_param QueryParam Parameter to add
local function addQueryParam(query_parts, query_param)
    local key = query_param.key
    local value = query_param.value
    local encoded_key = util.urlEncode(tostring(key))
    local encoded_value = util.urlEncode(tostring(value))
    table.insert(query_parts, encoded_key .. '=' .. encoded_value)
end

---Build error message from HTTP response code and body
---@param code number HTTP status code
---@param response_text string Response body text
---@return string Error message
local function buildErrorMessage(code, response_text)
    local api_error_message = nil
    if response_text and response_text ~= '' then
        local success, error_data = pcall(JSON.decode, response_text)
        if success and error_data and error_data.error_message then
            api_error_message = error_data.error_message
        end
    end

    if code == 400 then
        return api_error_message or _('Bad request')
    elseif code == 401 then
        return api_error_message or _('Unauthorized - please check your API token')
    elseif code == 403 then
        return api_error_message or _('Forbidden - access denied')
    elseif code == 500 then
        return api_error_message or _('Internal server error')
    else
        return api_error_message or (_('HTTP error: ') .. tostring(code))
    end
end

---Make an HTTP request to the API
---@param method "GET"|"POST"|"PUT"|"DELETE" HTTP method to use
---@param endpoint string API endpoint path
---@param config? HttpClientOptions<table, QueryParam[]> Configuration including body and query
---@return table|nil result, Error|nil error
function HttpClient:makeRequest(method, endpoint, config)
    config = config or {}

    local server_address = self.server_address
    local api_token = self.api_token

    if not server_address or not api_token or server_address == '' or api_token == '' then
        return nil, Error.new(_('Server address and API token must be configured'))
    end

    local base_url = Files.rtrimSlashes(server_address) .. '/v1'
    local url = base_url .. endpoint

    if config.query and next(config.query) then
        local query_parts = {}
        for key, value in pairs(config.query) do
            if type(value) == 'table' then
                for _, v in ipairs(value) do
                    -- Arrays values are encoded as multiple parameters. E.g. {status = {'read', 'unread'}} -> ?status=read&status=unread
                    addQueryParam(query_parts, { key = key, value = v })
                end
            else
                -- Single values are encoded as a single parameter. E.g. {status = 'read'} -> ?status=read
                addQueryParam(query_parts, { key = key, value = value })
            end
        end
        url = url .. '?' .. table.concat(query_parts, '&')
    end

    local headers = {
        ['X-Auth-Token'] = api_token,
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'KOReader/1.0',
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
        headers['Content-Length'] = tostring(#request_body)
    end

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, resp_headers, _status = socket.skip(1, http.request(request))
    logger.dbg('[HttpClient]', method, url, '->', code or 'no response')
    socketutil:reset_timeout()

    if resp_headers == nil then
        local error_message = _('Network error occurred')
        logger.err('[HttpClient] Network error:', method, url)
        return nil, Error.new(error_message)
    end

    local response_text = table.concat(response_body)

    if code == 200 or code == 201 or code == 204 then
        if response_text and response_text ~= '' then
            local success, data = pcall(JSON.decode, response_text)
            if success then
                return data, nil
            else
                local error_message = _('Invalid JSON response from server')
                return nil, Error.new(error_message)
            end
        else
            return {}, nil
        end
    end

    local error_message = buildErrorMessage(code, response_text)
    logger.warn('[HttpClient] API error:', method, url, '->', code, error_message)
    return nil, Error.new(error_message)
end

---Make a GET request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional query
---@return table|nil result, Error|nil error
function HttpClient:get(endpoint, config)
    config = config or {}
    return self:makeRequest('GET', endpoint, config)
end

---Make a POST request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional body, query
---@return table|nil result, Error|nil error
function HttpClient:post(endpoint, config)
    config = config or {}
    return self:makeRequest('POST', endpoint, config)
end

---Make a PUT request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional body, query
---@return table|nil result, Error|nil error
function HttpClient:put(endpoint, config)
    config = config or {}
    return self:makeRequest('PUT', endpoint, config)
end

---Make a DELETE request
---@param endpoint string API endpoint path
---@param config? table Configuration with optional query
---@return table|nil result, Error|nil error
function HttpClient:delete(endpoint, config)
    config = config or {}
    return self:makeRequest('DELETE', endpoint, config)
end

return HttpClient
