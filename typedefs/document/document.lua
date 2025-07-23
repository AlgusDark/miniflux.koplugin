---@meta
---@module 'document/document'

---Document - Abstract interface to a document in KOReader
---
---The Document class provides the foundational interface for all document types,
---including PDFs, EPUBs, text files, and other supported formats. It handles:
---- File management and metadata
---- Page rendering and caching
---- Document navigation and structure
---- Color and display capabilities
---- Security and locking features
---
---This serves as the base class for all document-specific implementations
---while providing a unified interface for the reader application.
---@class Document
---@field file string Path to the document file
---@field _document table Engine-specific document instance
---@field links table|nil Document links and navigation
---@field bbox table|nil Bounding box override from original page
---@field is_open boolean Whether document was opened successfully
---@field is_locked boolean Whether document needs password unlock
---@field is_edited boolean Whether document has unsaved changes
---@field is_color_capable boolean Whether document supports color rendering
---@field color_bb_type number Blitbuffer type for color rendering
local Document = {}

---Extend Document class with subclass prototype
---@param subclass_prototype table|nil Prototype for subclass
---@return Document Extended document class
function Document:extend(subclass_prototype) end

---Open document from file path
---@param self Document
---@param filename string Path to document file
---@return boolean success Whether document opened successfully
function Document:open(filename) end

---Close document and cleanup resources
---@param self Document
function Document:close() end

---Check if document is open and ready
---@param self Document
---@return boolean ready Document ready state
function Document:isOpen() end

---Get document page count
---@param self Document
---@return number pages Total number of pages
function Document:getPageCount() end

---Get image from position (if supported by document type)
---@param self Document
---@param pos table Position coordinates
---@param want_frames boolean|nil Whether to include frame data
---@param want_image boolean|nil Whether to include image data
---@return table|nil image Image data or nil if not found
function Document:getImageFromPosition(pos, want_frames, want_image) end

return Document
