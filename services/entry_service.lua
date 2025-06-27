--[[--
Entry Service

This service handles complex entry workflows and orchestration.
It coordinates between the Entry entity, repositories, and infrastructure services
to provide high-level entry operations including UI coordination, navigation,
and dialog management.

@module koplugin.miniflux.services.entry_service
--]]

local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")
local T = require("ffi/util").template
local dump = require("dump")
local Notification = require("utils/notification")

-- Import dependencies
local EntryUtils = require("utils/entry_utils")
local NavigationContext = require("utils/navigation_context")
local ImageDiscovery = require("utils/image_discovery")
local ImageDownload = require("utils/image_download")
local ImageUtils = require("utils/image_utils")
local HtmlUtils = require("utils/html_utils")
local FileUtils = require("utils/file_utils")
local NavigationUtils = require("utils/navigation_utils")
local MetadataLoader = require("utils/metadata_loader")

-- No timeout constants needed - handled by Notification utility

---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field api MinifluxAPI API client instance
local EntryService = {}

---Create a new EntryService instance
---@param settings MinifluxSettings Settings instance
---@param api MinifluxAPI API client instance
---@return EntryService
function EntryService:new(settings, api)
    local instance = {
        settings = settings,
        api = api,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- ENTRY READING WORKFLOW
-- =============================================================================

---Read an entry (download if needed and open)
---@param entry_data table Raw entry data from API
---@param browser? MinifluxBrowser Browser instance to close
---@return boolean success
function EntryService:readEntry(entry_data, browser)
    -- Validate entry data
    local valid, error_msg = EntryUtils.validateForDownload(entry_data)
    if not valid then
        Notification:error(error_msg)
        return false
    end

    -- Update navigation context
    self:_updateNavigationContext(entry_data.id)

    -- Download entry if needed
    local success = self:_downloadEntryContent(entry_data, browser)
    if not success then
        Notification:error(_("Failed to download and show entry"))
        return false
    end

    return true
end

---Download entry content with progress tracking
---@param entry_data table Entry data from API
---@param browser? MinifluxBrowser Browser instance to close
---@return boolean success
function EntryService:_downloadEntryContent(entry_data, browser)
    local title = entry_data.title or _("Untitled Entry")

    -- Create entry directory
    local entry_dir = EntryUtils.getEntryDirectory(entry_data.id)
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end

    local html_file = EntryUtils.getEntryHtmlPath(entry_data.id)

    -- Check if already downloaded
    if EntryUtils.isEntryDownloaded(entry_data.id) then
        self:_closeBrowserAndOpenEntry(browser, html_file)
        return true
    end

    -- Simple progress using close/recreate approach (inline, no abstraction)
    local progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nPreparing download…"), title),
        timeout = nil,
    })

    -- Get entry content
    local content = entry_data.content or entry_data.summary or ""
    local include_images = self.settings.include_images

    -- Update progress
    progress_info:close()
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nScanning for images…"), title),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Process images
    local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
    local images, seen_images = ImageDiscovery.discoverImages(content, base_url)

    -- Update progress with image info
    progress_info:close()
    local image_info = ""
    if include_images and #images > 0 then
        image_info = T(_("\n\nImages found: %1"), #images)
    elseif not include_images and #images > 0 then
        image_info = T(_("\n\nImages: %1 found (skipped)"), #images)
    end
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nFound images%2"), title, image_info),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Download images if enabled
    if include_images and #images > 0 then
        progress_info = self:_downloadImages(images, entry_dir, progress_info, title)
    end

    -- Update progress
    progress_info:close()
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nProcessing content…"), title),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Process and clean content
    local processed_content = ImageUtils.processHtmlImages(content, seen_images, include_images, base_url)
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    -- Update progress
    progress_info:close()
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nCreating HTML file…"), title),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Create and save HTML document
    local html_content = HtmlUtils.createHtmlDocument(entry_data, processed_content)
    local file_success = FileUtils.writeFile(html_file, html_content)
    if not file_success then
        progress_info:close()
        Notification:error(_("Failed to save HTML file"))
        return false
    end

    -- Update progress
    progress_info:close()
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nCreating metadata…"), title),
        timeout = nil,
    })
    UIManager:forceRePaint()

    -- Save metadata
    local metadata = EntryUtils.createMetadata({
        entry_data = entry_data,
        include_images = include_images,
        images_count = #images,
    })
    local metadata_file = EntryUtils.getEntryMetadataPath(entry_data.id)
    local metadata_content = "return " .. dump(metadata)
    FileUtils.writeFile(metadata_file, metadata_content)

    -- Close progress dialog
    progress_info:close()

    -- Show completion summary
    local image_summary = ImageUtils.createDownloadSummary(include_images, images)
    Notification:success({
        text = _("Download completed!") .. "\n\n" .. image_summary,
        timeout = 1,
    })

    -- Close browser and open entry
    self:_closeBrowserAndOpenEntry(browser, html_file)
    return true
end

