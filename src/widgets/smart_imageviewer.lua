--[[--
**Smart ImageViewer for Miniflux Plugin**

Minimal implementation extending ImageViewer with:
- Page turn buttons close the viewer instead of zooming

Simple and focused - just overrides key events for better navigation.
--]]

local ImageViewer = require('ui/widget/imageviewer')
local UIManager = require('ui/uimanager')

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
        CloseRPgFwd = { { 'RPgFwd' }, doc = 'close image viewer' }, -- Right page forward
        CloseLPgFwd = { { 'LPgFwd' }, doc = 'close image viewer' }, -- Left page forward
        CloseRPgBack = { { 'RPgBack' }, doc = 'close image viewer' }, -- Right page back
        CloseLPgBack = { { 'LPgBack' }, doc = 'close image viewer' }, -- Left page back
        -- Keep original close keys for other buttons
        Close = { { 'Back', 'Left' }, doc = 'close image viewer' },
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
