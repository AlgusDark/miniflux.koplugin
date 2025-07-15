---@meta
---@module 'apps/reader/readerui'

---ReaderUI - Main reader application interface for KOReader
---
---ReaderUI serves as the central coordinator for the document reading experience, managing:
---- Document lifecycle (opening, closing, rendering, caching)
---- Reader module orchestration (highlights, bookmarks, annotations, etc.)
---- User interface coordination and widget management
---- Input handling and gesture processing for reading interactions
---- View management and display modes (paging, scrolling, zooming)
---- Integration with file management and document settings
---- Plugin system integration and module registration
---
---As the primary application controller, ReaderUI bridges document engines with
---the user interface, providing a cohesive reading experience across different
---document formats and device capabilities.
---@class ReaderUI : InputContainer
---@field instance ReaderUI|nil Static reference to current ReaderUI singleton instance
---@field name string Module name identifier
---@field active_widgets table[] Currently active widget instances
---@field dialog table|nil Parent container reference if in dialog mode
---@field document table Document interface for current file
---@field password string|nil Password for document unlock
---@field postInitCallback function|nil Callback after initialization
---@field postReaderReadyCallback function|nil Callback when reader is ready
---@field view table Document view management
---@field link ReaderLink Link handling module
---@field highlight table Highlight management module
---@field bookmark table Bookmark management module
---@field annotation table Annotation management module
---@field menu table Reader menu system
---@field config table Configuration management
---@field rolling table Rolling view module (for reflowable documents)
---@field paging table Paging view module (for fixed layout documents)
---@field doc_settings DocSettings Document settings for current file
local ReaderUI = {}

---Register a reader module with the UI
---@param self ReaderUI
---@param name string Module name
---@param ui_module table Module instance
---@param always_active? boolean Whether module should always be active
function ReaderUI:registerModule(name, ui_module, always_active) end

---Initialize the reader UI with document
---@param self ReaderUI
---@param document table Document to open
function ReaderUI:init(document) end

---Handle document opening process
---@param self ReaderUI
---@param file string Path to document file
function ReaderUI:showReader(file) end

---Close current document and clean up
---@param self ReaderUI
---@param full_refresh boolean|nil Whether to do a full screen refresh
function ReaderUI:onClose(full_refresh) end

---Check if reader is ready for interaction
---@param self ReaderUI
---@return boolean ready Whether reader is fully initialized
function ReaderUI:isReaderReady() end

---Register callback to be called when reader is ready
---@param self ReaderUI
---@param callback function Callback to register
function ReaderUI:registerPostReaderReadyCallback(callback) end

return ReaderUI
