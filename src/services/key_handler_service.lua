--[[--
**Key Handler Service for Miniflux Plugin**

This service handles key events for navigation in Miniflux entries and image viewing.
It provides physical key support for end-of-book dialogs and image viewer interactions.
--]]

local UIManager = require('ui/uimanager')
local Device = require('device')
local _ = require('gettext')

---@class KeyHandlerService
---@field miniflux_plugin table Reference to main plugin
---@field entry_service table Entry service for navigation
---@field navigation_service table Navigation service
local KeyHandlerService = {}

---Create a new KeyHandlerService instance
---@param params table Parameters with miniflux_plugin, entry_service, navigation_service
---@return KeyHandlerService New service instance
function KeyHandlerService:new(params)
    local instance = {
        miniflux_plugin = params.miniflux_plugin,
        entry_service = params.entry_service,
        navigation_service = params.navigation_service,
        touch_zones_registered = false, -- Track registration state
    }
    setmetatable(instance, { __index = self })

    -- Conditionally set up touch zones only for miniflux entries
    -- This prevents global override of ReaderUI for non-miniflux content
    if Device:isTouchDevice() and instance.miniflux_plugin.ui then
        instance:setupImageTouchZones()
    end

    return instance
end

---Setup touch zones for image tap detection
---
---Touch Zone Priority System:
---KOReader processes touch zones in registration order, but the 'overrides' array
---allows higher priority handlers to intercept gestures before lower priority ones.
---
---Event Flow Hierarchy (highest to lowest priority):
---1. Links - Highest priority when link detection is enabled
---2. Images - Our miniflux image detection (this handler)
---3. Menu activation - Menu taps in designated corner areas
---4. Page turning - Default fallback for navigation
---
---Strategy:
---We override both menu corner zones AND page turning zones to ensure image detection
---takes precedence. This solves the problem where images near the top of the screen
---would trigger menu activation instead of image viewing.
---
---The overrides work by preventing the overridden zones from receiving the tap gesture
---if our handler returns true (indicating we handled the tap).
---
---Conditional Registration:
---Touch zones are only registered when viewing miniflux entries to avoid global
---interference with ReaderUI for regular books. This follows KOReader best practices.
---
---@return nil
function KeyHandlerService:setupImageTouchZones()
    -- Only register touch zones when viewing miniflux entries
    -- This prevents global override of ReaderUI for non-miniflux content
    if not self:isMinifluxEntry() then
        return
    end

    -- Avoid duplicate registration
    if self.touch_zones_registered then
        return
    end

    -- Store zone definition for potential deregistration
    self.touch_zones = {
        {
            id = 'miniflux_tap_image',
            ges = 'tap',
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0, -- Cover entire screen
                ratio_w = 1,
                ratio_h = 1,
            },
            overrides = {
                -- Override menu corner zones to prioritize image detection
                'tap_top_left_corner', -- Top-left menu activation
                'tap_top_right_corner', -- Top-right menu activation
                'tap_left_bottom_corner', -- Bottom-left menu activation
                'tap_right_bottom_corner', -- Bottom-right menu activation
                -- Override page turning zones as secondary priority
                'tap_forward', -- Forward page turn
                'tap_backward', -- Backward page turn
            },
            handler = function(ges)
                return self:onTapImage(ges)
            end,
        },
    }

    self.miniflux_plugin.ui:registerTouchZones(self.touch_zones)
    self.touch_zones_registered = true
end

---Handle image tap events
---
---This handler is called for ALL taps due to our full-screen touch zone, but we use
---careful filtering to only process relevant taps:
---
---1. Context Filter: Only process taps on miniflux entries (not regular books)
---2. Position Transform: Convert screen coordinates to document coordinates
---3. Image Detection: Use KOReader's built-in image detection (same as ReaderHighlight)
---4. Return Logic: Return true if we handled the tap, false to pass it through
---
---The return value is crucial for the override system:
---- true = We handled this tap, prevent other handlers from processing it
---- false = We didn't handle this tap, let other handlers (menu, page turn) process it
---
---@param ges table Gesture information with screen position
---@return boolean True if handled (blocks other handlers), false if not handled
function KeyHandlerService:onTapImage(ges)
    -- Context filter: Only process taps on miniflux entries
    -- This prevents interference with regular reading of other documents
    if not self:isMinifluxEntry() then
        return false -- Not our content, let other handlers process
    end

    -- Convert screen coordinates to document coordinates
    local tap_pos = self.miniflux_plugin.ui.view:screenToPageTransform(ges.pos)
    if not tap_pos then
        return false -- Couldn't transform coordinates, let other handlers process
    end

    -- Use KOReader's built-in image detection (same method as ReaderHighlight)
    -- Parameters: position, try_image_box=true, try_bb_from_selection=true
    local image = self.miniflux_plugin.ui.document:getImageFromPosition(tap_pos, true, true)
    if image then
        -- Found an image at tap position - show custom viewer with key handlers
        self:showImageViewer(image)
        return true -- We handled this tap, block menu/page turn handlers
    end

    -- No image found at tap position - let other handlers process the tap
    return false -- Pass through to menu activation or page turning
end