---Download images with progress tracking
---@param images table Array of image info
---@param entry_dir string Entry directory path
---@param progress_info NotificationInstance Progress dialog (will be updated by reference)
---@param title string Entry title
---@return NotificationInstance Updated progress dialog
function EntryService:_downloadImages(images, entry_dir, progress_info, title)
    local images_downloaded = 0

    for i, img in ipairs(images) do
        -- Update progress for current image
        progress_info:close()
        progress_info = Notification:info({
            text = T(_("Downloading: %1\n\nDownloading image %2 of %3…\n\nImages: %4 / %5 downloaded"),
                title, i, #images, images_downloaded, #images),
            timeout = nil,
        })
        UIManager:forceRePaint()

        local success = ImageDownload.downloadImage({
            url = img.src,
            entry_dir = entry_dir,
            filename = img.filename
        })
        img.downloaded = success

        if success then
            images_downloaded = images_downloaded + 1
        end
    end

    -- Final update
    progress_info:close()
    progress_info = Notification:info({
        text = T(_("Downloading: %1\n\nImage downloads completed\n\nImages: %2 / %3 downloaded"),
            title, images_downloaded, #images),
        timeout = nil,
    })
    UIManager:forceRePaint()

    return progress_info
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

---Generate status messages for entry operations
---@param new_status string The new status ("read" or "unread")
---@return table Status messages with loading, success, and error text
function EntryService:_getStatusMessages(new_status)
    if new_status == "read" then
        return {
            loading = _("Marking entry as read..."),
            success = _("Entry marked as read"),
            error = _("Failed to mark entry as read")
        }
    else
        return {
            loading = _("Marking entry as unread..."),
            success = _("Entry marked as unread"),
            error = _("Failed to mark entry as unread")
        }
    end
end

---Mark an entry as read
---@param entry_id number Entry ID
---@return boolean success
function EntryService:markAsRead(entry_id)
    return self:changeEntryStatus(entry_id, "read")
end

---Mark an entry as unread
---@param entry_id number Entry ID
---@return boolean success
function EntryService:markAsUnread(entry_id)
    return self:changeEntryStatus(entry_id, "unread")
end

---Change entry status with validation and side effects
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:changeEntryStatus(entry_id, new_status)
    if not EntryUtils.isValidId(entry_id) then
        Notification:error(_("Cannot change status: invalid entry ID"))
        return false
    end

    -- Get consolidated status messages
    local messages = self:_getStatusMessages(new_status)

    -- Call API with automatic dialog management
    local success, result = self.api.entries:updateEntries(entry_id, {
        body = { status = new_status },
        dialogs = {
            loading = { text = messages.loading },
            success = { text = messages.success, timeout = 2 },
            error = { text = messages.error, timeout = 5 }
        }
    })

    if success then
        -- Handle side effects after successful status change
        self:onEntryStatusChanged(entry_id, new_status)
        return true
    else
        -- Error dialog already shown by API system
        return false
    end
end

---Handle side effects when entry status changes
---@param entry_id number Entry ID
---@param new_status string New status
---@return nil
function EntryService:onEntryStatusChanged(entry_id, new_status)
    -- Update local metadata
    self:_updateLocalEntryStatus(entry_id, new_status)

    -- If marked as read, schedule local deletion
    if new_status == "read" then
        UIManager:scheduleIn(0.5, function()
            self:deleteLocalEntry(entry_id)
        end)
    end
end

-- =============================================================================
-- UI COORDINATION & FILE OPERATIONS
-- =============================================================================

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@return nil
function EntryService:openEntryFile(html_file)
    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil

    if is_miniflux_entry then
        -- Extract entry ID from path and convert to number for navigation context
        local entry_id_str = html_file:match("/miniflux/(%d+)/")
        local entry_id = entry_id_str and tonumber(entry_id_str)

        if entry_id then
            -- Update global navigation context with this entry
            -- Note: We don't have browsing context when opening existing files,
            -- so navigation will be global unless the user came from a browser session
            if not NavigationContext.hasValidContext() then
                -- Set global context if no context exists
                NavigationContext.setContext(entry_id)
            else
                -- Update current entry in existing context
                NavigationContext.updateCurrentEntry(entry_id)
            end
        end
    end

    -- Open the file - EndOfBook event handler will detect miniflux entries automatically
    ReaderUI:showReader(html_file)
end

---Show end of entry dialog with navigation options
---@param entry_info table Entry information with file_path and entry_id
---@return table|nil Dialog reference for caller management or nil if failed
function EntryService:showEndOfEntryDialog(entry_info)
    if not entry_info or not entry_info.file_path or not entry_info.entry_id then
        return nil
    end

    -- Load entry metadata to check current status with error handling
    local metadata = nil
    local metadata_success = pcall(function()
        metadata = MetadataLoader.loadCurrentEntryMetadata(entry_info)
    end)

    if not metadata_success then
        -- If metadata loading fails, assume unread status
        metadata = { status = "unread" }
    end

    -- Use status for business logic
    local entry_status = metadata and metadata.status or "unread"

    -- Use utility functions for button text and callback
    local mark_button_text = EntryUtils.getStatusButtonText(entry_status)
    local mark_callback
    if EntryUtils.isEntryRead(entry_status) then
        mark_callback = function()
            self:markEntryAsUnread(entry_info)
        end
    else
        mark_callback = function()
            self:markEntryAsRead(entry_info)
        end
    end

    -- Create dialog and return reference for caller management
    local dialog = nil
    local dialog_success = pcall(function()
        dialog = ButtonDialogTitle:new({
            title = _("You've reached the end of the entry."),
            title_align = "center",
            buttons = {
                {
                    {
                        text = _("← Previous"),
                        callback = function()
                            UIManager:close(dialog)
                            NavigationUtils.navigateToEntry(entry_info, {
                                navigation_options = { direction = "previous" },
                                settings = self.settings,
                                api = self.api,
                                entry_service = self
                            })
                        end,
                    },
                    {
                        text = _("Next →"),
                        callback = function()
                            UIManager:close(dialog)
                            NavigationUtils.navigateToEntry(entry_info, {
                                navigation_options = { direction = "next" },
                                settings = self.settings,
                                api = self.api,
                                entry_service = self
                            })
                        end,
                    },
                },
                {
                    {
                        text = _("⚠ Delete local entry"),
                        callback = function()
                            UIManager:close(dialog)
                            self:deleteLocalEntryFromInfo(entry_info)
                        end,
                    },
                    {
                        text = mark_button_text,
                        callback = function()
                            UIManager:close(dialog)
                            mark_callback()
                        end,
                    },
                },
                {
                    {
                        text = _("⌂ Miniflux folder"),
                        callback = function()
                            UIManager:close(dialog)
                            self:openMinifluxFolder()
                        end,
                    },
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(dialog)
                        end,
                    },
                },
            },
        })
    end)

    if dialog_success and dialog then
        -- Show dialog and return reference for caller management
        UIManager:show(dialog)
        return dialog
    else
        -- If dialog creation fails, show a simple error message
        Notification:error(_("Failed to create end of entry dialog"))
        return nil
    end
end

-- =============================================================================
-- ENTRY OPERATIONS FROM DIALOG
-- =============================================================================

---Entry operations (entry_id is already a number from boundary conversion)
---@param entry_info table Current entry information
---@return nil
function EntryService:markEntryAsRead(entry_info)
    self:markAsRead(entry_info.entry_id)
end

---Mark an entry as unread (entry_id is already a number)
---@param entry_info table Current entry information
---@return nil
function EntryService:markEntryAsUnread(entry_info)
    self:markAsUnread(entry_info.entry_id)
end

---Delete a local entry (with validation, entry_id is already a number)
---@param entry_info table Current entry information
---@return nil
function EntryService:deleteLocalEntryFromInfo(entry_info)
    local entry_id = entry_info.entry_id

    if not EntryUtils.isValidId(entry_id) then
        Notification:warning(_("Cannot delete: invalid entry ID"))
        return
    end

    self:deleteLocalEntry(entry_id)
end

-- =============================================================================
-- PRIVATE HELPER METHODS
-- =============================================================================

---Update local entry metadata status
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:_updateLocalEntryStatus(entry_id, new_status)
    local metadata_file = EntryUtils.getEntryMetadataPath(entry_id)

    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return false
    end

    local success, metadata = pcall(dofile, metadata_file)
    if not success or not metadata then
        return false
    end

    metadata.status = new_status
    local metadata_content = "return " .. dump(metadata)
    return FileUtils.writeFile(metadata_file, metadata_content)
end

---Delete a local entry
---@param entry_id number Entry ID
---@return boolean success
function EntryService:deleteLocalEntry(entry_id)
    local entry_dir = EntryUtils.getEntryDirectory(entry_id)

    local success = pcall(function()
        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end
        FFIUtil.purgeDir(entry_dir)
        return true
    end)

    if success then
        Notification:success(_("Local entry deleted successfully"))

        -- Open Miniflux folder
        self:openMinifluxFolder()

        return true
    else
        Notification:error(_("Failed to delete local entry"))
        return false
    end
end

---Update navigation context
---@param entry_id number Entry ID
---@return nil
function EntryService:_updateNavigationContext(entry_id)
    NavigationContext.updateCurrentEntry(entry_id)
end

---Close browser and open entry file
---@param browser? MinifluxBrowser Browser instance
---@param html_file string HTML file path
---@return nil
function EntryService:_closeBrowserAndOpenEntry(browser, html_file)
    -- Close browser first
    if browser and browser.closeAll then
        browser:closeAll()
    end

    -- Small delay to ensure browser cleanup, then open reader
    UIManager:scheduleIn(0.1, function()
        ReaderUI:showReader(html_file)
    end)
end

---Open the Miniflux folder in file manager
---@return nil
function EntryService:openMinifluxFolder()
    local download_dir = EntryUtils.getDownloadDir()

    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(download_dir)
    else
        FileManager:showFiles(download_dir)
    end
end

return EntryService
