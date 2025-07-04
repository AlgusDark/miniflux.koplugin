--[[--
Miniflux Plugin for KOReader

This plugin provides integration with Miniflux RSS reader.
This main file acts as a coordinator, delegating to specialized modules.

@module koplugin.miniflux
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Dispatcher = require("dispatcher")
local _ = require("gettext")

-- Import specialized modules
local APIClient = require("api/api_client")
local MinifluxAPI = require("api/miniflux_api")
local MinifluxSettings = require("settings/settings")
local Menu = require("menu/menu")
local EntryService = require("services/entry_service")
local EntryEntity = require("entities/entry_entity")

-- Static browser context shared across all plugin instances
local _static_browser_context = nil

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field is_doc_only boolean Whether plugin is document-only
---@field download_dir string Full path to download directory
---@field settings MinifluxSettings Settings instance
---@field api_client APIClient Generic API client instance
---@field miniflux_api MinifluxAPI Miniflux-specific API instance
---@field entry_service EntryService Entry service instance
local Miniflux = WidgetContainer:extend({
    name = "miniflux",
    is_doc_only = false,
    settings = nil,
})

---Initialize the plugin by setting up all components
---@return nil
function Miniflux:init()
    logger.info("Initializing Miniflux plugin")

    -- Initialize download directory
    local download_dir = self:initializeDownloadDirectory()
    if not download_dir then
        logger.err("Failed to initialize download directory")
        return
    end
    self.download_dir = download_dir

    -- Initialize settings instance
    self.settings = MinifluxSettings:new()

    -- Initialize API client (generic HTTP client)
    self.api_client = APIClient:new({
        settings = self.settings
    })

    -- Initialize Miniflux-specific API
    self.miniflux_api = MinifluxAPI:new({ api_client = self.api_client })

    -- Initialize EntryService instance with settings, miniflux API, and plugin dependencies
    self.entry_service = EntryService:new({
        settings = self.settings,
        miniflux_api = self.miniflux_api,
        miniflux_plugin = self
    })

    -- Override ReaderStatus EndOfBook behavior for miniflux entries
    self:overrideEndOfBookBehavior()

    -- Register with KOReader menu system
    self.ui.menu:registerToMainMenu(self)

    logger.info("Miniflux plugin initialization complete")
end

---Initialize the download directory for entries
---@return string|nil Download directory path or nil if failed
function Miniflux:initializeDownloadDirectory()
    local download_dir = EntryEntity.getDownloadDir()

    -- Create the directory if it doesn't exist
    if not lfs.attributes(download_dir, "mode") then
        logger.dbg("Miniflux: Creating download directory:", download_dir)
        local success = lfs.mkdir(download_dir)
        if not success then
            logger.err("Failed to create download directory:", download_dir)
            return nil
        end
    end

    return download_dir
end

---Add Miniflux items to the main menu (called by KOReader)
---@param menu_items table The main menu items table
---@return nil
function Miniflux:addToMainMenu(menu_items)
    menu_items.miniflux = Menu.build(self)
end

---Handle dispatcher events (method required by KOReader)
---@return nil
function Miniflux:onDispatcherRegisterActions()
    Dispatcher:registerAction("miniflux_read_entries", {
        category = "none",
        event = "ReadMinifluxEntries",
        title = _("Read Miniflux entries"),
        general = true,
    })
end

---Handle the read entries dispatcher event
---@return nil
function Miniflux:onReadMinifluxEntries()
    local browser = self:createBrowser()
    browser:open()
end

---Create and return a new browser instance (BookList-based)
---@return MinifluxBrowser Browser instance
function Miniflux:createBrowser()
    local MinifluxBrowser = require("browser/miniflux_browser")
    local browser = MinifluxBrowser:new({
        title = _("Miniflux"),
        settings = self.settings,
        miniflux_api = self.miniflux_api,
        download_dir = self.download_dir,
        entry_service = self.entry_service,
        miniflux_plugin = self, -- Pass plugin reference for context management
    })
    return browser
end

---Override ReaderStatus EndOfBook behavior to handle miniflux entries
---@return nil
function Miniflux:overrideEndOfBookBehavior()
    if not self.ui or not self.ui.status then
        logger.warn("Cannot override EndOfBook behavior - ReaderStatus not available")
        return
    end

    -- Save the original onEndOfBook method
    local original_onEndOfBook = self.ui.status.onEndOfBook

    -- Replace with our custom handler
    self.ui.status.onEndOfBook = function(reader_status_instance)
        -- Check if current document is a miniflux HTML file
        if not self.ui or not self.ui.document or not self.ui.document.file then
            -- Fallback to original behavior
            return original_onEndOfBook(reader_status_instance)
        end

        local file_path = self.ui.document.file

        -- Check if this is a miniflux HTML entry
        if file_path:match("/miniflux/") and file_path:match("%.html$") then
            -- Extract entry ID from path and convert to number
            local entry_id_str = file_path:match("/miniflux/(%d+)/")
            local entry_id = entry_id_str and tonumber(entry_id_str)

            if entry_id then
                -- Show the end of entry dialog with entry info as parameter
                self.entry_service:showEndOfEntryDialog({
                    file_path = file_path,
                    entry_id = entry_id,
                })
                return -- Don't call original handler
            end
        end

        -- For non-miniflux files, use original behavior
        return original_onEndOfBook(reader_status_instance)
    end
end

---Handle ReaderReady event - called when a document is fully loaded and ready
---This is the proper place to perform auto-mark-as-read for miniflux entries
---@param doc_settings table Document settings instance
---@return nil
function Miniflux:onReaderReady(doc_settings)
    local file_path = self.ui and self.ui.document and self.ui.document.file
    self.entry_service:onReaderReady({ file_path = file_path })
end

-- =============================================================================
-- BROWSER CONTEXT MANAGEMENT
-- =============================================================================

---Set the browser context (called when browser opens entry)
---@param context {type: "feed"|"category"|"global"}|nil Browser context or nil
---@return nil
function Miniflux:setBrowserContext(context)
    _static_browser_context = context
end

---Get the current browser context
---@return {type: "feed"|"category"|"global"}|nil Current context or nil
function Miniflux:getBrowserContext()
    return _static_browser_context
end

return Miniflux
