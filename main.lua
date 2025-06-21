--[[--
Miniflux Plugin for KOReader

This plugin provides integration with Miniflux RSS reader.
This main file acts as a coordinator, delegating to specialized modules.

@module koplugin.miniflux
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Dispatcher = require("dispatcher")
local _ = require("gettext")

-- Import specialized modules
local MinifluxAPI = require("api/api_client")
local MinifluxSettings = require("settings/settings")
local BrowserLauncher = require("browser/browser_launcher")
local MenuManager = require("menu/menu_manager")
local EntryService = require("services/entry_service")

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field is_doc_only boolean Whether plugin is document-only
---@field download_dir string Full path to download directory
---@field settings MinifluxSettings Settings instance
---@field api MinifluxAPI API client instance
---@field browser_launcher BrowserLauncher Browser launcher instance
---@field menu_manager MenuManager Menu construction manager
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

    -- Initialize API client
    self.api = MinifluxAPI:new({
        server_address = self.settings.server_address,
        api_token = self.settings.api_token
    })

    -- Initialize EntryService instance with settings dependency
    self.entry_service = EntryService:new(self.settings)

    -- Initialize browser launcher with dependency injection
    self.browser_launcher = BrowserLauncher:new()
    self.browser_launcher:init(self.settings, self.api, download_dir)

    -- Create menu manager with proper dependency injection
    self.menu_manager = MenuManager:new({
        browser_launcher = self.browser_launcher,
        settings = self.settings,
        api = self.api
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
    local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")

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
    self.menu_manager:addToMainMenu(menu_items)
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
    if self.browser_launcher then
        self.browser_launcher:showMainScreen()
    end
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
            -- Extract entry ID from path
            local entry_id = file_path:match("/miniflux/(%d+)/")

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

    logger.info("Successfully overrode ReaderStatus EndOfBook behavior for miniflux entries")
end

return Miniflux
