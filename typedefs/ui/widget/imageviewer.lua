---@meta
---@module 'ui/widget/imageviewer'

---@class ImageViewerOptions
---@field file? string Path to image file
---@field image? table Image data object
---@field image_disposable? boolean Whether image can be disposed after viewing
---@field fullscreen? boolean Whether to show in fullscreen mode
---@field with_title_bar? boolean Whether to show title bar
---@field title_text? string Custom title text
---@field caption? string Image caption text
---@field width? number Custom width
---@field height? number Custom height
---@field rotated? boolean Whether image is rotated
---@field x? number X position
---@field y? number Y position
---@field modal? boolean Whether to show as modal dialog
---@field dismiss_callback? function Callback when viewer is dismissed

---ImageViewer widget for KOReader - A comprehensive image display and manipulation component
---
---The ImageViewer provides a full-featured image viewing experience with support for:
---- Fullscreen and windowed display modes with optional title bars and captions
---- Interactive image manipulation: zoom, pan, and rotation with gesture support
---- Multiple image sources: file paths or pre-loaded image data objects
---- Modal and non-modal presentation modes for different UI contexts
---- Memory management through disposable image objects
---- Touch and keyboard navigation with intuitive controls
---- Integration with KOReader's UI system and event handling
---
---ImageViewer is commonly used throughout KOReader for displaying book covers, diagrams,
---extracted images from documents, and any other image content that requires user interaction.
---It provides the foundation for image-related features while maintaining consistency with
---the overall KOReader user experience and e-ink display optimizations.
---@class ImageViewer : WidgetContainer
---@field image any Current image object
---@field file string|nil Image file path
---@field image_disposable boolean Whether image can be disposed
---@field fullscreen boolean Whether in fullscreen mode
---@field with_title_bar boolean Whether title bar is shown
---@field title_text string|nil Custom title text
---@field caption string|nil Image caption
---@field width number Image width
---@field height number Image height
---@field rotated boolean Whether image is rotated
---@field x number X position
---@field y number Y position
---@field modal boolean Whether shown as modal
---@field dismiss_callback function|nil Dismiss callback
local ImageViewer = {}

---Create new ImageViewer instance
---@param self ImageViewer
---@param opts ImageViewerOptions
---@return ImageViewer
function ImageViewer:new(opts) end

---Initialize ImageViewer
---@param self ImageViewer
function ImageViewer:init() end

---Show the image viewer
---@param self ImageViewer
function ImageViewer:show() end

---Close the image viewer
---@param self ImageViewer
function ImageViewer:close() end

---Rotate image
---@param self ImageViewer
---@param direction? number Rotation direction (1 or -1)
function ImageViewer:rotate(direction) end

---Zoom image
---@param self ImageViewer
---@param factor number Zoom factor
function ImageViewer:zoom(factor) end

---Pan image
---@param self ImageViewer
---@param x number X offset
---@param y number Y offset
function ImageViewer:pan(x, y) end

---Reset image view to original state
---@param self ImageViewer
function ImageViewer:reset() end

---Handle key events
---@param self ImageViewer
---@param key string Key name
---@return boolean handled Whether event was handled
function ImageViewer:onKeyPress(key) end

---Handle gesture events
---@param self ImageViewer
---@param gesture table Gesture data
---@return boolean handled Whether event was handled
function ImageViewer:onGesture(gesture) end

---Clean up resources when widget is closed
---@param self ImageViewer
function ImageViewer:onCloseWidget() end

---Not sure where this is coming from but maybe from a widget parent
function ImageViewer:update() end

---Close the ImageViewer
function ImageViewer:onClose() end

return ImageViewer
