--[[--
**ReaderLink Enhancement for Miniflux Plugin**

This module enhances KOReader's ReaderLink functionality by:
1. Adding 'Open image in viewer' button to link dialogs
2. Providing full-screen image tap detection for miniflux entries
3. Integrating with custom ImageViewer widget

This is the single entry point for all reader enhancements.
--]]

local EventListener = require('ui/widget/eventlistener')
local UIManager = require('ui/uimanager')
local Device = require('device')
local util = require('util')
local _ = require('gettext')

---@class MinifluxReaderLink : EventListener
---@field miniflux Miniflux Reference to main plugin
---@field ui ReaderUI Direct reference to reader UI
---@field reader_link ReaderLink Direct reference to ReaderLink module
---@field wrapped_onTap table|nil Wrapped onTap method object
---@field dialog_integration_setup boolean Track setup state
---@field last_link_tap_pos table|nil Store tap position from link detection
---@field touch_zones_registered boolean Track touch zones registration state
---@field touch_zones table[]|nil Touch zones definition for image tap detection
local MinifluxReaderLink = EventListener:extend({
    name = 'miniflux_readerlink',
    miniflux = nil,
})

---Initialize the module and set up ReaderLink enhancements
function MinifluxReaderLink:init()
    if not self.miniflux or not self.miniflux.ui or not self.miniflux.ui.link then
        return
    end

    -- Set up references
    self.ui = self.miniflux.ui
    self.reader_link = self.miniflux.ui.link
    self.wrapped_onTap = nil
    self.dialog_integration_setup = false
    self.last_link_tap_pos = nil
    self.touch_zones_registered = false
    self.touch_zones = nil

    -- Wrap ReaderLink's onTap method to capture tap position
    if self.reader_link then
        self.wrapped_onTap = util.wrapMethod(self.reader_link, 'onTap', function(...)
            -- Only capture tap position for miniflux entries
            if self:isMinifluxEntry() then
                local args = { ... }
                local ges = args[3] -- third argument is gesture
                self.last_link_tap_pos = ges and ges.pos
            end

            -- Always call original method
            return self.wrapped_onTap:raw_method_call(...)
        end)
    end

    -- Set up ReaderLink dialog integration
    self:setupLinkDialogIntegration()

    -- Set up image touch zones for full-screen image tap detection
    if Device:isTouchDevice() and self.ui then
        self:setupImageTouchZones()
    end
end

---Setup integration with ReaderLink dialog to add "Open in Image Viewer" option
---
---This integrates with KOReader's external link dialog system to add a new button
---that appears when tapping on links that contain images. It follows the same pattern
---as other plugins (like Wallabag) that extend the link dialog functionality.
---
---The button is numbered "15_image_viewer" to appear between existing buttons:
---10_copy → 15_image_viewer → 20_qrcode → etc.
---
---Integration Pattern:
---KOReader's ReaderLink module provides addToExternalLinkDialog() method that allows
---plugins to inject custom buttons into the link dialog. Each button has:
---1. Numbered key for ordering (15_image_viewer)
---2. Callback function that defines button behavior
---3. Optional show_in_dialog_func for conditional display
---
---@return nil
function MinifluxReaderLink:setupLinkDialogIntegration()
    -- Only set up integration if ReaderLink is available
    if not self.reader_link then
        return
    end

    -- Store reference to self for use in closures
    local service = self

    -- Add image viewer button to external link dialog
    self.reader_link:addToExternalLinkDialog('15_image_viewer', function(this, link_url)
        return {
            text = _('Open image in viewer'),
            callback = function()
                UIManager:close(this.external_link_dialog)
                service:handleImageViewerAction(this)
            end,
            show_in_dialog_func = function()
                return service:shouldShowImageViewerButton(link_url)
            end,
        }
    end)

    self.dialog_integration_setup = true
end

---Handle the image viewer action when button is tapped
---
---This method is called when the user taps "Open image in viewer" in the link dialog.
---It uses the stored tap position to find and display the image.
---
---@param reader_link_instance table ReaderLink instance (not used, but provided by dialog)
---@return nil
-- selene: allow(unused_variable)
function MinifluxReaderLink:handleImageViewerAction(reader_link_instance)
    -- Check if we have a stored tap position
    if not self.last_link_tap_pos then
        return
    end

    -- Validate UI components
    if
        not self.miniflux
        or not self.miniflux.ui
        or not self.miniflux.ui.view
        or not self.miniflux.ui.document
    then
        return
    end

    -- Check if there's an image at the stored tap position
    local tap_pos = self.miniflux.ui.view:screenToPageTransform(self.last_link_tap_pos)
    if not tap_pos then
        return
    end

    -- Use KOReader's built-in image detection with error handling
    local success, image = pcall(function()
        return self.miniflux.ui.document:getImageFromPosition(tap_pos, true, true)
    end)

    if not success then
        return
    end

    if not image then
        return
    end

    -- Use custom image viewer with enhanced key handling
    self:showImageViewer(image)

    -- Clear stored tap position to prevent stale data
    self.last_link_tap_pos = nil
