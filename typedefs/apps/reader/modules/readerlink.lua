---@meta
---@module 'apps/reader/modules/readerlink'

---ReaderLink - Document link handling for KOReader
---
---ReaderLink provides comprehensive link interaction capabilities for documents including:
---- Internal navigation (table of contents, page references, footnotes)
---- External link handling (web URLs, email addresses, file references)
---- Wikipedia integration with offline EPUB support
---- Link visualization with overlay boxes and highlighting
---- Customizable external link dialog with plugin extensions
---- Location history and navigation stack for back/forward functionality
---
---The module integrates with various document types and provides a unified interface
---for link interaction across PDF, EPUB, and other supported formats.
---@class ReaderLink : InputContainer
---@field location_stack table[] Navigation history stack for back functionality
---@field forward_location_stack table[] Forward navigation stack
---@field _external_link_buttons table[] Registered external link dialog buttons
---@field supported_external_schemes table[] Supported URL schemes for external links
---@field ui ReaderUI Reference to the main reader UI
---@field document table Reference to the current document
local ReaderLink = {}

---Initialize ReaderLink with touch zones and key events
---@param self ReaderLink
function ReaderLink:init() end

---Handle tap gesture for link detection
---@param self ReaderLink
---@param arg table Gesture arguments
---@param ges table Gesture data
---@return boolean handled Whether the gesture was handled
function ReaderLink:onTap(arg, ges) end

---Add button to external link dialog
---@param self ReaderLink
---@param button_id string Unique identifier for the button
---@param callback function Function to call when button is tapped
function ReaderLink:addToExternalLinkDialog(button_id, callback) end

---Navigate to internal link destination
---@param self ReaderLink
---@param link_dest table Link destination data
function ReaderLink:onGotoLink(link_dest) end

---Navigate back in location history
---@param self ReaderLink
function ReaderLink:onGoBack() end

---Navigate forward in location history
---@param self ReaderLink
function ReaderLink:onGoForward() end

---Handle external link (web URL, email, etc.)
---@param self ReaderLink
---@param link_url string External link URL
function ReaderLink:onExternalLink(link_url) end

return ReaderLink