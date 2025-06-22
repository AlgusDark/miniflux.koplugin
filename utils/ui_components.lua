--[[--
UI Components for Miniflux Browser

This module provides reusable UI components for the browser layer, including
standardized message dialogs, loading indicators, and progress tracking.

@module miniflux.browser.lib.ui_components
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UIComponents = {}

-- =============================================================================
-- MESSAGE COMPONENTS
-- =============================================================================

---Create and show a loading message with immediate display
---@param text? string Loading message text (defaults to "Loading...")
---@return InfoMessage Loading message widget for cleanup
function UIComponents.showLoadingMessage(text)
    local loading_info = InfoMessage:new({
        text = text or _("Loading..."),
    })
    UIManager:show(loading_info)
    UIManager:forceRePaint() -- Force immediate display before API call blocks
    return loading_info
end

---Close a loading message dialog
---@param loading_info InfoMessage Loading message widget to close
---@return nil
function UIComponents.closeLoadingMessage(loading_info)
    if loading_info then
        UIManager:close(loading_info)
    end
end

---Show an error message with timeout
---@param message string Error message text
---@param timeout? number Message timeout in seconds (default: 5)
---@return nil
function UIComponents.showErrorMessage(message, timeout)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = timeout or 5,
    }))
end

---Show a success message with timeout
---@param message string Success message text
---@param timeout? number Message timeout in seconds (default: 3)
---@return nil
function UIComponents.showSuccessMessage(message, timeout)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = timeout or 3,
    }))
end

---Show an info message with timeout
---@param message string Info message text
---@param timeout? number Message timeout in seconds (default: 3)
---@return nil
function UIComponents.showInfoMessage(message, timeout)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = timeout or 3,
    }))
end

---Show a warning message with timeout
---@param message string Warning message text
---@param timeout? number Message timeout in seconds (default: 4)
---@return nil
function UIComponents.showWarningMessage(message, timeout)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = timeout or 4,
    }))
end

-- =============================================================================
-- PROGRESS COMPONENTS
-- =============================================================================

---@class ProgressDialog
---@field dialog InfoMessage Current progress dialog
---@field title string Progress operation title
local ProgressDialog = {}

---Create a new progress dialog
---@param title string Title for the progress operation
---@return ProgressDialog
function ProgressDialog:new(title)
    local obj = {
        title = title,
        dialog = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Update progress dialog with new message
---@param message string Current progress message
---@param timeout? number Dialog timeout (nil for persistent)
---@return nil
function ProgressDialog:update(message, timeout)
    -- Close previous dialog if exists
    if self.dialog then
        UIManager:close(self.dialog)
    end

    -- Build full message with title
    local full_message = self.title and (self.title .. "\n\n" .. message) or message

    -- Create new progress dialog
    self.dialog = InfoMessage:new({
        text = full_message,
        timeout = timeout,
    })

    UIManager:show(self.dialog)
    UIManager:forceRePaint()
end

---Close the progress dialog
---@return nil
function ProgressDialog:close()
    if self.dialog then
        UIManager:close(self.dialog)
        self.dialog = nil
    end
end

---Create a new progress dialog
---@param title string Title for the progress operation
---@return ProgressDialog
function UIComponents.createProgressDialog(title)
    return ProgressDialog:new(title)
end

---Show a simple progress message (auto-managed)
---@param message string Progress message
---@return InfoMessage Progress dialog for manual cleanup if needed
function UIComponents.showSimpleProgress(message)
    local dialog = InfoMessage:new({
        text = message,
    })
    UIManager:show(dialog)
    UIManager:forceRePaint()
    return dialog
end

-- =============================================================================
-- SPECIALIZED MESSAGE PATTERNS
-- =============================================================================

---Show a standardized API error message
---@param operation_name string Name of the failed operation
---@param error_message string Specific error details
---@param timeout? number Message timeout in seconds (default: 5)
---@return nil
function UIComponents.showApiError(operation_name, error_message, timeout)
    local message = _("Failed to ") .. operation_name .. ": " .. tostring(error_message)
    UIComponents.showErrorMessage(message, timeout)
end

---Show a standardized operation success message
---@param operation_name string Name of the successful operation
---@param timeout? number Message timeout in seconds (default: 3)
---@return nil
function UIComponents.showOperationSuccess(operation_name, timeout)
    local message = operation_name .. _(" completed successfully")
    UIComponents.showSuccessMessage(message, timeout)
end

---Show a "no data found" message
---@param data_type string Type of data that wasn't found
---@param timeout? number Message timeout in seconds (default: 3)
---@return nil
function UIComponents.showNoDataMessage(data_type, timeout)
    local message = _("No ") .. data_type .. _(" found")
    UIComponents.showInfoMessage(message, timeout)
end

---Show a configuration required message
---@param setting_name string Name of the required setting
---@param timeout? number Message timeout in seconds (default: 4)
---@return nil
function UIComponents.showConfigurationRequired(setting_name, timeout)
    local message = _("Please configure ") .. setting_name .. _(" first")
    UIComponents.showWarningMessage(message, timeout)
end

-- =============================================================================
-- COMPOUND OPERATIONS
-- =============================================================================

---Execute an operation with loading feedback
---@param params {operation_name: string, operation_func: function, loading_message?: string, success_message?: string}
---@return boolean success, any result_or_error
function UIComponents.withLoadingFeedback(params)
    local operation_name = params.operation_name
    local operation_func = params.operation_func
    local loading_message = params.loading_message or _("Loading...")
    local success_message = params.success_message

    -- Show loading
    local loading_info = UIComponents.showLoadingMessage(loading_message)

    -- Execute operation
    local success, result = pcall(operation_func)

    -- Close loading
    UIComponents.closeLoadingMessage(loading_info)

    -- Show result feedback
    if success then
        if success_message then
            UIComponents.showSuccessMessage(success_message)
        end
        return true, result
    else
        UIComponents.showApiError(operation_name, result)
        return false, result
    end
end

---Execute multiple sequential operations with progress updates
---@param operations {name: string, func: function, loading_message: string}[]
---@param title string Overall operation title
---@return boolean success, any[] results
function UIComponents.withProgressFeedback(operations, title)
    local progress = UIComponents.createProgressDialog(title)
    local results = {}

    for i, operation in ipairs(operations) do
        -- Update progress
        local progress_message = operation.loading_message or operation.name
        progress:update(progress_message)

        -- Execute operation
        local success, result = pcall(operation.func)

        if not success then
            progress:close()
            UIComponents.showApiError(operation.name, result)
            return false, results
        end

        table.insert(results, result)
    end

    progress:close()
    return true, results
end

return UIComponents
