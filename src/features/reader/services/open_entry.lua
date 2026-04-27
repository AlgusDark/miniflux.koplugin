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
local BrowserContext = require('shared/browser_context')

---@class MinifluxContext
---@field type string Context type ("feed", "category", "global", "local", "unread")
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

    MinifluxEvent:broadcastBrowserCloseRequest({ reason = 'entry_opening' })

    if context then
        -- Persist the context in the module-scoped store BEFORE broadcasting.
        -- Plugin instances may not be registered with UIManager during the
        -- transition into the reader, so the broadcast handler is unreliable
        -- as the sole writer (see #65 follow-up).
        BrowserContext.set(context)
        MinifluxEvent:broadcastMinifluxBrowserContextChange({ context = context })
    end

    local ReaderUI = require('apps/reader/readerui')
    ReaderUI:showReader(file_path)
end

return EntryReader
