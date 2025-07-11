--[[--
**ReaderLink Service for Miniflux Plugin**

This service enhances KOReader's ReaderLink functionality by adding miniflux-specific
options to the link dialog. It integrates with the external link dialog system to
provide additional actions when tapping on links in miniflux entries.
--]]

local UIManager = require("ui/uimanager")
local Debugger = require("utils/debugger")
local _ = require("gettext")

---@class ReaderLinkService
---@field miniflux_plugin table Reference to main plugin
local ReaderLinkService = {}

---Create a new ReaderLinkService instance
---@param params table Parameters with miniflux_plugin
---@return ReaderLinkService New service instance
function ReaderLinkService:new(params)
    local instance = {
        ui = params.miniflux_plugin.ui,  -- Direct reference to UI
        reader_link = params.miniflux_plugin.ui.link,  -- Direct reference to ReaderLink
        key_handler_service = nil,  -- Will be set after KeyHandlerService is created
        dialog_integration_setup = false,  -- Track setup state
        last_link_tap_pos = nil,  -- Store tap position from link detection
    }
    setmetatable(instance, { __index = self })
    
    -- Override ReaderLink's onTap to capture tap position
    instance:overrideReaderLinkOnTap()
    
    -- Set up ReaderLink dialog integration
    instance:setupLinkDialogIntegration()
    
    return instance
end

---Override ReaderLink's onTap method to capture tap position for image detection
---
---This method intercepts the link tap handling to store the tap position so we can
---use it later in the external link dialog to detect if there's an image at that position.
---
---The override chain works like this:
---1. User taps on a link
---2. Our override captures the tap position
---3. Original onTap processes the link normally
---4. External link dialog shows with our button (if image detected)
---5. Button uses stored tap position to find and show the image
---
---@return nil
function ReaderLinkService:overrideReaderLinkOnTap()
    if not self.ui or not self.reader_link then
        Debugger.debug("ReaderLink not available for onTap override")
        return
    end
    
    Debugger.debug("Setting up ReaderLink onTap override")
    
    -- Store reference to original onTap method
    local original_onTap = self.reader_link.onTap
    local service = self
    
    -- Replace with our override
    self.reader_link.onTap = function(reader_link_instance, arg, ges)
        -- Only capture tap position for miniflux entries
        if service:isMinifluxEntry() then
            Debugger.debug("Capturing tap position for miniflux entry")
            service.last_link_tap_pos = ges and ges.pos
        end
        
        -- Call original onTap method
        return original_onTap(reader_link_instance, arg, ges)
    end
    
    Debugger.debug("ReaderLink onTap override complete")
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
function ReaderLinkService:setupLinkDialogIntegration()
    Debugger.enter("setupLinkDialogIntegration")
    
    -- Only set up integration if ReaderLink is available
    if not self.reader_link then
        Debugger.debug("ReaderLink not available, skipping dialog integration")
        Debugger.exit("setupLinkDialogIntegration", "no_readerlink")
        return
    end
    
    Debugger.debug("Setting up link dialog integration")
    
    -- Store reference to self for use in closures
    local service = self
    
    -- Add image viewer button to external link dialog
    self.reader_link:addToExternalLinkDialog("15_image_viewer", function(this, link_url)
        return {
            text = _("Open image in viewer"),
            callback = function()
                Debugger.debug("Image viewer button clicked")
                UIManager:close(this.external_link_dialog)
                service:handleImageViewerAction(this)
            end,
            show_in_dialog_func = function()
                return service:shouldShowImageViewerButton(link_url)
            end,
        }
    end)
    
    self.dialog_integration_setup = true
    Debugger.exit("setupLinkDialogIntegration", "success")
end

