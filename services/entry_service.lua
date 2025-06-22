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
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import dependencies
local EntryUtils = require("utils/entry_utils")
local MinifluxAPI = require("api/api_client")
local NavigationContext = require("utils/navigation_context")
local ProgressUtils = require("utils/progress_utils")
local ImageUtils = require("utils/image_utils")
local HtmlUtils = require("utils/html_utils")
local NavigationService = require("services/navigation_service")
local MetadataLoader = require("utils/metadata_loader")

---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field navigation_service NavigationService Navigation service for entry navigation
local EntryService = {}

---Create a new EntryService instance
---@param settings MinifluxSettings Settings instance
---@return EntryService
function EntryService:new(settings)
    local instance = {
        settings = settings,
        navigation_service = NavigationService:new(settings),
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
        self:_showError(error_msg)
        return false
    end

    -- Update navigation context
    self:_updateNavigationContext(entry_data.id)

    -- Download entry if needed
    local success = self:_downloadEntryContent(entry_data, browser)
    if not success then
        self:_showError(_("Failed to download and show entry"))
        return false
    end

    return true
end

---Download entry content with progress tracking
---@param entry_data table Entry data from API
---@param browser? MinifluxBrowser Browser instance to close
---@return boolean success
function EntryService:_downloadEntryContent(entry_data, browser)
    local progress = ProgressUtils.createEntryProgress(entry_data.title or _("Untitled Entry"))

    -- Create entry directory
    local entry_dir = EntryUtils.getEntryDirectory(entry_data.id)
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end

    local html_file = EntryUtils.getEntryHtmlPath(entry_data.id)

    -- Check if already downloaded
    if EntryUtils.isEntryDownloaded(entry_data.id) then
        progress:close()
        self:_closeBrowserAndOpenEntry(browser, html_file)
        return true
    end

    progress:update(_("Preparing download…"))

    -- Get entry content
    local content = entry_data.content or entry_data.summary or ""
    local include_images = self.settings.include_images

    progress:update(_("Scanning for images…"))

    -- Process images
    local base_url = entry_data.url and socket_url.parse(entry_data.url) or nil
    local images, seen_images = ImageUtils.discoverImages(content, base_url)

    progress:setImageConfig(include_images, #images)

    -- Download images if enabled
    if include_images and #images > 0 then
        self:_downloadImages(images, entry_dir, progress)
    end

    progress:update(_("Processing content…"))

    -- Process and clean content
    local processed_content = ImageUtils.processHtmlImages(content, seen_images, include_images, base_url)
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    progress:update(_("Creating HTML file…"))

    -- Create and save HTML document
    local html_content = HtmlUtils.createHtmlDocument(entry_data, processed_content)
    local file_success = self:_saveFile(html_file, html_content)
    if not file_success then
        progress:close()
        self:_showError(_("Failed to save HTML file"))
        return false
    end

    progress:update(_("Creating metadata…"))

    -- Save metadata
    local metadata = EntryUtils.createMetadata({
        entry_data = entry_data,
        include_images = include_images,
        images_count = #images,
    })
    local metadata_file = EntryUtils.getEntryMetadataPath(entry_data.id)
    local metadata_content = "return " .. self:_tableToString(metadata)
    self:_saveFile(metadata_file, metadata_content)

    progress:close()

    -- Show completion summary
    local image_summary = ImageUtils.createDownloadSummary(include_images, images)
    UIManager:show(InfoMessage:new({
        text = _("Download completed!") .. "\n\n" .. image_summary,
        timeout = 1,
    }))

    -- Close browser and open entry
    self:_closeBrowserAndOpenEntry(browser, html_file)
    return true
end

---Download images with progress tracking
---@param images table Array of image info
---@param entry_dir string Entry directory path
---@param progress table Progress tracker
---@return nil
function EntryService:_downloadImages(images, entry_dir, progress)
    local time = require("ui/time")
    local time_prev = time.now()

    for i, img in ipairs(images) do
        -- Update progress for each image
        progress:update(T(_("Downloading image %1 of %2…"), i, #images), { current = i - 1, total = #images }, true)

        -- Process can be interrupted every second
        if time.to_ms(time.since(time_prev)) > 1000 then
            time_prev = time.now()
            local go_on = progress:update(
                T(_("Downloading image %1 of %2…"), i, #images),
                { current = i - 1, total = #images },
                true
            )
            if not go_on then
                break
            end
        end

        local success = ImageUtils.downloadImage(img.src, entry_dir, img.filename)
        img.downloaded = success

        if success then
            progress:incrementDownloadedImages()
        end
    end

    -- Final update
    progress:update(_("Image downloads completed"), { current = progress.downloaded_images, total = #images })
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

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
        self:_showError(_("Cannot change status: invalid entry ID"))
        return false
    end

    -- Show loading message
    local action_text = new_status == "read" and _("Marking entry as read...") or _("Marking entry as unread...")
    local loading_info = InfoMessage:new({ text = action_text })
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    -- Create API client
    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token,
        })
    end)

    if not api_success or not api then
        UIManager:close(loading_info)
        self:_showError(_("API not available"))
        return false
    end

    -- Call appropriate API method
    local success, result
    if new_status == "read" then
        success, result = api.entries:markAsRead(entry_id)
    else
        success, result = api.entries:markAsUnread(entry_id)
    end

    UIManager:close(loading_info)

    if success then
        -- Handle side effects
        self:onEntryStatusChanged(entry_id, new_status)

        local success_text = new_status == "read" and _("Entry marked as read") or _("Entry marked as unread")
        UIManager:show(InfoMessage:new({
            text = success_text,
            timeout = 2,
        }))
        return true
    else
        local error_text = new_status == "read" and _("Failed to mark entry as read: ") .. tostring(result)
            or _("Failed to mark entry as unread: ") .. tostring(result)
        self:_showError(error_text)
        return false
    end
end

---Handle side effects when entry status changes
---@param entry_id number Entry ID
---@param new_status string New status
---@return nil
function EntryService:onEntryStatusChanged(entry_id, new_status)
    -- Update local metadata
    pcall(function()
        self:_updateLocalEntryStatus(entry_id, new_status)
    end)

    -- If marked as read, schedule local deletion
    if new_status == "read" then
        UIManager:scheduleIn(0.5, function()
            pcall(function()
                self:deleteLocalEntry(entry_id)
            end)
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
                NavigationContext.setGlobalContext(entry_id)
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
                            pcall(function()
                                self:navigateToPreviousEntry(entry_info)
                            end)
                        end,
                    },
                    {
                        text = _("Next →"),
                        callback = function()
                            UIManager:close(dialog)
                            pcall(function()
                                self:navigateToNextEntry(entry_info)
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⚠ Delete local entry"),
                        callback = function()
                            UIManager:close(dialog)
                            pcall(function()
                                self:deleteLocalEntryFromInfo(entry_info)
                            end)
                        end,
                    },
                    {
                        text = mark_button_text,
                        callback = function()
                            UIManager:close(dialog)
                            pcall(function()
                                mark_callback()
                            end)
                        end,
                    },
                },
                {
                    {
                        text = _("⌂ Miniflux folder"),
                        callback = function()
                            UIManager:close(dialog)
                            pcall(function()
                                self:openMinifluxFolder()
                            end)
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
        UIManager:show(InfoMessage:new({
            text = _("Failed to create end of entry dialog"),
            timeout = 3,
        }))
        return nil
    end
end

-- =============================================================================
-- NAVIGATION FUNCTIONS (DELEGATES TO NAVIGATION SERVICE)
-- =============================================================================

---Navigate to the previous entry (delegates to NavigationService)
---@param entry_info table Current entry information
---@return nil
function EntryService:navigateToPreviousEntry(entry_info)
    -- Delegate to NavigationService for complex navigation logic
    self.navigation_service:navigateToPreviousEntry(entry_info, self)
end

---Navigate to the next entry (delegates to NavigationService)
---@param entry_info table Current entry information
---@return nil
function EntryService:navigateToNextEntry(entry_info)
    -- Delegate to NavigationService for complex navigation logic
    self.navigation_service:navigateToNextEntry(entry_info, self)
end

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
        UIManager:show(InfoMessage:new({
            text = _("Cannot delete: invalid entry ID"),
            timeout = 3,
        }))
        return
    end

    self:deleteLocalEntry(entry_id)
end

-- =============================================================================
-- LEGACY SUPPORT METHODS
-- =============================================================================

---Legacy method aliases for backward compatibility
---@param params {entry: MinifluxEntry, browser?: MinifluxBrowser}
function EntryService:showEntry(params)
    return self:readEntry(params.entry, params.browser)
end

---Legacy method aliases for backward compatibility
---@param params {entry: MinifluxEntry, browser?: MinifluxBrowser}
function EntryService:downloadEntry(params)
    return self:readEntry(params.entry, params.browser)
end

---Legacy method aliases for backward compatibility
---@param entry MinifluxEntry Entry to download and show
---@return nil
function EntryService:downloadAndShowEntry(entry)
    self:readEntry(entry)
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
    local metadata_content = "return " .. self:_tableToString(metadata)
    return self:_saveFile(metadata_file, metadata_content)
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
        UIManager:show(InfoMessage:new({
            text = _("Local entry deleted successfully"),
            timeout = 2,
        }))

        -- Open Miniflux folder
        pcall(function()
            self:openMinifluxFolder()
        end)

        return true
    else
        self:_showError(_("Failed to delete local entry"))
        return false
    end
end

---Update navigation context
---@param entry_id number Entry ID
---@return nil
function EntryService:_updateNavigationContext(entry_id)
    pcall(function()
        NavigationContext.updateCurrentEntry(entry_id)
    end)
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

---Save content to file
---@param file_path string File path
---@param content string Content to save
---@return boolean success
function EntryService:_saveFile(file_path, content)
    local file = io.open(file_path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
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

---Show error message
---@param message string Error message
---@return nil
function EntryService:_showError(message)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = 5,
    }))
end

---Convert table to Lua string representation
---@param tbl table Table to convert
---@param indent? number Current indentation level
---@return string Lua code representation of table
function EntryService:_tableToString(tbl, indent)
    indent = indent or 0
    local result = {}
    local spaces = string.rep("  ", indent)

    table.insert(result, "{\n")
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
        local value
        if type(v) == "string" then
            value = string.format('"%s"', v:gsub('"', '\\"'))
        elseif type(v) == "table" then
            value = self:_tableToString(v, indent + 1)
        else
            value = tostring(v)
        end
        table.insert(result, string.format("%s  [%s] = %s,\n", spaces, key, value))
    end
    table.insert(result, spaces .. "}")

    return table.concat(result)
end

return EntryService
