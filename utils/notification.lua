--[[--
Notification Utility

Simple notification wrapper around InfoMessage with consistent timeout handling.
Always returns instance for consistent API.

@module koplugin.miniflux.utils.notification
--]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

-- Default timeout constants
local DEFAULT_TIMEOUTS = {
    SUCCESS = 2,
    ERROR = 5,
    WARNING = 3,
}

---@class NotificationInstance
---@field widget table The underlying InfoMessage widget
---@field is_open boolean Whether notification is currently shown
local NotificationInstance = {}

function NotificationInstance:new(widget)
    local instance = {
        widget = widget,
        is_open = true
    }
    setmetatable(instance, self)
    self.__index = self

    UIManager:forceRePaint()
    return instance
end

function NotificationInstance:close()
    if self.is_open and self.widget then
        UIManager:close(self.widget)
        self.is_open = false
        self.widget = nil
    end
    -- Safe to call multiple times - becomes no-op after first call
end

local Notification = {}

---Parse parameters (string shorthand or options table)
---@param params string|table Message text or options table
---@param default_timeout number|nil Default timeout for this notification type
---@return string text, number|nil timeout
local function parseParams(params, default_timeout)
    if type(params) == "string" then
        -- Shorthand: Notification:success("Hello!")
        return params, default_timeout
    elseif type(params) == "table" then
        -- Advanced: Notification:success({ text = "Hello!", timeout = 10 }) or { text = "Hello!", timeout = nil }
        local text = params.text or ""
        local timeout = params.timeout ~= nil and params.timeout or default_timeout
        return text, timeout
    else
        -- Safe fallback instead of error() for KOReader compatibility
        return tostring(params), default_timeout
    end
end

---Show success notification
---@param params string|table Message text or options {text, timeout?}
---@return NotificationInstance Instance for manual closing
function Notification:success(params)
    local text, timeout = parseParams(params, DEFAULT_TIMEOUTS.SUCCESS)

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show error notification
---@param params string|table Message text or options {text, timeout?}
---@return NotificationInstance Instance for manual closing
function Notification:error(params)
    local text, timeout = parseParams(params, DEFAULT_TIMEOUTS.ERROR)

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show warning notification
---@param params string|table Message text or options {text, timeout?}
---@return NotificationInstance Instance for manual closing
function Notification:warning(params)
    local text, timeout = parseParams(params, DEFAULT_TIMEOUTS.WARNING)

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show info notification (manual close by default)
---@param params string|table Message text or options {text, timeout?}
---@return NotificationInstance Instance for manual closing
function Notification:info(params)
    local text, timeout = parseParams(params, nil) -- nil = manual close by default

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

return Notification