---Show smart image viewer with auto-rotation and custom key handlers
---
---Creates a SmartImageViewer that supports:
--- - 4-direction rotation (0°, 90°, 180°, 270°)
--- - Auto-rotation on device orientation changes
--- - Physical page turn keys to close viewer
---
---Physical Key Mapping:
---- RPgFwd (Right Page Forward) - Close image viewer
---- LPgFwd (Left Page Forward) - Close image viewer
---- RPgBack (Right Page Back) - Close image viewer
---- LPgBack (Left Page Back) - Close image viewer
---
---This provides a consistent experience where the same keys used for entry navigation
---also work for closing image viewers, making it intuitive for e-reader users.
---
---@param image table Image data from document
---@return nil
function KeyHandlerService:showImageViewer(image)
    local SmartImageViewer = require('widgets/smart_imageviewer')

    local imgviewer = SmartImageViewer:new({
        image = image,
        with_title_bar = false,
        fullscreen = true,
        ui_ref = self.miniflux_plugin.ui, -- Pass UI reference for rotation events
        key_events = {
            -- Map all page turn keys to close the image viewer
            -- This overrides the default zoom behavior to provide consistent navigation
            CloseRPgFwd = { { 'RPgFwd' }, event = 'Close' }, -- Right page forward
            CloseLPgFwd = { { 'LPgFwd' }, event = 'Close' }, -- Left page forward
            CloseRPgBack = { { 'RPgBack' }, event = 'Close' }, -- Right page back
            CloseLPgBack = { { 'LPgBack' }, event = 'Close' }, -- Left page back
        },
    })

    UIManager:show(imgviewer)
end

---Check if current document is a miniflux entry
---@return boolean True if current document is a miniflux entry
function KeyHandlerService:isMinifluxEntry()
    if
        not self.miniflux_plugin.ui
        or not self.miniflux_plugin.ui.document
        or not self.miniflux_plugin.ui.document.file
    then
        return false
    end

    local file_path = self.miniflux_plugin.ui.document.file
    return file_path:match('/miniflux/') and file_path:match('%.html$')
end

---Enhance end-of-entry dialog with key event support if device has keys
---
---This function adds physical key navigation to the existing end-of-entry dialog,
---allowing users to navigate between entries using the same keys they use for page turning.
---
---Key Mapping Strategy:
---- Back Keys (RPgBack, LPgBack) - Navigate to previous entry
---- Forward Keys (RPgFwd, LPgFwd) - Navigate to next entry
---
---This mirrors the logical direction of page turning and provides an intuitive
---navigation experience for users with physical keys (Kobo, Kindle, etc.).
---
---The enhancement is applied to the existing dialog without replacing it,
---maintaining compatibility with touch-only devices while adding key support
---for devices that have physical buttons.
---
---@param dialog table Existing dialog to enhance
---@param entry_info table Entry information with file_path and entry_id
---@return table Enhanced dialog (same instance, modified)
function KeyHandlerService:enhanceDialogWithKeys(dialog, entry_info)
    if not dialog then
        return dialog
    end

    -- Only add key handlers if device has physical keys
    -- Use Device:hasKeys() if available, otherwise check for common e-reader devices
    local has_keys = (Device.hasKeys and Device:hasKeys())
        or Device:isKobo()
        or Device:isKindle()
        or Device:isCervantes()
        or Device:isRemarkable()

    if not has_keys then
        return dialog -- No physical keys, return dialog unchanged
    end

    -- Add key event handlers to the existing dialog
    dialog.key_events = dialog.key_events or {}

    -- Register key events for entry navigation
    -- Each key event maps a physical key to an event name that triggers a handler function

    -- Navigate to previous entry (logical "back" direction)
    dialog.key_events.NavigatePreviousRPgBack = {
        { 'RPgBack' }, -- Right page back button
        event = 'NavigatePrevious',
    }
    dialog.key_events.NavigatePreviousLPgBack = {
        { 'LPgBack' }, -- Left page back button
        event = 'NavigatePrevious',
    }

    -- Navigate to next entry (logical "forward" direction)
    dialog.key_events.NavigateNextRPgFwd = {
        { 'RPgFwd' }, -- Right page forward button
        event = 'NavigateNext',
    }
    dialog.key_events.NavigateNextLPgFwd = {
        { 'LPgFwd' }, -- Left page forward button
        event = 'NavigateNext',
    }

    -- Store references for navigation
    local key_handler_service = self
    local stored_entry_info = entry_info

    -- Add event handlers
    function dialog:onNavigatePrevious()
        UIManager:close(self)
        local Navigation = require('services/navigation_service')
        Navigation.navigateToEntry(stored_entry_info, {
            navigation_options = { direction = 'previous' },
            settings = key_handler_service.miniflux_plugin.settings,
            miniflux_api = key_handler_service.miniflux_plugin.miniflux_api,
            entry_service = key_handler_service.miniflux_plugin.entry_service,
            miniflux_plugin = key_handler_service.miniflux_plugin,
        })
        return true
    end

    function dialog:onNavigateNext()
        UIManager:close(self)
        local Navigation = require('services/navigation_service')
        Navigation.navigateToEntry(stored_entry_info, {
            navigation_options = { direction = 'next' },
            settings = key_handler_service.miniflux_plugin.settings,
            miniflux_api = key_handler_service.miniflux_plugin.miniflux_api,
            entry_service = key_handler_service.miniflux_plugin.entry_service,
            miniflux_plugin = key_handler_service.miniflux_plugin,
        })
        return true
    end

    return dialog
end

---Cleanup touch zones when closing or switching documents
---This method can be called to unregister touch zones when they're no longer needed
---@return nil
function KeyHandlerService:cleanup()
    if self.touch_zones_registered and self.touch_zones then
        self.miniflux_plugin.ui:unRegisterTouchZones(self.touch_zones)
        self.touch_zones_registered = false
        self.touch_zones = nil
    end
end

return KeyHandlerService