end

---Determine if the image viewer button should be shown in the link dialog
---
---The button is only shown when:
---1. We're viewing a miniflux entry (not regular books)
---2. There's actually an image at the tapped position
---
---This prevents the button from appearing unnecessarily and maintains clean UI.
---
---@param link_url string The URL of the link (not used, but required by ReaderLink)
---@return boolean True if button should be shown, false otherwise
-- selene: allow(unused_variable)
function MinifluxReaderLink:shouldShowImageViewerButton(link_url)
    -- Only show for miniflux entries
    if not self:isMinifluxEntry() then
        return false
    end

    -- Check if we have a stored tap position
    if not self.last_link_tap_pos then
        return false
    end

    -- Validate UI components
    if
        not self.miniflux
        or not self.miniflux.ui
        or not self.miniflux.ui.view
        or not self.miniflux.ui.document
    then
        return false
    end

    -- Check if there's actually an image at the stored tap position
    local tap_pos = self.miniflux.ui.view:screenToPageTransform(self.last_link_tap_pos)
    if not tap_pos then
        return false
    end

    -- Use KOReader's built-in image detection with error handling
    local success, image = pcall(function()
        return self.miniflux.ui.document:getImageFromPosition(tap_pos, true, true)
    end)

    if not success then
        return false
    end

    local has_image = image ~= nil

    return has_image
end

---Check if current document is a miniflux entry
---@return boolean True if current document is a miniflux entry
function MinifluxReaderLink:isMinifluxEntry()
    if
        not self.miniflux
        or not self.miniflux.ui
        or not self.miniflux.ui.document
        or not self.miniflux.ui.document.file
    then
        return false
    end

    local file_path = self.miniflux.ui.document.file
    return file_path:match('/miniflux/') and file_path:match('%.html$')
end

---Setup touch zones for full-screen image tap detection
---
---This sets up full-screen touch zones that override menu corners and page turning
---to prioritize image detection. Only active for miniflux entries.
---
---@return nil
function MinifluxReaderLink:setupImageTouchZones()
    -- Only register touch zones when viewing miniflux entries
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

    self.miniflux.ui:registerTouchZones(self.touch_zones)
    self.touch_zones_registered = true
end

---Handle full-screen image tap events
---
---This handler detects image taps anywhere on screen and shows the custom ImageViewer.
---It only processes taps on miniflux entries to avoid interfering with regular books.
---
---@param ges table Gesture information with screen position
---@return boolean True if handled (blocks other handlers), false if not handled
function MinifluxReaderLink:onTapImage(ges)
    -- Context filter: Only process taps on miniflux entries
    if not self:isMinifluxEntry() then
        return false -- Not our content, let other handlers process
    end

    -- Convert screen coordinates to document coordinates
    local tap_pos = self.miniflux.ui.view:screenToPageTransform(ges.pos)
    if not tap_pos then
        return false -- Couldn't transform coordinates, let other handlers process
    end

    -- Use KOReader's built-in image detection (same method as ReaderHighlight)
    local image = self.miniflux.ui.document:getImageFromPosition(tap_pos, true, true)
    if image then
        -- Found an image at tap position - show custom viewer
        self:showImageViewer(image)
        return true -- We handled this tap, block menu/page turn handlers
    end

    -- No image found at tap position - let other handlers process the tap
    return false -- Pass through to menu activation or page turning
end

---Show custom image viewer with enhanced key handling
---
---Creates a SmartImageViewer with page-turn-to-close behavior for consistent
---navigation experience with entry reading.
---
---@param image table Image data from document
---@return nil
function MinifluxReaderLink:showImageViewer(image)
    local MinifluxImageViewer = require('features/reader/widgets/miniflux_imageviewer')

    local imgviewer = MinifluxImageViewer:new({
        image = image,
        with_title_bar = false,
        fullscreen = true,
        ui_ref = self.ui, -- Pass UI reference for rotation events
        key_events = {
            -- Map all page turn keys to close the image viewer
            ClosePgFwd = { Device.input.group.PgFwd, event = 'Close' }, -- Page forward
            ClosePgBack = { Device.input.group.PgBack, event = 'Close' }, -- Page back
        },
    })

    UIManager:show(imgviewer)
end

---Cleanup module when closing or switching documents
---@return nil
function MinifluxReaderLink:onCloseWidget()
    -- Revert wrapped onTap method
    if self.wrapped_onTap then
        self.wrapped_onTap:revert()
        self.wrapped_onTap = nil
    end

    -- Unregister touch zones if registered
    if self.touch_zones_registered and self.touch_zones and self.miniflux and self.miniflux.ui then
        self.miniflux.ui:unRegisterTouchZones(self.touch_zones)
        self.touch_zones_registered = false
        self.touch_zones = nil
    end
end

return MinifluxReaderLink
