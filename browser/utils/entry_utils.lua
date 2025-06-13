--[[--
Entry Utilities for Miniflux Browser

This utility module handles entry downloading, processing, file operations,
and integration with KOReader for entry display and navigation.

@module miniflux.browser.utils.entry_utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local _ = require("gettext")
local T = require("ffi/util").template

-- Move frequently used requires to module level for performance
local MinifluxSettingsManager = require("settings/settings_manager")
local time = require("ui/time")
local BrowserUtils = require("browser/utils/browser_utils")
local ReaderUI = require("apps/reader/readerui")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local NavigationUtils = require("browser/utils/navigation_utils")

local EntryUtils = {}

---@class EntryDownloadProgress
---@field dialog InfoMessage Progress dialog instance
---@field title string Entry title being downloaded
---@field current_step string Current step description
---@field total_images number Total number of images found
---@field downloaded_images number Number of images successfully downloaded
---@field include_images boolean Whether images are being downloaded
local EntryDownloadProgress = {}

---Create a new progress tracker
---@param entry_title string Title of the entry being downloaded
---@return EntryDownloadProgress
function EntryDownloadProgress:new(entry_title)
    local obj = {
        title = entry_title,
        current_step = _("Preparing download…"),
        total_images = 0,
        downloaded_images = 0,
        include_images = true,
        dialog = nil
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Update the progress dialog with current status
---@param step string Current step description
---@param image_progress? {current: number, total: number} Optional image progress
---@param can_cancel? boolean Whether the operation can be cancelled
---@return boolean True if user wants to continue, false to cancel
function EntryDownloadProgress:update(step, image_progress, can_cancel)
    self.current_step = step
    
    if image_progress then
        self.downloaded_images = image_progress.current
        self.total_images = image_progress.total
    end
    
    -- Build progress message
    local message_parts = {
        T(_("Downloading: %1"), self.title),
        "",
        self.current_step
    }
    
    -- Add image progress if relevant
    if self.include_images and self.total_images > 0 then
        table.insert(message_parts, "")
        if image_progress then
            table.insert(message_parts, T(_("Images: %1 / %2 downloaded"), self.downloaded_images, self.total_images))
        else
            table.insert(message_parts, T(_("Images found: %1"), self.total_images))
        end
    elseif not self.include_images and self.total_images > 0 then
        table.insert(message_parts, "")
        table.insert(message_parts, T(_("Images: %1 found (skipped)"), self.total_images))
    end
    
    local message = table.concat(message_parts, "\n")
    
    -- Close previous dialog if exists
    if self.dialog then
        UIManager:close(self.dialog)
    end
    
    -- Create new progress dialog
    self.dialog = InfoMessage:new{
        text = message,
        timeout = can_cancel and 30 or nil, -- Allow longer timeout for cancellable operations
    }
    
    UIManager:show(self.dialog)
    UIManager:forceRePaint()
    
    -- For cancellable operations, check if user wants to continue
    if can_cancel then
        -- This is a simplified approach - in a real implementation, 
        -- we might want to add proper cancel button support
        return true
    end
    
    return true
end

---Set image configuration
---@param include_images boolean Whether images will be downloaded
---@param total_images number Total number of images found
---@return nil
function EntryDownloadProgress:setImageConfig(include_images, total_images)
    self.include_images = include_images
    self.total_images = total_images
end

---Increment downloaded images counter
---@return nil
function EntryDownloadProgress:incrementDownloadedImages()
    self.downloaded_images = self.downloaded_images + 1
end

---Close the progress dialog
---@return nil
function EntryDownloadProgress:close()
    if self.dialog then
        UIManager:close(self.dialog)
        self.dialog = nil
    end
end

---Show completion message
---@param summary string Completion summary message
---@return nil
function EntryDownloadProgress:showCompletion(summary)
    self:close()
    
    local completion_dialog = InfoMessage:new{
        text = summary,
        -- No timeout - we'll close it manually when opening the entry
    }
    
    UIManager:show(completion_dialog)
    UIManager:forceRePaint()
    
    -- Store reference to close it later
    self.completion_dialog = completion_dialog
end

---Show an entry by downloading and opening it
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, navigation_context?: NavigationContext, browser?: BaseBrowser}
function EntryUtils.showEntry(params)
    local entry = params.entry
    local api = params.api
    local download_dir = params.download_dir
    local navigation_context = params.navigation_context
    local browser = params.browser
    if not download_dir then
        UIManager:show(InfoMessage:new{
            text = _("Download directory not configured"),
            timeout = 3,
        })
        return
    end
    
    -- Direct download without Trapper wrapper since we have our own progress system
    EntryUtils.downloadEntry({
        entry = entry,
        api = api,
        download_dir = download_dir,
        navigation_context = navigation_context,
        browser = browser
    })
end

---Download and process an entry with images
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, navigation_context?: NavigationContext, browser?: BaseBrowser, progress_callback?: function, include_images?: boolean}
function EntryUtils.downloadEntry(params)
    local entry = params.entry
    local api = params.api
    local download_dir = params.download_dir
    local navigation_context = params.navigation_context
    local browser = params.browser
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local entry_title = entry.title or _("Untitled Entry")
    local entry_id = tostring(entry.id)
    
    -- Create progress tracker
    local progress = EntryDownloadProgress:new(entry_title)
    
    -- Create entry directory
    local entry_dir = download_dir .. entry_id .. "/"
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end
    
    local html_file = entry_dir .. "entry.html"
    local metadata_file = entry_dir .. "metadata.lua"
    
    -- Check if already downloaded
    if lfs.attributes(html_file, "mode") == "file" then
        progress:close()
        EntryUtils.openEntryFile(html_file, navigation_context)
        return
    end
    
    progress:update(_("Preparing download…"))
    
    -- Get entry content
    local content = entry.content or entry.summary or ""
    if content == "" then
        progress:close()
        UIManager:show(InfoMessage:new{
            text = _("No content available for this entry"),
            timeout = 3,
        })
        return
    end
    
    -- Check if images should be included
    local include_images = MinifluxSettings:getIncludeImages()
    
    -- Process images with improved logic from newsdownloader
    local images = {}
    local seen_images = {}
    local image_count = 0
    local base_url = entry.url and socket_url.parse(entry.url) or nil
    
    progress:update(_("Scanning for images…"))
    
    -- First pass: collect all images but don't modify HTML yet - with better progress
    local collectImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            return img_tag -- Keep original tag for now
        end
        
        -- Skip data URLs
        if src:sub(1,5) == "data:" then
            return img_tag -- Keep original tag for now
        end
        
        -- Handle different URL types
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Use HTTPS for protocol-relative URLs
        elseif src:sub(1,1) == "/" and base_url then -- absolute path, relative to domain
            src = socket_url.absolute(base_url, src)
        elseif not src:match("^https?://") and base_url then -- relative path
            src = socket_url.absolute(base_url, src)
        end
        
        if not seen_images[src] then
            image_count = image_count + 1
            
            -- Get file extension
            local src_ext = src
            if src_ext:find("?") then
                src_ext = src_ext:match("(.-)%?") -- remove query parameters
            end
            local ext = src_ext:match(".*%.(%S%S%S?%S?%S?)$") -- extensions are 2 to 5 chars
            if ext == nil then
                ext = "jpg" -- default extension
            end
            ext = ext:lower()
            
            -- Valid image extensions
            local valid_exts = {jpg=true, jpeg=true, png=true, gif=true, webp=true, svg=true}
            if not valid_exts[ext] then
                ext = "jpg"
            end
            
            local filename = string.format("image_%03d.%s", image_count, ext)
            local width = tonumber(img_tag:match([[width="([^"]*)"]]))
            local height = tonumber(img_tag:match([[height="([^"]*)"]]))
            
            local cur_image = {
                src = src,
                original_tag = img_tag,
                filename = filename,
                width = width,
                height = height,
                downloaded = false
            }
            
            table.insert(images, cur_image)
            seen_images[src] = cur_image
        end
        
        return img_tag -- Keep original tag for now
    end
    
    -- First pass: collect images without modifying HTML
    local scan_success = pcall(function()
        content:gsub("(<%s*img [^>]*>)", collectImg)
    end)
    
    if not scan_success then
        images = {} -- Clear images if scanning failed
    end
    
    -- Configure progress tracker with image information
    progress:setImageConfig(include_images, #images)
    
    -- Show what we found and what we'll do
    if include_images and #images > 0 then
        progress:update(T(_("Found %1 images - Starting download…"), #images))
    elseif include_images and #images == 0 then
        progress:update(_("No images found - Processing content…"))
    else
        progress:update(T(_("Found %1 images - Skipping (disabled in settings)"), #images))
    end
    
    -- Download images if enabled with proper progress reporting
    if include_images and #images > 0 then
        local before_images_time = time.now()
        local time_prev = before_images_time
        
        for i, img in ipairs(images) do
            -- Update progress for each image
            progress:update(
                T(_("Downloading image %1 of %2…"), i, #images),
                {current = i - 1, total = #images},
                true -- Allow cancellation during image downloads
            )
            
            -- Process can be interrupted every second between image downloads
            -- by tapping while the InfoMessage is displayed
            -- We use the fast_refresh option from image #2 for a quicker download
            local go_on = true
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()
                -- Update progress with cancellation option
                go_on = progress:update(
                    T(_("Downloading image %1 of %2…"), i, #images),
                    {current = i - 1, total = #images},
                    true
                )
                if not go_on then
                    break
                end
            end
            
            local success = EntryUtils.downloadImage(img.src, entry_dir, img.filename)
            img.downloaded = success
            
            if success then
                progress:incrementDownloadedImages()
            end
        end
        
        -- Final image download update
        progress:update(
            _("Image downloads completed"),
            {current = progress.downloaded_images, total = #images}
        )
    end
    
    progress:update(_("Processing content…"))
    
    -- Second pass: replace img tags based on download results
    local replaceImg = function(img_tag)
        -- Find which image this tag corresponds to
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            if include_images then
                return img_tag -- Keep original if we can't identify it
            else
                return "" -- Remove if include_images is false
            end
        end
        
        -- Skip data URLs
        if src:sub(1,5) == "data:" then
            if include_images then
                return img_tag -- Keep data URLs as-is
            else
                return "" -- Remove if include_images is false
            end
        end
        
        -- Normalize the URL to match what we stored
        if src:sub(1,2) == "//" then
            src = "https:" .. src
        elseif src:sub(1,1) == "/" and base_url then
            src = socket_url.absolute(base_url, src)
        elseif not src:match("^https?://") and base_url then
            src = socket_url.absolute(base_url, src)
        end
        
        local img_info = seen_images[src]
        if img_info then
            if include_images and img_info.downloaded then
                -- Image was successfully downloaded, use local path
                local style_props = {}
                if img_info.width then
                    table.insert(style_props, string.format("width: %spx", img_info.width))
                end
                if img_info.height then
                    table.insert(style_props, string.format("height: %spx", img_info.height))
                end
                local style = table.concat(style_props, "; ")
                if style ~= "" then
                    return string.format([[<img src="%s" style="%s" alt=""/>]], img_info.filename, style)
                else
                    return string.format([[<img src="%s" alt=""/>]], img_info.filename)
                end
            else
                -- Image download failed or include_images is false
                return ""
            end
        else
            -- Image not in our list (shouldn't happen, but handle gracefully)
            if include_images then
                return img_tag -- Keep original
            else
                return "" -- Remove
            end
        end
    end
    
    -- Final HTML processing: replace img tags appropriately
    local processed_content
    local process_success = pcall(function()
        processed_content = content:gsub("(<%s*img [^>]*>)", replaceImg)
    end)
    
    if not process_success then
        processed_content = content -- Use original content if processing failed
    else
        content = processed_content
    end
    
    -- Remove iframe tags since they won't work in offline HTML files
    pcall(function()
        -- Remove iframe tags (both self-closing and with content)
        content = content:gsub("<%s*iframe[^>]*>.-<%s*/%s*iframe%s*>", "")  -- iframe with content
        content = content:gsub("<%s*iframe[^>]*/%s*>", "")  -- self-closing iframe
        content = content:gsub("<%s*iframe[^>]*>", "")  -- opening iframe tag without closing
    end)
    
    progress:update(_("Creating HTML file…"))
    
    -- Create full HTML document
    local html_content = EntryUtils.createHtmlDocument(entry, content)
    
    -- Save HTML file
    local file = io.open(html_file, "w")
    if file then
        file:write(html_content)
        file:close()
    else
        progress:close()
        UIManager:show(InfoMessage:new{
            text = _("Failed to save HTML file"),
            timeout = 3,
        })
        return
    end
    
    progress:update(_("Creating metadata…"))
    
    -- Create metadata with navigation context
    local metadata = EntryUtils.createEntryMetadata({
        entry = entry,
        include_images = include_images,
        images = images,
        navigation_context = navigation_context
    })
    
    -- Save metadata file
    local metadata_content = "return " .. BrowserUtils.tableToString(metadata)
    file = io.open(metadata_file, "w")
    if file then
        file:write(metadata_content)
        file:close()
    end
    
    -- Show completion summary
    local summary_message = EntryUtils.createDownloadSummary(include_images, images)
    progress:showCompletion(summary_message)
    
    -- Close browser if provided before opening the entry
    if browser and browser.closeAll then
        -- Schedule browser close after UI operations complete
        UIManager:scheduleIn(0.1, function()
            browser:closeAll()
        end)
    end
    
    -- Open the file with navigation context after a brief delay
    UIManager:scheduleIn(0.3, function()
        -- Close the completion dialog immediately before opening the entry
        if progress.completion_dialog then
            UIManager:close(progress.completion_dialog)
            progress.completion_dialog = nil
        end
        
        EntryUtils.openEntryFile(html_file, navigation_context)
    end)
end

---Download a single image from URL
---@param url string Image URL to download
---@param entry_dir string Directory to save image in
---@param filename string Filename to save image as
---@return boolean True if download successful
function EntryUtils.downloadImage(url, entry_dir, filename)
    local filepath = entry_dir .. filename
    local response_body = {}
    
    -- Add robust timeout handling using socketutil (from newsdownloader)
    local timeout, maxtime = 10, 30
    socketutil:set_timeout(timeout, maxtime)
    
    local result, status_code
    local network_success = pcall(function()
        result, status_code = http.request{
            url = url,
            sink = ltn12.sink.table(response_body),
        }
    end)
    
    socketutil:reset_timeout()
    
    if not network_success then
        return false
    end
    
    if not result then
        return false
    end
    
    if status_code == 200 then
        local content = table.concat(response_body)
        if content and #content > 0 then
            local file = io.open(filepath, "wb")
            if file then
                file:write(content)
                file:close()
                return true
            else
                return false
            end
        else
            return false
        end
    else
        return false
    end
end

---Create HTML document for entry
---@param entry MinifluxEntry Entry data
---@param content string Processed content
---@return string Complete HTML document
function EntryUtils.createHtmlDocument(entry, content)
    local entry_title = entry.title or _("Untitled Entry")
    
    return string.format([[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        body { 
            font-family: serif; 
            line-height: 1.6; 
            max-width: 800px; 
            margin: 0 auto; 
        }
        img { 
            max-width: 100%%; 
            height: auto; 
        }
        .entry-meta {
            border-bottom: 1px solid #ccc;
            padding-bottom: 10px;
            margin-bottom: 20px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>
        %s
        %s
        %s
    </div>
    <div class="entry-content">
        %s
    </div>
</body>
</html>]], 
        entry_title,
        entry_title,
        entry.feed and entry.feed.title and ("<p><strong>Feed:</strong> " .. entry.feed.title .. "</p>") or "",
        entry.published_at and ("<p><strong>Published:</strong> " .. entry.published_at .. "</p>") or "",
        entry.url and ("<p><strong>URL:</strong> <a href=\"" .. entry.url .. "\">" .. entry.url .. "</a></p>") or "",
        content
    )
end

---Create entry metadata
---@param params {entry: MinifluxEntry, include_images: boolean, images: ImageInfo[], navigation_context?: NavigationContext}
---@return EntryMetadata
function EntryUtils.createEntryMetadata(params)
    local entry = params.entry
    local include_images = params.include_images
    local images = params.images
    local navigation_context = params.navigation_context
    local images_downloaded = 0
    if include_images then
        for _, img in ipairs(images) do
            if img.downloaded then
                images_downloaded = images_downloaded + 1
            end
        end
    end
    
    -- Calculate previous/next entry IDs from navigation context
    local previous_entry_id = nil
    local next_entry_id = nil
    if navigation_context and navigation_context.entries and navigation_context.current_index then
        local entries = navigation_context.entries
        local current_index = navigation_context.current_index
        
        -- Get previous entry (index - 1)
        if current_index > 1 then
            local prev_entry = entries[current_index - 1]
            if prev_entry and prev_entry.id then
                previous_entry_id = prev_entry.id
            end
        end
        
        -- Get next entry (index + 1)
        if current_index < #entries then
            local next_entry = entries[current_index + 1]
            if next_entry and next_entry.id then
                next_entry_id = next_entry.id
            end
        end
    end
    
    return {
        title = entry.title or _("Untitled Entry"),
        id = entry.id,
        url = entry.url,
        published_at = entry.published_at,
        feed_title = entry.feed and entry.feed.title,
        status = entry.status,
        starred = entry.starred,
        download_time = os.time(),
        include_images = include_images,
        images_found = #images,
        images_downloaded = images_downloaded,
        previous_entry_id = previous_entry_id,
        next_entry_id = next_entry_id,
        -- Store the original navigation context for context-aware navigation
        navigation_context = navigation_context,
    }
end

---Create download summary message
---@param include_images boolean Whether images were included
---@param images ImageInfo[] Image information
---@return string Summary message
function EntryUtils.createDownloadSummary(include_images, images)
    local images_downloaded = 0
    if include_images then
        for _, img in ipairs(images) do
            if img.downloaded then
                images_downloaded = images_downloaded + 1
            end
        end
    end
    
    local summary_parts = {
        _("Download completed!")
    }
    
    if include_images and #images > 0 then
        if images_downloaded == #images then
            table.insert(summary_parts, T(_("All %1 images downloaded successfully"), #images))
        else
            table.insert(summary_parts, T(_("%1 of %2 images downloaded"), images_downloaded, #images))
        end
    elseif include_images and #images == 0 then
        table.insert(summary_parts, _("No images found in entry"))
    else
        table.insert(summary_parts, T(_("%1 images found (skipped - disabled in settings)"), #images))
    end
    
    table.insert(summary_parts, _("Opening entry…"))
    
    return table.concat(summary_parts, "\n\n")
end

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@param navigation_context? NavigationContext Navigation context for prev/next
---@return nil
function EntryUtils.openEntryFile(html_file, navigation_context)
    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil
    
    if is_miniflux_entry then
        -- Extract entry ID from path for later use
        local entry_id = html_file:match("/miniflux/(%d+)/")
        
        -- Use KOReader's document opening mechanism
        
        -- Store the entry info for the event listener with navigation context
        EntryUtils._current_miniflux_entry = {
            file_path = html_file,
            entry_id = entry_id,
            navigation_context = navigation_context, -- Always use the passed context
        }
        
        -- If no navigation context was passed, try to load it from metadata
        if not navigation_context then
            local loaded_context = NavigationUtils.getCurrentNavigationContext(EntryUtils._current_miniflux_entry)
            if loaded_context then
                EntryUtils._current_miniflux_entry.navigation_context = loaded_context
            end
        end
        
        -- Open the file
        ReaderUI:showReader(html_file)
        
        -- Add event listener after a short delay to ensure ReaderUI is ready
        UIManager:scheduleIn(0.5, function()
            EntryUtils.addMinifluxEventListeners()
        end)
    else
        -- Regular file opening for non-Miniflux entries
        ReaderUI:showReader(html_file)
    end
end

---Add event listeners for Miniflux entry navigation
---@return nil
function EntryUtils.addMinifluxEventListeners()
    -- Get the current ReaderUI instance
    local reader_instance = ReaderUI.instance
    
    if not reader_instance then
        return
    end
    
    -- Add event listener for page turn events
    if not reader_instance._miniflux_listener_added then
        reader_instance._miniflux_listener_added = true
        
        -- Store original onPageUpdate function if it exists
        local original_onPageUpdate = reader_instance.onPageUpdate
        
        -- Override onPageUpdate to detect end of document
        reader_instance.onPageUpdate = function(self, new_page_no)
            -- Call original function first
            if original_onPageUpdate then
                original_onPageUpdate(self, new_page_no)
            end
            
            -- Check if we're at the end and user tried to go forward
            if self.document and self.document.info and new_page_no then
                local total_pages = self.document.info.number_of_pages or 0
                
                -- If we're on the last page and user tries to go forward
                if new_page_no >= total_pages then
                    -- Check if this was triggered by a forward navigation attempt
                    -- We'll show the dialog after a brief delay to ensure UI is stable
                    UIManager:scheduleIn(0.1, function()
                        EntryUtils.showEndOfEntryDialog()
                    end)
                end
            end
        end
    end
end

---Show end of entry dialog with navigation options
---@return nil
function EntryUtils.showEndOfEntryDialog()
    local current_entry = EntryUtils._current_miniflux_entry
    if not current_entry then
        return
    end
    
    local dialog = ButtonDialogTitle:new{
        title = _("You've reached the end of the entry."),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("← Previous"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryUtils.navigateToPreviousEntry(current_entry)
                    end,
                },
                {
                    text = _("Next →"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryUtils.navigateToNextEntry(current_entry)
                    end,
                },
            },
            {
                {
                    text = _("⚠ Delete local entry"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryUtils.deleteLocalEntry(current_entry)
                    end,
                },
                {
                    text = _("✓ Mark as read"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryUtils.markEntryAsRead(current_entry)
                    end,
                },
            },
            {
                {
                    text = _("⌂ Miniflux folder"),
                    callback = function()
                        UIManager:close(dialog)
                        EntryUtils.openMinifluxFolder(current_entry)
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
    }
    
    UIManager:show(dialog)
end

-- Delegate navigation functions to NavigationUtils
EntryUtils.navigateToPreviousEntry = NavigationUtils.navigateToPreviousEntry
EntryUtils.navigateToNextEntry = NavigationUtils.navigateToNextEntry
EntryUtils.markEntryAsRead = NavigationUtils.markEntryAsRead
EntryUtils.deleteLocalEntry = NavigationUtils.deleteLocalEntry
EntryUtils.openMinifluxFolder = NavigationUtils.openMinifluxFolder
EntryUtils.fetchAndShowEntry = NavigationUtils.fetchAndShowEntry

return EntryUtils 