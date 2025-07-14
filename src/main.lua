--[[--
**Miniflux Plugin for KOReader**

This plugin provides integration with Miniflux RSS reader.
This main file acts as a coordinator, delegating to specialized modules.
--]]

local WidgetContainer = require('ui/widget/container/widgetcontainer')
local FFIUtil = require('ffi/util')
local UIManager = require('ui/uimanager')
local lfs = require('libs/libkoreader-lfs')
local Dispatcher = require('dispatcher')
local _ = require('gettext')

local APIClient = require('api/api_client')
local MinifluxAPI = require('api/miniflux_api')
local MinifluxSettings = require('settings/settings')
local Menu = require('menu/menu')
local EntryService = require('services/entry_service')
local FeedService = require('services/feed_service')
local CategoryService = require('services/category_service')
local QueueService = require('services/queue_service')
local EntryEntity = require('entities/entry_entity')
local KeyHandlerService = require('services/key_handler_service')
local ReaderLinkService = require('services/readerlink_service')
local UpdateSettings = require('menu/settings/update_settings')

local _static_browser_context = nil

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field is_doc_only boolean Whether plugin is document-only
---@field download_dir string Full path to download directory
---@field settings MinifluxSettings Settings instance
---@field api_client APIClient Generic API client instance
---@field miniflux_api MinifluxAPI Miniflux-specific API instance
---@field entry_service EntryService Entry service instance
---@field feed_service FeedService Feed service instance
---@field category_service CategoryService Category service instance
---@field queue_service QueueService Unified queue management service instance
---@field key_handler_service KeyHandlerService Key handler service instance
---@field readerlink_service ReaderLinkService ReaderLink enhancement service instance
---@field subprocesses_pids table[] List of subprocess PIDs for cleanup
---@field subprocesses_collector boolean|nil Flag indicating if subprocess collector is active
---@field subprocesses_collect_interval number Interval for subprocess collection in seconds
---@field browser MinifluxBrowser|nil Browser instance for UI navigation
local Miniflux = WidgetContainer:extend({
    name = 'miniflux',
    is_doc_only = false,
    settings = nil,
    subprocesses_pids = {},
    subprocesses_collector = nil,
    subprocesses_collect_interval = 10,
})

---Initialize the plugin by setting up all components
---@return nil
function Miniflux:init()
    local download_dir = self:initializeDownloadDirectory()
    if not download_dir then
        return
    end
    self.download_dir = download_dir

    self.settings = MinifluxSettings:new()

    self.api_client = APIClient:new({
        settings = self.settings,
    })
    self.miniflux_api = MinifluxAPI:new({ api_client = self.api_client })

    local FeedRepository = require('repositories/feed_repository')
    local CategoryRepository = require('repositories/category_repository')

    local feed_repository = FeedRepository:new({
        miniflux_api = self.miniflux_api,
        settings = self.settings,
    })

    local category_repository = CategoryRepository:new({
        miniflux_api = self.miniflux_api,
        settings = self.settings,
    })

    self.entry_service = EntryService:new({
        settings = self.settings,
        miniflux_api = self.miniflux_api,
        miniflux_plugin = self,
        feed_repository = feed_repository,
        category_repository = category_repository,
    })

    self.feed_service = FeedService:new({
        feed_repository = feed_repository,
        category_repository = category_repository,
        settings = self.settings,
    })

    self.category_service = CategoryService:new({
        category_repository = category_repository,
        feed_repository = feed_repository,
        settings = self.settings,
    })

    self.queue_service = QueueService:new({
        entry_service = self.entry_service,
        miniflux_api = self.miniflux_api,
    })

    if self.ui and self.ui.document then
        self.key_handler_service = KeyHandlerService:new({
            miniflux_plugin = self,
            entry_service = self.entry_service,
            navigation_service = require('services/navigation_service'),
        })
    end

    if self.ui and self.ui.link then
        self.readerlink_service = ReaderLinkService:new({
            miniflux_plugin = self,
        })
        -- Set cross-service reference for image viewer integration
        if self.key_handler_service then
            self.readerlink_service.key_handler_service = self.key_handler_service
        end
    end

    -- Override ReaderStatus EndOfBook behavior for miniflux entries
    self:overrideEndOfBookBehavior()

    -- Register with KOReader menu system
    self.ui.menu:registerToMainMenu(self)

    -- Check for automatic updates if enabled
    self:checkForAutomaticUpdates()
end

