--[[--
**MinifluxImageViewer for Miniflux Plugin**

Minimal implementation extending ImageViewer with:
- Page turn buttons close/rotate the viewer instead of zooming

Simple and focused - just overrides key events for better navigation.
--]]

local ImageViewer = require('ui/widget/imageviewer')
local Device = require('device')

---@class MinifluxImageViewer : ImageViewer
local MinifluxImageViewer = ImageViewer:extend({})

---Initialize the MinifluxImageViewer
function MinifluxImageViewer:init()
    -- Call parent init
    ImageViewer.init(self)

    -- Override key events after parent init (parent sets key_events dynamically)
    self:setupKeyEvents()
end

---Setup key events to override default zoom behavior with close actions
function MinifluxImageViewer:setupKeyEvents()
    -- Override the parent's key_events with our close actions
    self.key_events = {
        ClosePgFwd = { { Device.input.group.PgFwd } }, -- Page forward
        RotatePgBack = { { Device.input.group.PgBack } }, -- Page back
        Close = { { Device.input.group.Back } },
        CloseWithRight = { { 'Right' } },
        RotateWithLeft = { { 'Left' } },
    }
end

function MinifluxImageViewer:onRotateWithLeft()
    self.rotated = not self.rotated and true or false
    self:update()
    return true
end

function MinifluxImageViewer:onCloseWithRight()
    return self:onClose()
end

-- Page turn key handlers (override default zoom behavior)
function MinifluxImageViewer:onCloseRPgFwd()
    return self:onClose()
end

function MinifluxImageViewer:onCloseLPgFwd()
    return self:onClose()
end

function MinifluxImageViewer:onRotateRPgBack()
    self.rotated = not self.rotated and true or false
    self:update()
    return true
end

function MinifluxImageViewer:onRotateLPgBack()
    self.rotated = not self.rotated and true or false
    self:update()
    return true
end

return MinifluxImageViewer
