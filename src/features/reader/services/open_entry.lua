--[[--
**Entry Reader Service**

Handles opening miniflux entries with KOReader's ReaderUI. This service manages
the complete workflow of opening entries including browser cleanup, context
management, and reader integration.

This service is specifically designed for miniflux entries and replaces the
generic openWithReader function with entry-focused functionality.

Future improvements planned:
- Event-driven browser closing
- Memory-based context management  
- Integration with DocSettingsLoad event
- Enhanced metadata preservation
--]]

local MinifluxEvent = require('shared/utils/event')

---@class MinifluxContext
---@field type string Context type ("feed", "category", "global", "local")
---@field id? number Feed or category ID
---@field ordered_entries? table[] Ordered entries for navigation

---@class EntryReader
local EntryReader = {}

-- =============================================================================
-- ENTRY OPENING FUNCTIONALITY
-- =============================================================================

---@class OpenEntryOptions
---@field context? MinifluxContext Navigation context for entry navigation

---Open a miniflux entry with ReaderUI
---
---This function handles the complete workflow of opening an entry:
---1. Browser cleanup
---2. Context preservation for navigation
---3. Reader UI initialization
---
---@param file_path string Path to the entry HTML file to open
---@param opts? OpenEntryOptions Options for entry opening
---@return nil
function EntryReader.openEntry(file_path, opts)
    opts = opts or {}
    local context = opts.context

    -- Phase 1: Browser cleanup (event-driven approach)
    -- Broadcast close event to any open browser instances
    MinifluxEvent:broadcastMinifluxBrowserCloseRequested({ reason = 'entry_opening' })

    -- Phase 2: Context preservation
    -- TODO: Replace file-based cache with memory-based context management
    -- TODO: Investigate attaching context via DocSettingsLoad event
    if context then
        local BrowserCache = require('features/browser/utils/browser_cache')
        BrowserCache.save(context)
    end

    -- Phase 3: Reader initialization
    local ReaderUI = require('apps/reader/readerui')
    ReaderUI:showReader(file_path)
end

return EntryReader
