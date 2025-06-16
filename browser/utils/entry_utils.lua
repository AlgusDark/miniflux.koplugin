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
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, browser?: BaseBrowser}
function EntryUtils.showEntry(params)
    local entry = params.entry
    local api = params.api
    local download_dir = params.download_dir
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
        browser = browser
    })
end

---Download and process an entry with images
---@param params {entry: MinifluxEntry, api: MinifluxAPI, download_dir: string, browser?: BaseBrowser, progress_callback?: function, include_images?: boolean}
function EntryUtils.downloadEntry(params)
    local entry = params.entry
    local api = params.api
    local download_dir = params.download_dir
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
        EntryUtils.openEntryFile(html_file)
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
        local time_prev = time.now()
        
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
    
    -- Create metadata
    local metadata = EntryUtils.createEntryMetadata({
        entry = entry,
        include_images = include_images,
        images = images
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
    
    -- Open the file after a brief delay
    UIManager:scheduleIn(0.3, function()
        -- Close the completion dialog immediately before opening the entry
        progress:closeCompletion()
        EntryUtils.openEntryFile(html_file)
    end)
end

---Create entry metadata
---@param params {entry: MinifluxEntry, include_images: boolean, images: ImageInfo[]}
---@return EntryMetadata
function EntryUtils.createEntryMetadata(params)
    local entry = params.entry
    local include_images = params.include_images
    local images = params.images
    
    -- Essential metadata for entry display and status tracking
    local metadata = {
        -- Entry identification
        id = entry.id,
        title = entry.title or _("Untitled Entry"),
        url = entry.url,
        
        -- Entry status and properties
        status = entry.status,
        starred = entry.starred,
        published_at = entry.published_at,
        
        -- Image processing results (minimal info)
        images_included = include_images,
        images_count = include_images and #images or 0
    }
    
    -- Note: Navigation context is now handled globally in memory,
    -- not stored in metadata files anymore
    
    return metadata
end

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@return nil
function EntryUtils.openEntryFile(html_file)
    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil
    
    if is_miniflux_entry then
        -- Extract entry ID from path for later use
        local entry_id = html_file:match("/miniflux/(%d+)/")
        
        if entry_id then
            -- Update global navigation context with this entry
            -- Note: We don't have browsing context when opening existing files,
            -- so navigation will be global unless the user came from a browser session
            local NavigationContext = require("browser/utils/navigation_context")
            if not NavigationContext.hasValidContext() then
                -- Set global context if no context exists
                NavigationContext.setGlobalContext(tonumber(entry_id))
            else
                -- Update current entry in existing context
                NavigationContext.updateCurrentEntry(tonumber(entry_id))
            end
        end
        
        -- Store the entry info for the EndOfBook event handler
        EntryUtils._current_miniflux_entry = {
            file_path = html_file,
            entry_id = entry_id
        }
    end
    
    -- Open the file - EndOfBook event handler will detect miniflux entries automatically
    ReaderUI:showReader(html_file)
end

---Show end of entry dialog with navigation options
---@return nil
function EntryUtils.showEndOfEntryDialog()
    local current_entry = EntryUtils._current_miniflux_entry
    if not current_entry then
        return
    end
    
    -- Load entry metadata to check current status
    local metadata = NavigationUtils.loadCurrentEntryMetadata(current_entry)
    local entry_status = metadata and metadata.status or "unread"
    
    -- Determine mark button text and action based on current status
    local mark_button_text, mark_callback
    if entry_status == "read" then
        mark_button_text = _("✓ Mark as unread")
        mark_callback = function()
            EntryUtils.markEntryAsUnread(current_entry)
        end
    else
        mark_button_text = _("✓ Mark as read")
        mark_callback = function()
            EntryUtils.markEntryAsRead(current_entry)
        end
    end
    
    -- Create dialog with proper variable scope
    local dialog
    dialog = ButtonDialogTitle:new{
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
EntryUtils.markEntryAsUnread = NavigationUtils.markEntryAsUnread
EntryUtils.deleteLocalEntry = NavigationUtils.deleteLocalEntry
EntryUtils.openMinifluxFolder = NavigationUtils.openMinifluxFolder
EntryUtils.fetchAndShowEntry = NavigationUtils.fetchAndShowEntry

return EntryUtils 