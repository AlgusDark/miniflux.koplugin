--[[--
Entry Utilities for Miniflux Browser

This utility module coordinates entry downloading, processing, and integration
with KOReader. It delegates specialized tasks to focused utility modules.

@module miniflux.browser.utils.entry_utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local socket_url = require("socket.url")
local _ = require("gettext")
local T = require("ffi/util").template

-- Move frequently used requires to module level for performance
local MinifluxSettingsManager = require("settings/settings_manager")
local time = require("ui/time")
local BrowserUtils = require("browser/utils/browser_utils")
local ReaderUI = require("apps/reader/readerui")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local NavigationUtils = require("browser/utils/navigation_utils")

-- Import the new specialized utility modules
local ProgressUtils = require("browser/utils/progress_utils")
local ImageUtils = require("browser/utils/image_utils")
local HtmlUtils = require("browser/utils/html_utils")

local EntryUtils = {}

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
    
    -- Create progress tracker using new ProgressUtils
    local progress = ProgressUtils.createEntryProgress(entry_title)
    
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
    
    progress:update(_("Scanning for images…"))
    
    -- Discover images using ImageUtils
    local base_url = entry.url and socket_url.parse(entry.url) or nil
    local images, seen_images = ImageUtils.discoverImages(content, base_url)
    
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
            
            local success = ImageUtils.downloadImage(img.src, entry_dir, img.filename)
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
    
    -- Process HTML content using ImageUtils
    local processed_content = ImageUtils.processHtmlImages(content, seen_images, include_images, base_url)
    
    -- Clean HTML content using HtmlUtils
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)
    
    progress:update(_("Creating HTML file…"))
    
    -- Create full HTML document using HtmlUtils
    local html_content = HtmlUtils.createHtmlDocument(entry, processed_content)
    
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
    
    -- Show completion summary using ImageUtils
    local image_summary = ImageUtils.createDownloadSummary(include_images, images)
    local complete_summary = _("Download completed!") .. "\n\n" .. image_summary .. "\n\n" .. _("Opening entry…")
    progress:showCompletion(complete_summary)
    
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
        progress:closeCompletion()
        EntryUtils.openEntryFile(html_file, navigation_context)
    end)
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