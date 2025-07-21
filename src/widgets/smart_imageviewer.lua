--[[--
**Smart ImageViewer for Miniflux Plugin**

Minimal implementation extending ImageViewer with:
- Page turn buttons close the viewer instead of zooming

Simple and focused - just overrides key events for better navigation.
--]]

local ImageViewer = require('ui/widget/imageviewer')
local UIManager = require('ui/uimanager')
local Device = require('device')

---@class SmartImageViewer : ImageViewer
local SmartImageViewer = ImageViewer:extend({})

---Initialize the SmartImageViewer
function SmartImageViewer:init()
    -- Call parent init
    ImageViewer.init(self)

    -- Override key events after parent init (parent sets key_events dynamically)
    self:setupKeyEvents()
end

---Setup key events to override default zoom behavior with close actions
function SmartImageViewer:setupKeyEvents()
    -- Override the parent's key_events with our close actions
    self.key_events = {
        -- Map all page turn keys to close the image viewer (same as end-of-entry dialog)
        ClosePgFwd = { Device.input.group.PgFwd, doc = 'close image viewer' }, -- Page forward
        ClosePgBack = { Device.input.group.PgBack, doc = 'close image viewer' }, -- Page back
        -- Keep original close keys for other buttons
        Close = { Device.input.group.Back, doc = 'close image viewer' },
        CloseAlt = { { 'Right' }, doc = 'close image viewer' },
    }
end

---Handle key events for closing image viewer
function SmartImageViewer:onClose()
    UIManager:close(self)
    return true
end

function SmartImageViewer:onCloseAlt()
    UIManager:close(self)
    return true
end

-- Page turn key handlers (override default zoom behavior)
function SmartImageViewer:onCloseRPgFwd()
    UIManager:close(self)
    return true
end

function SmartImageViewer:onCloseLPgFwd()
    UIManager:close(self)
    return true
end

function SmartImageViewer:onCloseRPgBack()
    UIManager:close(self)
    return true
end

function SmartImageViewer:onCloseLPgBack()
    UIManager:close(self)
    return true
end

-- No rotation functionality - just custom key events for closing

---Cleanup when closing
function SmartImageViewer:onCloseWidget()
    -- Call parent cleanup
    ImageViewer.onCloseWidget(self)
end

return SmartImageViewer
