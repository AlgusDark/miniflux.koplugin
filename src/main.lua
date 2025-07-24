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
local logger = require('logger')

local MinifluxAPI = require('api/miniflux_api')
local MinifluxSettings = require('features/settings/settings')
local Menu = require('features/menu/menu')
local EntryEntity = require('domains/entries/entry_entity')
local UpdateSettings = require('features/menu/settings/update_settings')
local EntryService = require('features/entries/services/entry_service')
local QueueService = require('features/sync/services/queue_service')

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field is_doc_only boolean Whether plugin is document-only
---@field download_dir string Full path to download directory
---@field settings MinifluxSettings Settings instance
---@field api MinifluxAPI Miniflux-specific API instance
---@field feeds Feeds Feeds domain module
---@field categories Categories Categories domain module
---@field entries Entries Entries domain module
---@field entry_service EntryService Entry service instance
---@field queue_service QueueService Unified queue management service instance
---@field readerLink MinifluxReaderLink ReaderLink enhancement module instance
---@field subprocesses_pids table[] List of subprocess PIDs for cleanup
---@field subprocesses_collector boolean|nil Flag indicating if subprocess collector is active
---@field subprocesses_collect_interval number Interval for subprocess collection in seconds
---@field browser MinifluxBrowser|nil Browser instance for UI navigation
---@field wrapped_onClose table|nil Wrapped ReaderUI onClose method for metadata preservation
---@field ui ReaderUI|nil ReaderUI instance when running in reader context
local Miniflux = WidgetContainer:extend({
    name = 'miniflux',
    is_doc_only = false,
    settings = nil,
    subprocesses_pids = {},
    subprocesses_collector = nil,
    subprocesses_collect_interval = 10,
})

---Register a module with the plugin for event handling
---@param name string Module name
---@param module table Module instance
function Miniflux:registerModule(name, module)
    if name then
        self[name] = module -- Direct property access like ReaderUI
        module.name = 'miniflux_' .. name
    end
    table.insert(self, module) -- Add to widget hierarchy
end

---Handle FlushSettings event from UIManager
function Miniflux:onFlushSettings()
    if self.settings.updated then
        logger.dbg('[Miniflux:Main] Writing settings to disk')
        self.settings:save()
        self.settings.updated = false
    end
end

---Initialize the plugin by setting up all components
---@return nil
function Miniflux:init()
    logger.info('[Miniflux:Main] Initializing plugin')

    local download_dir = self:initializeDownloadDirectory()
    if not download_dir then
        logger.err('[Miniflux:Main] Failed to initialize download directory')
        return
    end
    self.download_dir = download_dir
    logger.dbg('[Miniflux:Main] Download directory:', download_dir)

    self.settings = MinifluxSettings:new()

    -- Register MinifluxAPI as a module after settings initialization
    self:registerModule(
        'api',
        MinifluxAPI:new({
            api_token = self.settings.api_token,
            server_address = self.settings.server_address,
        })
    )

    -- Register domain modules using vertical slice architecture
    local Feeds = require('domains/feeds/feeds')
    local Categories = require('domains/categories/categories')
    local Entries = require('domains/entries/entries')

    self:registerModule('feeds', Feeds:new({ miniflux = self }))
    self:registerModule('categories', Categories:new({ miniflux = self }))
    self:registerModule('entries', Entries:new({ miniflux = self }))

    -- Create services directly with proper dependency order
    self.entry_service = EntryService:new({
        settings = self.settings,
        feeds = self.feeds,
        categories = self.categories,
        entries = self.entries,
        miniflux_plugin = self,
    })

    self.queue_service = QueueService:new({
        entry_service = self.entry_service,
        feeds = self.feeds,
        categories = self.categories,
    })

    local MinifluxBrowser = require('features/browser/browser')
    self.browser = MinifluxBrowser:new({
        title = _('Miniflux'),
        miniflux = self,
    })

    if self.ui and self.ui.document then
        -- Wrap ReaderUI to preserve metadata on close
        local MetadataPreserver = require('features/plugin/utils/metadata_preserver')
        self.wrapped_onClose = MetadataPreserver.wrapReaderClose(self.ui)
    end

    -- Register reader modules only when in ReaderUI context
    logger.dbg(
        '[Miniflux:Main] Checking ReaderUI context - ui.link exists:',
        self.ui and self.ui.link and true or false
    )
    if self.ui and self.ui.link then
        logger.dbg('[Miniflux:Main] Initializing ReaderLink module')
        local MinifluxReaderLink = require('features/reader/modules/miniflux_readerlink')
        self:registerModule('readerLink', MinifluxReaderLink:new({ miniflux = self }))
    end

    logger.dbg(
        '[Miniflux:Main] Checking ReaderUI context - ui.status exists:',
        self.ui and self.ui.status and true or false
    )
    if self.ui and self.ui.status then
        logger.dbg('[Miniflux:Main] Initializing EndOfBook module')
        local MinifluxEndOfBook = require('features/reader/modules/miniflux_end_of_book')
        self:registerModule('endOfBook', MinifluxEndOfBook:new({ miniflux = self }))
    end

    -- Register with KOReader menu system
    self.ui.menu:registerToMainMenu(self)

    -- Check for automatic updates if enabled
    self:checkForAutomaticUpdates()

    logger.info('[Miniflux:Main] Plugin initialization complete')
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
    self.browser:open()