---Initialize the download directory for entries
---@return string|nil Download directory path or nil if failed
function Miniflux:initializeDownloadDirectory()
    local download_dir = EntryEntity.getDownloadDir()

    -- Create the directory if it doesn't exist
    if not lfs.attributes(download_dir, 'mode') then
        local success = lfs.mkdir(download_dir)
        if not success then
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
    Dispatcher:registerAction('miniflux_read_entries', {
        category = 'none',
        event = 'ReadMinifluxEntries',
        title = _('Read Miniflux entries'),
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
    local MinifluxBrowser = require('browser/miniflux_browser')
    local browser = MinifluxBrowser:new({
        title = _('Miniflux'),
        settings = self.settings,
        miniflux_api = self.miniflux_api,
        download_dir = self.download_dir,
        entry_service = self.entry_service,
        feed_service = self.feed_service,
        category_service = self.category_service,
        miniflux_plugin = self, -- Pass plugin reference for context management
    })
    return browser
end

---Override ReaderStatus EndOfBook behavior to handle miniflux entries
---@return nil
function Miniflux:overrideEndOfBookBehavior()
    if not self.ui or not self.ui.status then
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
        if file_path:match('/miniflux/') and file_path:match('%.html$') then
            -- Extract entry ID from path and convert to number
            local entry_id_str = file_path:match('/miniflux/(%d+)/')
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
    -- Pass ReaderUI's DocSettings to avoid cache conflicts
    self.entry_service:onReaderReady({
        file_path = file_path,
        doc_settings = doc_settings, -- ReaderUI's cached DocSettings instance
    })
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

-- =============================================================================
-- SUBPROCESS MANAGEMENT
-- =============================================================================

---Track a new subprocess PID for zombie cleanup
---@param pid number Process ID to track
function Miniflux:trackSubprocess(pid)
    if not pid then
        return
    end

    UIManager:preventStandby()
    table.insert(self.subprocesses_pids, pid)

    -- Start zombie collector if not already running
    if not self.subprocesses_collector then
        self.subprocesses_collector = true
        UIManager:scheduleIn(self.subprocesses_collect_interval, function()
            self:collectSubprocesses()
        end)
    end
end

---Collect finished subprocesses to prevent zombies
function Miniflux:collectSubprocesses()
    self.subprocesses_collector = nil

    if #self.subprocesses_pids > 0 then
        -- Check each subprocess and remove completed ones
        for i = #self.subprocesses_pids, 1, -1 do
            local pid = self.subprocesses_pids[i]
            if FFIUtil.isSubProcessDone(pid) then
                table.remove(self.subprocesses_pids, i)
                UIManager:allowStandby()
            end
        end

        -- If subprocesses still running, schedule next collection
        if #self.subprocesses_pids > 0 then
            self.subprocesses_collector = true
            UIManager:scheduleIn(self.subprocesses_collect_interval, function()
                self:collectSubprocesses()
            end)
        else
        end
    end
end

---Terminate all background subprocesses
function Miniflux:terminateBackgroundJobs()
    if #self.subprocesses_pids > 0 then
        for i = 1, #self.subprocesses_pids do
            FFIUtil.terminateSubProcess(self.subprocesses_pids[i])
        end
        -- Processes will be cleaned up by next collectSubprocesses() call
    end
end

---Check if background jobs are running
---@return boolean true if subprocesses are running
function Miniflux:hasBackgroundJobs()
    return #self.subprocesses_pids > 0
end

-- =============================================================================
-- NETWORK EVENT HANDLERS
-- =============================================================================

---Handle network connected event - process all offline queues
function Miniflux:onNetworkConnected()
    -- Only process if QueueService is available (plugin initialized)
    if self.queue_service then
        -- Check if any queue has items before showing dialog
        local total_count = self.queue_service:getTotalQueueCount()

        if total_count > 0 then
            -- Show sync dialog only if there are items to sync
            self.queue_service:processAllQueues()
        end
        -- If all queues are empty, do nothing (silent)
    end
end

---Handle device suspend event - terminate background jobs to save battery
function Miniflux:onSuspend()
    self:terminateBackgroundJobs()
    -- Queue operations will be processed on next network connection
end

---Handle plugin close event - ensure proper cleanup
function Miniflux:onClose()
    self:terminateBackgroundJobs()
    -- Cancel any scheduled zombie collection
    if self.subprocesses_collector then
        UIManager:unschedule(function()
            self:collectSubprocesses()
        end)
        self.subprocesses_collector = nil
    end
end

---Check for automatic updates if enabled and due
---@return nil
function Miniflux:checkForAutomaticUpdates()
    if not self.settings or not UpdateSettings.isUpdateCheckDue(self.settings) then
        return
    end

    -- Perform automatic update check in background
    UIManager:nextTick(function()
        local CheckUpdates = require('menu/settings/check_updates')
        CheckUpdates.checkForUpdates(false) -- Don't show "no update" dialog for automatic checks
        UpdateSettings.markUpdateCheckPerformed(self.settings)
    end)
end

---Handle widget close event - ensure proper cleanup
function Miniflux:onCloseWidget()
    self:terminateBackgroundJobs()
    -- Cancel any scheduled zombie collection
    if self.subprocesses_collector then
        UIManager:unschedule(function()
            self:collectSubprocesses()
        end)
        self.subprocesses_collector = nil
    end
    -- Cleanup key handler service touch zones
    if self.key_handler_service then
        self.key_handler_service:cleanup()
    end
    -- Cleanup ReaderLink service
    if self.readerlink_service then
        self.readerlink_service:cleanup()
    end
end

return Miniflux
