--[[--
**Smart ImageViewer for Miniflux Plugin**

Minimal implementation extending ImageViewer with:
- 4-direction rotation support (0°, 90°, 180°, 270°)
- Auto-rotation on device orientation changes
- Enhanced rotation button cycling

This is a minimal viable implementation focusing on core functionality.
--]]

local ImageViewer = require("ui/widget/imageviewer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local logger = require("logger")
local _ = require("gettext")

---@class SmartImageViewer : ImageViewer
local SmartImageViewer = ImageViewer:extend{
    rotation_state = 0,  -- 0=0°, 1=90°, 2=180°, 3=270°
    ui_ref = nil,
}

-- Simple rotation mappings
local ROTATION_ANGLES = { 0, 90, 180, 270 }
local ROTATION_NAMES = { "0°", "90°", "180°", "270°" }

---Initialize the SmartImageViewer
function SmartImageViewer:init()
    -- Auto-rotate on init if enabled
    if self.image and G_reader_settings:isTrue("imageviewer_rotate_auto_for_best_fit") then
        self.rotation_state = self:calculateOptimalRotation()
        self.rotated = self.rotation_state ~= 0
    end
    
    -- Call parent init
    ImageViewer.init(self)
    
    -- Register for device rotation events
    if self.ui_ref then
        self:registerForRotationEvents()
    end
    
    -- Override rotation button
    self:enhanceRotationButton()
end

---Calculate optimal rotation based on screen and image dimensions
---@return number rotation_state (0-3)
function SmartImageViewer:calculateOptimalRotation()
    if not self.image then return 0 end
    
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local image_w, image_h = self.image:getWidth(), self.image:getHeight()
    
    -- Simple logic: if orientations don't match, rotate
    local screen_is_landscape = screen_w > screen_h
    local image_is_landscape = image_w > image_h
    
    if screen_is_landscape ~= image_is_landscape then
        -- Use existing ImageViewer rotation direction logic
        if screen_w <= screen_h then
            -- Portrait mode - default counterclockwise (270°)
            return G_reader_settings:isTrue("imageviewer_rotation_portrait_invert") and 1 or 3
        else
            -- Landscape mode - default clockwise (90°)
            return G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and 3 or 1
        end
    end
    
    return 0  -- No rotation needed
end

---Register for device rotation events
function SmartImageViewer:registerForRotationEvents()
    -- Store original handler
    self.original_rotation_handler = self.ui_ref.onSetRotationMode
    
    local viewer = self
    -- Override with our handler
    self.ui_ref.onSetRotationMode = function(ui_instance, mode)
        viewer:onSetRotationMode(mode)
        -- Call original if it exists
        if viewer.original_rotation_handler then
            return viewer.original_rotation_handler(ui_instance, mode)
        end
    end
end

---Handle device rotation
function SmartImageViewer:onSetRotationMode(mode)
    local new_rotation = self:calculateOptimalRotation()
    
    if new_rotation ~= self.rotation_state then
        logger.dbg("SmartImageViewer: Auto-rotating from", 
                   ROTATION_NAMES[self.rotation_state + 1], 
                   "to", ROTATION_NAMES[new_rotation + 1])
        
        self.rotation_state = new_rotation
        self.rotated = self.rotation_state ~= 0
        self:update()
        UIManager:setDirty(self, "full")
    end
end

---Enhance rotation button to cycle through 4 directions
function SmartImageViewer:enhanceRotationButton()
    if not self.button_table then return end
    
    -- Find and enhance the rotate button
    local viewer = self
    local button = self.button_table:getButtonById("rotate")
    if button then
        button.text = _("Rotate")  -- Keep original text for now
        button.callback = function()
            viewer:cycleRotation()
        end
    end
end

---Cycle through rotation states
function SmartImageViewer:cycleRotation()
    self.rotation_state = (self.rotation_state + 1) % 4
    self.rotated = self.rotation_state ~= 0
    
    logger.dbg("SmartImageViewer: Manual rotation to", ROTATION_NAMES[self.rotation_state + 1])
    
    -- Keep button text simple for now - no need to update
    self:update()
end

---Calculate rotation angle based on rotation state
---@return number rotation angle for ImageWidget
function SmartImageViewer:calculateRotationAngle()
    if not self.rotated or self.rotation_state == 0 then
        return 0
    end
    
    -- ImageViewer uses inverted angles for 90° and 270°
    local angles = { 0, 270, 180, 90 }  -- 0°, 90°, 180°, 270°
    return angles[self.rotation_state + 1]
end

---Override to support 4-direction rotation
function SmartImageViewer:_new_image_wg()
    -- Call parent method to handle all the complex logic
    ImageViewer._new_image_wg(self)
    
    -- Only override rotation_angle if we have custom rotation
    if self.rotated and self.rotation_state ~= 0 then
        local rotation_angle = self:calculateRotationAngle()
        if self._image_wg then
            self._image_wg.rotation_angle = rotation_angle
        end
    end
end

---Cleanup when closing
function SmartImageViewer:onCloseWidget()
    -- Restore original rotation handler
    if self.ui_ref and self.original_rotation_handler then
        self.ui_ref.onSetRotationMode = self.original_rotation_handler
    end
    
    ImageViewer.onCloseWidget(self)
end

return SmartImageViewer