---Handle the image viewer action when button is tapped
---
---This method is called when the user taps "Open image in viewer" in the link dialog.
---It uses the stored tap position to find and display the image.
---
---@param reader_link_instance table ReaderLink instance (not used, but provided by dialog)
---@return nil
function ReaderLinkService:handleImageViewerAction(reader_link_instance)
    Debugger.enter("handleImageViewerAction")
    
    -- Check if we have a stored tap position
    if not self.last_link_tap_pos then
        Debugger.error("No stored tap position")
        Debugger.exit("handleImageViewerAction", "no_tap_pos")
        return
    end
    
    -- Validate UI components
    if not self.ui or not self.ui.view or not self.ui.document then
        Debugger.error("Invalid UI components")
        Debugger.exit("handleImageViewerAction", "invalid_ui")
        return
    end
    
    Debugger.debug("Transforming stored tap position")
    
    -- Check if there's an image at the stored tap position
    local tap_pos = self.ui.view:screenToPageTransform(self.last_link_tap_pos)
    if not tap_pos then
        Debugger.warn("Could not transform tap position")
        Debugger.exit("handleImageViewerAction", "transform_failed")
        return
    end
    
    Debugger.debug("Checking for image at position")
    
    -- Use KOReader's built-in image detection with error handling
    local success, image = pcall(function()
        return self.ui.document:getImageFromPosition(tap_pos, true, true)
    end)
    
    if not success then
        Debugger.error("Error detecting image: " .. tostring(image))
        Debugger.exit("handleImageViewerAction", "image_detection_error")
        return
    end
    
    if not image then
        Debugger.warn("No image found at tap position")
        Debugger.exit("handleImageViewerAction", "no_image")
        return
    end
    
    Debugger.debug("Image found, opening viewer")
    
    -- Use custom image viewer with key handlers if available
    if self.key_handler_service then
        self.key_handler_service:showImageViewer(image)
    else
        -- Fallback to standard ImageViewer
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            with_title_bar = false,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
    end
    
    -- Clear stored tap position to prevent stale data
    self.last_link_tap_pos = nil
    
    Debugger.exit("handleImageViewerAction", "success")
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
function ReaderLinkService:shouldShowImageViewerButton(link_url)
    Debugger.enter("shouldShowImageViewerButton")
    
    -- Only show for miniflux entries
    if not self:isMinifluxEntry() then
        Debugger.debug("Not a miniflux entry, hiding button")
        Debugger.exit("shouldShowImageViewerButton", "not_miniflux")
        return false
    end
    
    -- Check if we have a stored tap position
    if not self.last_link_tap_pos then
        Debugger.debug("No stored tap position, hiding button")
        Debugger.exit("shouldShowImageViewerButton", "no_tap_pos")
        return false
    end
    
    -- Validate UI components
    if not self.ui or not self.ui.view or not self.ui.document then
        Debugger.debug("Invalid UI components, hiding button")
        Debugger.exit("shouldShowImageViewerButton", "invalid_ui")
        return false
    end
    
    -- Check if there's actually an image at the stored tap position
    local tap_pos = self.ui.view:screenToPageTransform(self.last_link_tap_pos)
    if not tap_pos then
        Debugger.debug("Could not transform tap position, hiding button")
        Debugger.exit("shouldShowImageViewerButton", "transform_failed")
        return false
    end
    
    -- Use KOReader's built-in image detection with error handling
    local success, image = pcall(function()
        return self.ui.document:getImageFromPosition(tap_pos, true, true)
    end)
    
    if not success then
        Debugger.error("Error detecting image: " .. tostring(image))
        Debugger.exit("shouldShowImageViewerButton", "image_detection_error")
        return false
    end
    
    local has_image = image ~= nil
    Debugger.debug("Image detection result: " .. tostring(has_image))
    Debugger.exit("shouldShowImageViewerButton", tostring(has_image))
    return has_image
end

---Check if current document is a miniflux entry
---@return boolean True if current document is a miniflux entry
function ReaderLinkService:isMinifluxEntry()
    if not self.ui or not self.ui.document or not self.ui.document.file then
        return false
    end
    
    local file_path = self.ui.document.file
    return file_path:match("/miniflux/") and file_path:match("%.html$")
end

---Cleanup service when closing or switching documents
---@return nil
function ReaderLinkService:cleanup()
    -- Currently no cleanup needed, but method provided for consistency
    Debugger.debug("ReaderLinkService cleanup complete")
end

return ReaderLinkService