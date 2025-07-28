--[[--
**Entry Reader Service**

Handles opening miniflux entries with KOReader's ReaderUI. This service manages
the complete workflow of opening entries including browser cleanup, context
management, and reader integration.

Future improvements planned:
- Integration with DocSettingsLoad event
- Enhanced metadata preservation
--]]

local MinifluxEvent = require('shared/event')

---@class MinifluxContext
---@field type string Context type ("feed", "category", "global", "local")
---@field id? number Feed or category ID
---@field ordered_entries? table[] Ordered entries for navigation

---@class EntryReader
local EntryReader = {}

---@class OpenEntryOptions
---@field context? MinifluxContext Navigation context for entry navigation

---Open a miniflux entry with ReaderUI
---@param file_path string Path to the entry HTML file to open
---@param opts? OpenEntryOptions Options for entry opening
---@return nil
function EntryReader.openEntry(file_path, opts)
    opts = opts or {}
    local context = opts.context

    MinifluxEvent:broadcastMinifluxBrowserCloseRequested({ reason = 'entry_opening' })

    if context then
        MinifluxEvent:broadcastMinifluxBrowserContextChange({ context = context })
    end

    local ReaderUI = require('apps/reader/readerui')
    ReaderUI:showReader(file_path)
end

return EntryReader
