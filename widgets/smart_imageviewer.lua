--[[--
**Smart ImageViewer for Miniflux Plugin**

Minimal implementation extending ImageViewer with:
- Auto-rotation on device orientation changes (toggles rotation like manual button)
- Page turn buttons close the viewer instead of zooming

Uses ImageViewer's built-in rotation logic for simplicity and reliability.
--]]

local ImageViewer = require("ui/widget/imageviewer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local logger = require("logger")
local _ = require("gettext")
local Debugger = require("utils/debugger")

---@class SmartImageViewer : ImageViewer
local SmartImageViewer = ImageViewer:extend{}

---Initialize the SmartImageViewer
function SmartImageViewer:init()
    Debugger.enter("SmartImageViewer:init")
    
    -- Call parent init (handles auto-rotation setting)
    ImageViewer.init(self)
    
    -- Override key events after parent init (parent sets key_events dynamically)
    self:setupKeyEvents()
    
    -- Device rotation will be handled via onSetRotationMode event
    Debugger.debug("SmartImageViewer: Initialized and ready for rotation events")
    
    Debugger.exit("SmartImageViewer:init")
end

---Setup key events to override default zoom behavior with close actions
function SmartImageViewer:setupKeyEvents()
    -- Override the parent's key_events with our close actions
    self.key_events = {
        -- Map all page turn keys to close the image viewer (same as end-of-entry dialog)
        CloseRPgFwd = { {"RPgFwd"}, doc = "close image viewer" },   -- Right page forward
        CloseLPgFwd = { {"LPgFwd"}, doc = "close image viewer" },   -- Left page forward  
        CloseRPgBack = { {"RPgBack"}, doc = "close image viewer" }, -- Right page back
        CloseLPgBack = { {"LPgBack"}, doc = "close image viewer" }, -- Left page back
        -- Keep original close keys for other buttons
        Close = { {"Back", "Left"}, doc = "close image viewer" },
        CloseAlt = { {"Right"}, doc = "close image viewer" },
    }
    Debugger.debug("SmartImageViewer: Key events set up to close instead of zoom")
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

-- Device rotation events are automatically received by modal widgets via UIManager event system

---Handle device rotation events from accelerometer
---This is called automatically by UIManager when device orientation changes
function SmartImageViewer:onSetRotationMode(mode)
    Debugger.enter("SmartImageViewer:onSetRotationMode", "mode=" .. tostring(mode))
    
    local old_screen_mode = Screen:getRotationMode()
    Debugger.debug("SmartImageViewer: Current screen mode=" .. tostring(old_screen_mode) .. ", incoming mode=" .. tostring(mode))
    
    -- First, let the screen rotation update
    if mode ~= nil then
        if mode ~= old_screen_mode then
            Screen:setRotationMode(mode)
            Debugger.debug("SmartImageViewer: Screen rotation updated from " .. tostring(old_screen_mode) .. " to " .. tostring(mode))
        else
            Debugger.debug("SmartImageViewer: Screen mode unchanged")
        end
    end
    
    -- Do exactly what the manual rotate button does: toggle rotated and update
    local old_rotated = self.rotated
    self.rotated = not self.rotated and true or false
    
    Debugger.info("SmartImageViewer: AUTO-ROTATION - " .. tostring(old_rotated) .. " → " .. tostring(self.rotated))
    self:update()
    
    Debugger.exit("SmartImageViewer:onSetRotationMode", "handled=true")
    return true  -- Event handled, stop propagation
end

-- No complex rotation logic needed - just use ImageViewer's built-in rotation

---Cleanup when closing
function SmartImageViewer:onCloseWidget()
    -- Call parent cleanup
    ImageViewer.onCloseWidget(self)
end

return SmartImageViewer