end

---Handle ReaderReady event - called when a document is fully loaded and ready
---This is the proper place to perform auto-mark-as-read for miniflux entries
---@param doc_settings table Document settings instance
---@return nil
function Miniflux:onReaderReady(doc_settings)
    local file_path = self.ui and self.ui.document and self.ui.document.file
    -- Only process if we have a valid file path
    if file_path then
        -- Pass ReaderUI's DocSettings to avoid cache conflicts
        self.entry_service:onReaderReady({
            file_path = file_path,
            doc_settings = doc_settings, -- ReaderUI's cached DocSettings instance
        })
    end
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
    logger.info('[Miniflux:Main] Network connected event received')
    -- Only process if QueueService is available (plugin initialized)
    if self.queue_service then
        -- Check if any queue has items before showing dialog
        local total_count = self.queue_service:getTotalQueueCount()
        logger.dbg('[Miniflux:Main] Queue items pending sync:', total_count)

        if total_count > 0 then
            -- Show sync dialog only if there are items to sync
            logger.info('[Miniflux:Main] Processing offline queues')
            self.queue_service:processAllQueues()
        end
        -- If all queues are empty, do nothing (silent)
    end
end

---Handle device suspend event - terminate background jobs to save battery
function Miniflux:onSuspend()
    logger.info('[Miniflux:Main] Device suspend event - terminating background jobs')
    self:terminateBackgroundJobs()
    -- Queue operations will be processed on next network connection
end

---Check for automatic updates if enabled and due
---@return nil
function Miniflux:checkForAutomaticUpdates()
    if not self.settings or not UpdateSettings.isUpdateCheckDue(self.settings) then
        return
    end

    local CheckUpdates = require('features/menu/settings/check_updates')
    CheckUpdates.checkForUpdates({
        show_no_update = false,
        settings = self.settings,
        plugin_instance = self,
    })
end

---Handle widget close event - cleanup resources and instances
function Miniflux:onCloseWidget()
    logger.info('[Miniflux:Main] Plugin widget closing - cleaning up resources')

    self:terminateBackgroundJobs()
    -- Cancel any scheduled zombie collection
    if self.subprocesses_collector then
        UIManager:unschedule(function()
            self:collectSubprocesses()
        end)
        self.subprocesses_collector = nil
    end

    -- Clear download cache on plugin close
    local DownloadCache = require('features/entries/utils/download_cache')
    DownloadCache.clear()

    -- Revert the wrapped onClose method if it exists
    if self.wrapped_onClose then
        self.wrapped_onClose:revert()
        self.wrapped_onClose = nil
    end
end

return Miniflux
