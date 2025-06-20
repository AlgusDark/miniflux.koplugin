--[[--
Entry Service

This service handles complex entry workflows and orchestration.
It coordinates between the Entry entity, repositories, and infrastructure services
to provide high-level entry operations.

@module koplugin.miniflux.entities.entry.entry_service
--]] --

local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local _ = require("gettext")
local T = require("ffi/util").template

-- Import dependencies
local Entry = require("entities/entry/entry")
local MinifluxAPI = require("api/api_client")
local NavigationContext = require("utils/navigation_context")
local ProgressUtils = require("utils/progress_utils")
local ImageUtils = require("utils/image_utils")
local HtmlUtils = require("utils/html_utils")

---@class EntryService
---@field settings MinifluxSettings Settings instance
---@field download_dir string Download directory path
local EntryService = {}

---Create a new EntryService instance
---@param settings MinifluxSettings Settings instance
---@return EntryService
function EntryService:new(settings)
    local instance = {
        settings = settings,
        download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
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
---@param browser? table Browser instance to close
---@return boolean success
function EntryService:readEntry(entry_data, browser)
    local entry = Entry:new(entry_data)

    -- Validate entry
    local valid, error_msg = entry:validateForDownload()
    if not valid then
        self:_showError(error_msg)
        return false
    end

    -- Update navigation context
    self:_updateNavigationContext(entry.id)

    -- Download entry if needed
    local success = self:_downloadEntryContent(entry, browser)
    if not success then
        self:_showError(_("Failed to download and show entry"))
        return false
    end

    return true
end

---Download entry content with progress tracking
---@param entry Entry Entry entity
---@param browser? table Browser instance to close
---@return boolean success
function EntryService:_downloadEntryContent(entry, browser)
    local progress = ProgressUtils.createEntryProgress(entry.title)

    -- Create entry directory
    local entry_dir = entry:getLocalDirectory(self.download_dir)
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end

    local html_file = entry:getLocalHtmlPath(self.download_dir)

    -- Check if already downloaded
    if entry:isDownloaded(self.download_dir) then
        progress:close()
        self:_closeBrowserAndOpenEntry(browser, html_file)
        return true
    end

    progress:update(_("Preparing download…"))

    -- Get entry content
    local content = entry.content or entry.summary or ""
    local include_images = self.settings.include_images

    progress:update(_("Scanning for images…"))

    -- Process images
    local base_url = entry.url and socket_url.parse(entry.url) or nil
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
    local html_content = HtmlUtils.createHtmlDocument(entry, processed_content)
    local file_success = self:_saveFile(html_file, html_content)
    if not file_success then
        progress:close()
        self:_showError(_("Failed to save HTML file"))
        return false
    end

    progress:update(_("Creating metadata…"))

    -- Save metadata
    local metadata = entry:createMetadata(include_images, #images)
    local metadata_file = entry:getLocalMetadataPath(self.download_dir)
    local metadata_content = "return " .. self:_tableToString(metadata)
    self:_saveFile(metadata_file, metadata_content)

    progress:close()

    -- Show completion summary
    local image_summary = ImageUtils.createDownloadSummary(include_images, images)
    UIManager:show(InfoMessage:new {
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
---@param progress table Progress tracker
---@return nil
function EntryService:_downloadImages(images, entry_dir, progress)
    local time = require("ui/time")
    local time_prev = time.now()

    for i, img in ipairs(images) do
        -- Update progress for each image
        progress:update(
            T(_("Downloading image %1 of %2…"), i, #images),
            { current = i - 1, total = #images },
            true
        )

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
    progress:update(
        _("Image downloads completed"),
        { current = progress.downloaded_images, total = #images }
    )
end

-- =============================================================================
-- ENTRY STATUS MANAGEMENT
-- =============================================================================

---Mark an entry as read
---@param entry_id number Entry ID
---@return boolean success
function EntryService:markAsRead(entry_id)
    return self:_changeEntryStatus(entry_id, "read")
end

---Mark an entry as unread
---@param entry_id number Entry ID
---@return boolean success
function EntryService:markAsUnread(entry_id)
    return self:_changeEntryStatus(entry_id, "unread")
end

---Delete a local entry (public interface)
---@param entry_id number Entry ID
---@return boolean success
function EntryService:deleteLocalEntry(entry_id)
    return self:_deleteLocalEntry(entry_id)
end

---Open the Miniflux folder in file manager (public interface)
---@return nil
function EntryService:openMinifluxFolder()
    self:_openMinifluxFolder()
end

---Change entry status with validation and side effects
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:_changeEntryStatus(entry_id, new_status)
    local entry = Entry:new({ id = entry_id })

    if not entry:hasValidId() then
        self:_showError(_("Cannot change status: invalid entry ID"))
        return false
    end

    -- Show loading message
    local action_text = new_status == "read" and _("Marking entry as read...") or _("Marking entry as unread...")
    local loading_info = InfoMessage:new { text = action_text }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    -- Create API client
    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
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
        self:_onEntryStatusChanged(entry_id, new_status)

        local success_text = new_status == "read" and _("Entry marked as read") or _("Entry marked as unread")
        UIManager:show(InfoMessage:new {
            text = success_text,
            timeout = 2,
        })
        return true
    else
        local error_text = new_status == "read" and
            _("Failed to mark entry as read: ") .. tostring(result) or
            _("Failed to mark entry as unread: ") .. tostring(result)
        self:_showError(error_text)
        return false
    end
end

---Handle side effects when entry status changes
---@param entry_id number Entry ID
---@param new_status string New status
---@return nil
function EntryService:_onEntryStatusChanged(entry_id, new_status)
    -- Update local metadata
    pcall(function()
        self:_updateLocalEntryStatus(entry_id, new_status)
    end)

    -- If marked as read, schedule local deletion
    if new_status == "read" then
        UIManager:scheduleIn(0.5, function()
            pcall(function()
                self:_deleteLocalEntry(entry_id)
            end)
        end)
    end
end

-- =============================================================================
-- FILE OPERATIONS
-- =============================================================================

---Update local entry metadata status
---@param entry_id number Entry ID
---@param new_status string New status
---@return boolean success
function EntryService:_updateLocalEntryStatus(entry_id, new_status)
    local entry = Entry:new({ id = entry_id })
    local metadata_file = entry:getLocalMetadataPath(self.download_dir)

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
function EntryService:_deleteLocalEntry(entry_id)
    local entry = Entry:new({ id = entry_id })
    local entry_dir = entry:getLocalDirectory(self.download_dir)

    local success = pcall(function()
        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end
        FFIUtil.purgeDir(entry_dir)
        return true
    end)

    if success then
        UIManager:show(InfoMessage:new {
            text = _("Local entry deleted successfully"),
            timeout = 2,
        })

        -- Open Miniflux folder
        pcall(function()
            self:_openMinifluxFolder()
        end)

        return true
    else
        self:_showError(_("Failed to delete local entry"))
        return false
    end
end

-- =============================================================================
-- HELPER METHODS
-- =============================================================================

---Update navigation context
---@param entry_id number Entry ID
---@return nil
function EntryService:_updateNavigationContext(entry_id)
    pcall(function()
        NavigationContext.updateCurrentEntry(entry_id)
    end)
end

---Close browser and open entry file
---@param browser? table Browser instance
---@param html_file string HTML file path
---@return nil
function EntryService:_closeBrowserAndOpenEntry(browser, html_file)
    if browser and browser.closeAll then
        browser:closeAll()
    end

    -- Open entry file
    pcall(function()
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
function EntryService:_openMinifluxFolder()
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end

    if FileManager.instance then
        FileManager.instance:reinit(self.download_dir)
    else
        FileManager:showFiles(self.download_dir)
    end
end

---Show error message
---@param message string Error message
---@return nil
function EntryService:_showError(message)
    UIManager:show(InfoMessage:new {
        text = message,
        timeout = 5,
    })
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
