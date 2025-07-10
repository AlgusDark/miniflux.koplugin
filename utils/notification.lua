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

-- **Notification** - Simple notification wrapper around InfoMessage with
-- consistent timeout handling. Always returns instance for consistent API.
local Notification = {}

---Show success notification
---@param text string Message text
---@param opts? {timeout?: number} Optional configuration (defaults: timeout=2s)
---@return NotificationInstance Instance for manual closing
function Notification:success(text, opts)
    opts = opts or {}
    local timeout = opts.timeout or DEFAULT_TIMEOUTS.SUCCESS

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show error notification
---@param text string Message text
---@param opts? {timeout?: number} Optional configuration (defaults: timeout=5s)
---@return NotificationInstance Instance for manual closing
function Notification:error(text, opts)
    opts = opts or {}
    local timeout = opts.timeout or DEFAULT_TIMEOUTS.ERROR

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show warning notification
---@param text string Message text
---@param opts? {timeout?: number} Optional configuration (defaults: timeout=3s)
---@return NotificationInstance Instance for manual closing
function Notification:warning(text, opts)
    opts = opts or {}
    local timeout = opts.timeout or DEFAULT_TIMEOUTS.WARNING

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

---Show info notification
---@param text string Message text
---@param opts? {timeout?: number} Optional configuration (defaults: timeout=nil for manual close)
---@return NotificationInstance Instance for manual closing
function Notification:info(text, opts)
    opts = opts or {}
    local timeout = opts.timeout -- Defaults to nil (manual close) for info notifications

    local widget = InfoMessage:new({
        text = text,
        timeout = timeout,
    })
    UIManager:show(widget)
    return NotificationInstance:new(widget)
end

return Notification
