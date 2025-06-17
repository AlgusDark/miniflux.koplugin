--[[--
Error Handling Utilities

This utility module provides centralized error handling patterns for API calls
and other operations, eliminating code duplication across the browser modules.

@module miniflux.browser.utils.error_utils
--]]--

local UIComponents = require("browser/lib/ui_components")
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
    local loading_info = UIComponents.showLoadingMessage(loading_message)
    
    -- Execute API call with error protection
    local success, result
    local ok, err = pcall(function()
        success, result = api_call_func()
    end)
    
    -- Close loading message
    UIComponents.closeLoadingMessage(loading_info)
    
    -- Handle network/execution errors
    if not ok then
        UIComponents.showApiError(operation_name, err)
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



return ErrorUtils 