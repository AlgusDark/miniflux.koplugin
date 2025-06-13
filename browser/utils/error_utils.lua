--[[--
Error Handling Utilities

This utility module provides centralized error handling patterns for API calls
and other operations, eliminating code duplication across the browser modules.

@module miniflux.browser.utils.error_utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ErrorUtils = {}

---Handle a complete API call lifecycle with loading, error handling, and validation
---@param params {browser: BaseBrowser, operation_name: string, api_call_func: function, loading_message?: string, data_name?: string, skip_validation?: boolean}
---@return any|nil Result if successful, nil if error occurred
function ErrorUtils.handleApiCall(params)
    local browser = params.browser
    local operation_name = params.operation_name
    local api_call_func = params.api_call_func
    local loading_message = params.loading_message or _("Loading...")
    local data_name = params.data_name or operation_name
    local skip_validation = params.skip_validation or false
    
    -- Show loading message
    local loading_info = browser:showLoadingMessage(loading_message)
    
    -- Execute API call with error protection
    local success, result
    local ok, err = pcall(function()
        success, result = api_call_func()
    end)
    
    -- Close loading message
    browser:closeLoadingMessage(loading_info)
    
    -- Handle network/execution errors
    if not ok then
        browser:showErrorMessage(_("Failed to ") .. operation_name .. ": " .. tostring(err))
        return nil
    end
    
    -- Handle API errors
    if not browser:handleApiError(success, result, _("Failed to ") .. operation_name) then
        return nil
    end
    
    -- Handle data validation unless skipped
    if not skip_validation and not browser:validateData(result, data_name) then
        return nil
    end
    
    return result
end

---Handle a simple API call with basic error handling
---@param browser BaseBrowser Browser instance for UI feedback
---@param operation_name string Human-readable operation name
---@param api_call_func function Function that makes the API call
---@return any|nil Result if successful, nil if error occurred
function ErrorUtils.simpleApiCall(browser, operation_name, api_call_func)
    return ErrorUtils.handleApiCall({
        browser = browser,
        operation_name = operation_name,
        api_call_func = api_call_func
    })
end

---Show standardized error message
---@param browser BaseBrowser Browser instance
---@param operation_name string Operation that failed
---@param error_message string Specific error message
---@param timeout? number Message timeout in seconds
---@return nil
function ErrorUtils.showError(browser, operation_name, error_message, timeout)
    local message = _("Failed to ") .. operation_name .. ": " .. tostring(error_message)
    browser:showErrorMessage(message, timeout)
end

---Show standardized success message
---@param browser BaseBrowser Browser instance
---@param operation_name string Operation that succeeded
---@param timeout? number Message timeout in seconds
---@return nil
function ErrorUtils.showSuccess(browser, operation_name, timeout)
    local message = operation_name .. _(" completed successfully")
    browser:showInfoMessage(message, timeout or 2)
end

---Wrap a function call with error handling
---@param func function Function to wrap
---@param error_handler? function Optional custom error handler
---@return boolean success, any result_or_error
function ErrorUtils.safeCall(func, error_handler)
    local ok, result = pcall(func)
    
    if not ok then
        if error_handler then
            error_handler(result)
        end
        return false, result
    end
    
    return true, result
end

---Create a retry wrapper for unreliable operations
---@param func function Function to retry
---@param max_retries? number Maximum number of retries (default: 3)
---@param delay? number Delay between retries in seconds (default: 1)
---@return boolean success, any result_or_error
function ErrorUtils.withRetry(func, max_retries, delay)
    max_retries = max_retries or 3
    delay = delay or 1
    
    local last_error
    for attempt = 1, max_retries do
        local ok, result = pcall(func)
        
        if ok then
            return true, result
        end
        
        last_error = result
        
        -- Don't delay after the last attempt
        if attempt < max_retries then
            -- Simple delay using os.time (Lua 5.1 compatible)
            local start_time = os.time()
            while os.time() - start_time < delay do
                -- Busy wait (not ideal but simple and compatible)
            end
        end
    end
    
    return false, last_error
end

return ErrorUtils 