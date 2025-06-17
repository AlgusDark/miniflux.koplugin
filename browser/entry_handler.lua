--[[--
Entry Handler - Consolidated Implementation

Single-file entry handler that combines all entry-related functionality.
Handles entry downloading, display, navigation, and file management.

@module miniflux.browser.entry_handler
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

---@class EntryHandler
---@field api MinifluxAPI
---@field settings table
---@field download_dir string
local EntryHandler = {}

---Create a new entry handler instance
---@param api MinifluxAPI API client instance
---@param settings table Settings module instance  
---@param download_dir string Download directory path
---@return EntryHandler
function EntryHandler:new(api, settings, download_dir)
    local obj = {
        api = api,
        settings = settings,
        download_dir = download_dir
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- =============================================================================
-- NAVIGATION CONTEXT MANAGEMENT
-- =============================================================================

function EntryHandler:setNavigationContext(context, entry_id)
    -- Store local context for later use
    self.current_context = context
    self.current_entry_id = entry_id
    
    -- IMPORTANT: Set up the global NavigationContext that navigation utilities expect
    local NavigationContext = require("browser/utils/navigation_context")
    
    if context.type == "feed_entries" and context.feed_id then
        NavigationContext.setFeedContext(context.feed_id, entry_id)
    elseif context.type == "category_entries" and context.category_id then
        NavigationContext.setCategoryContext(context.category_id, entry_id)
    else
        -- For unread_entries or any other context, use global
        NavigationContext.setGlobalContext(entry_id)
    end
end



-- =============================================================================
-- ENTRY DISPLAY AND DOWNLOAD
-- =============================================================================

function EntryHandler:showEntry(entry, browser)
    if not self.download_dir then
        UIManager:show(InfoMessage:new{
            text = _("Download directory not configured"),
            timeout = 3,
        })
        return
    end
    
    -- For now, delegate to the existing EntryUtils
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.showEntry({
        entry = entry,
        api = self.api,
        download_dir = self.download_dir,
        browser = browser
    })
end











-- =============================================================================
-- END OF ENTRY DIALOG AND NAVIGATION
-- =============================================================================

function EntryHandler:showEndOfEntryDialog()
    local EntryUtils = require("browser/utils/entry_utils")
    local current_entry = EntryUtils._current_miniflux_entry
    if not current_entry then
        return
    end
    
    self:closeEndOfEntryDialog()
    
    -- Load entry metadata to check status
    local metadata = self:loadCurrentEntryMetadata(current_entry)
    local entry_status = metadata and metadata.status or "unread"
    
    local mark_button_text, mark_callback
    if entry_status == "read" then
        mark_button_text = _("✓ Mark as unread")
        mark_callback = function()
            self:markEntryAsUnread(current_entry)
        end
    else
        mark_button_text = _("✓ Mark as read")
        mark_callback = function()
            self:markEntryAsRead(current_entry)
        end
    end
    
    self._current_end_dialog = ButtonDialogTitle:new{
        title = _("You've reached the end of the entry."),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("← Previous"),
                    callback = function()
                        self:closeEndOfEntryDialog()
                        self:navigateToPreviousEntry(current_entry)
                    end,
                },
                {
                    text = _("Next →"),
                    callback = function()
                        self:closeEndOfEntryDialog()
                        self:navigateToNextEntry(current_entry)
                    end,
                },
            },
            {
                {
                    text = _("⚠ Delete local entry"),
                    callback = function()
                        self:closeEndOfEntryDialog()
                        self:deleteLocalEntry(current_entry)
                    end,
                },
                {
                    text = mark_button_text,
                    callback = function()
                        self:closeEndOfEntryDialog()
                        mark_callback()
                    end,
                },
            },
            {
                {
                    text = _("⌂ Miniflux folder"),
                    callback = function()
                        self:closeEndOfEntryDialog()
                        self:openMinifluxFolder(current_entry)
                    end,
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeEndOfEntryDialog()
                    end,
                },
            },
        },
    }
    
    UIManager:show(self._current_end_dialog)
end

---Close any existing EndOfEntry dialog
function EntryHandler:closeEndOfEntryDialog()
    if self._current_end_dialog then
        UIManager:close(self._current_end_dialog)
        self._current_end_dialog = nil
    end
end

-- =============================================================================
-- ENTRY NAVIGATION AND STATUS MANAGEMENT
-- =============================================================================

---Navigate to the previous entry
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:navigateToPreviousEntry(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.navigateToPreviousEntry(entry_info)
end

---Navigate to the next entry  
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:navigateToNextEntry(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.navigateToNextEntry(entry_info)
end

---Mark an entry as read on the server
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:markEntryAsRead(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.markEntryAsRead(entry_info)
end

---Mark an entry as unread on the server
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:markEntryAsUnread(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.markEntryAsUnread(entry_info)
end

---Delete a local entry from disk
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:deleteLocalEntry(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.deleteLocalEntry(entry_info)
end

---Open the Miniflux folder in file manager
---@param entry_info table Current entry information with file_path and entry_id
function EntryHandler:openMinifluxFolder(entry_info)
    local EntryUtils = require("browser/utils/entry_utils")
    EntryUtils.openMinifluxFolder(entry_info)
end

-- =============================================================================
-- UTILITY METHODS
-- =============================================================================

---Load current entry metadata from local file
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Metadata table or nil if not found/failed
function EntryHandler:loadCurrentEntryMetadata(entry_info)
    if not entry_info.file_path or not entry_info.entry_id then
        return nil
    end
    
    local entry_dir = entry_info.file_path:match("(.*)/entry%.html$")
    if not entry_dir then
        return nil
    end
    
    local metadata_file = entry_dir .. "/metadata.lua"
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return nil
    end
    
    local success, metadata = pcall(dofile, metadata_file)
    if success and metadata then
        return metadata
    end
    
    return nil
end



return EntryHandler 