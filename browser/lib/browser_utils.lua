--[[--
Browser utilities for Miniflux browsers

@module koplugin.miniflux.browser.browser_utils
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

---@class ImageInfo
---@field src string Original image URL
---@field original_tag string Original HTML img tag
---@field filename string Local filename for downloaded image
---@field width? number Image width
---@field height? number Image height
---@field downloaded boolean Whether image was successfully downloaded



---@class EntryMetadata
---@field title string Entry title
---@field id number Entry ID
---@field url? string Entry URL
---@field published_at? string Publication timestamp
---@field feed_title? string Feed title
---@field status EntryStatus Entry read status
---@field starred boolean Whether entry is bookmarked
---@field download_time number Timestamp when downloaded
---@field include_images boolean Whether images were included
---@field images_found number Number of images found
---@field images_downloaded number Number of images successfully downloaded
---@field previous_entry_id? number ID of previous entry for navigation
---@field next_entry_id? number ID of next entry for navigation

local BrowserUtils = {}

---Show an entry by downloading and opening it
---@param entry MinifluxEntry Entry to display
---@param api MinifluxAPI API client instance
---@param download_dir string Download directory path
---@param navigation_context? NavigationContext Navigation context for prev/next
---@return nil
function BrowserUtils.showEntry(entry, api, download_dir, navigation_context)
    if not download_dir then
        UIManager:show(InfoMessage:new{
            text = _("Download directory not configured"),
            timeout = 3,
        })
        return
    end
    
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        BrowserUtils.downloadEntry(entry, api, download_dir, navigation_context)
    end)
end

---Download and process an entry with images
---@param entry MinifluxEntry Entry to download
---@param api MinifluxAPI API client instance
---@param download_dir string Download directory path
---@param navigation_context? NavigationContext Navigation context for prev/next
---@return nil
function BrowserUtils.downloadEntry(entry, api, download_dir, navigation_context)
    local UI = require("ui/trapper")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    local time = require("ui/time")
    
    local entry_title = entry.title or _("Untitled Entry")
    local entry_id = tostring(entry.id)
    
    -- Create entry directory
    local entry_dir = download_dir .. entry_id .. "/"
    if not lfs.attributes(entry_dir, "mode") then
        lfs.mkdir(entry_dir)
    end
    
    local html_file = entry_dir .. "entry.html"
    local metadata_file = entry_dir .. "metadata.lua"
    
    -- Check if already downloaded
    if lfs.attributes(html_file, "mode") == "file" then
        BrowserUtils.openEntryFile(html_file)
        return
    end
    
    UI:info(_("Downloading entry…\n\nPreparing download…"))
    
    -- Get entry content
    local content = entry.content or entry.summary or ""
    if content == "" then
        UI:info(_("No content available for this entry"))
        return
    end
    
    -- Check if images should be included
    local include_images = MinifluxSettings:getIncludeImages()
    
    -- Process images with improved logic from newsdownloader
    local images = {}
    local seen_images = {}
    local image_count = 0
    local base_url = entry.url and socket_url.parse(entry.url) or nil
    
    UI:info(_("Downloading entry…\n\nScanning for images…"))
    
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
    
    -- Show what we found and what we'll do
    if include_images and #images > 0 then
        UI:info(T(_("Downloading entry…\n\nFound %1 images\nDownloading images…"), #images))
    elseif include_images and #images == 0 then
        UI:info(_("Downloading entry…\n\nNo images found\nProcessing content…"))
    else
        UI:info(T(_("Downloading entry…\n\nFound %1 images\nSkipping images (disabled in settings)"), #images))
    end
    
    -- Download images if enabled with proper progress reporting like newsdownloader
    if include_images and #images > 0 then
        local before_images_time = time.now()
        local time_prev = before_images_time
        
        for i, img in ipairs(images) do
            -- Process can be interrupted every second between image downloads
            -- by tapping while the InfoMessage is displayed
            -- We use the fast_refresh option from image #2 for a quicker download
            local go_on
            if time.to_ms(time.since(time_prev)) > 1000 then
                time_prev = time.now()
                go_on = UI:info(T(_("Downloading entry…\n\nDownloading image %1 / %2…"), i, #images), i >= 2)
                if not go_on then
                    break
                end
            else
                UI:info(T(_("Downloading entry…\n\nDownloading image %1 / %2…"), i, #images), i >= 2, true)
            end
            
            local success = BrowserUtils.downloadImage(img.src, entry_dir, img.filename)
            img.downloaded = success
        end
    end
    
    UI:info(_("Downloading entry…\n\nProcessing final content…"))
    
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
    
    UI:info(_("Downloading entry…\n\nCreating HTML file…"))
    
    -- Create full HTML document
    local html_content = string.format([[<!DOCTYPE html>
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
    
    -- Save HTML file
    local file = io.open(html_file, "w")
    if file then
        file:write(html_content)
        file:close()
    else
        UI:info(_("Failed to save HTML file"))
        return
    end
    
    UI:info(_("Downloading entry…\n\nCreating metadata…"))
    
    -- Create metadata
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
    
    local metadata = {
        title = entry_title,
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
    }
    
    -- Save metadata file
    local metadata_content = "return " .. BrowserUtils.tableToString(metadata)
    file = io.open(metadata_file, "w")
    if file then
        file:write(metadata_content)
        file:close()
    end
    
    -- Final status message with summary
    local summary_message
    if include_images and #images > 0 then
        summary_message = T(_("Download complete!\n\nImages: %1 downloaded, %2 total\nOpening entry…"), images_downloaded, #images)
    elseif include_images and #images == 0 then
        summary_message = _("Download complete!\n\nNo images found\nOpening entry…")
    else
        summary_message = T(_("Download complete!\n\nImages skipped (%1 found)\nOpening entry…"), #images)
    end
    
    UI:info(summary_message)
    
    -- Open the file
    BrowserUtils.openEntryFile(html_file)
    
    -- Clear the "Download complete" message since the entry is now open
    UI:clear()
end

---Download a single image from URL
---@param url string Image URL to download
---@param entry_dir string Directory to save image in
---@param filename string Filename to save image as
---@return boolean True if download successful
function BrowserUtils.downloadImage(url, entry_dir, filename)
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

---Open an entry HTML file in KOReader
---@param html_file string Path to HTML file to open
---@return nil
function BrowserUtils.openEntryFile(html_file)
    -- Check if this is a miniflux entry by looking at the path
    local is_miniflux_entry = html_file:match("/miniflux/") ~= nil
    
    if is_miniflux_entry then
        -- Extract entry ID from path for later use
        local entry_id = html_file:match("/miniflux/(%d+)/")
        
        -- Use KOReader's document opening mechanism
        local ReaderUI = require("apps/reader/readerui")
        
        -- Store the entry info for the event listener
        BrowserUtils._current_miniflux_entry = {
            file_path = html_file,
            entry_id = entry_id,
        }
        
        -- Open the file
        ReaderUI:showReader(html_file)
        
        -- Add event listener after a short delay to ensure ReaderUI is ready
        UIManager:scheduleIn(0.5, function()
            BrowserUtils.addMinifluxEventListeners()
        end)
    else
        -- Regular file opening for non-Miniflux entries
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(html_file)
    end
end

function BrowserUtils.addMinifluxEventListeners()
    -- Get the current ReaderUI instance
    local ReaderUI = require("apps/reader/readerui")
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
                        BrowserUtils.showEndOfEntryDialog()
                    end)
                end
            end
        end
    end
end

function BrowserUtils.showEndOfEntryDialog()
    local current_entry = BrowserUtils._current_miniflux_entry
    if not current_entry then
        return
    end
    
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    local _ = require("gettext")
    
    local dialog = ButtonDialogTitle:new{
        title = _("You've reached the end of the entry."),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("← Previous"),
                    callback = function()
                        UIManager:close(dialog)
                        BrowserUtils.navigateToPreviousEntry(current_entry)
                    end,
                },
                {
                    text = _("Next →"),
                    callback = function()
                        UIManager:close(dialog)
                        BrowserUtils.navigateToNextEntry(current_entry)
                    end,
                },
            },
            {
                {
                    text = _("⚠ Delete local entry"),
                    callback = function()
                        UIManager:close(dialog)
                        BrowserUtils.deleteLocalEntry(current_entry)
                    end,
                },
                {
                    text = _("✓ Mark as read"),
                    callback = function()
                        UIManager:close(dialog)
                        BrowserUtils.markEntryAsRead(current_entry)
                    end,
                },
            },
            {
                {
                    text = _("⌂ Miniflux folder"),
                    callback = function()
                        UIManager:close(dialog)
                        BrowserUtils.openMinifluxFolder(current_entry)
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

function BrowserUtils.deleteLocalEntry(entry_info)
    local entry_id = entry_info.entry_id
    
    if not entry_id then
        return
    end
    
    -- Extract miniflux directory from file path
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return
    end
    
    local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
    
    -- Close the current document first
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end
    
    -- Delete the directory
    local FFIUtil = require("ffi/util")
    
    local success = pcall(function()
        FFIUtil.purgeDir(entry_dir)
    end)
    
    if success then
        UIManager:show(InfoMessage:new{
            text = _("Local entry deleted successfully"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to delete local entry"),
            timeout = 3,
        })
    end
    
    -- Go to miniflux folder
    BrowserUtils.openMinifluxFolder(entry_info)
end

function BrowserUtils.markEntryAsRead(entry_info)
    local entry_id = entry_info.entry_id
    
    if not entry_id then
        return
    end
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Marking entry as read..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get API instance (we'll need to figure out how to access this)
    -- For now, we'll create a new instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Mark as read
    local success, result = api:markEntryAsRead(tonumber(entry_id))
    
    UIManager:close(loading_info)
    
    if success then
        UIManager:show(InfoMessage:new{
            text = _("Entry marked as read"),
            timeout = 2,
        })
        
        -- Delete local entry and go to miniflux folder
        UIManager:scheduleIn(0.5, function()
            BrowserUtils.deleteLocalEntry(entry_info)
        end)
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to mark entry as read: ") .. tostring(result),
            timeout = 5,
        })
    end
end

function BrowserUtils.openMinifluxFolder(entry_info)
    -- Extract miniflux directory from file path
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return
    end
    
    local full_miniflux_dir = miniflux_dir .. "/miniflux/"
    
    -- Close the current document first
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end
    
    -- Open file manager to miniflux folder
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:reinit(full_miniflux_dir)
    else
        FileManager:showFiles(full_miniflux_dir)
    end
end

---Convert table to string representation for serialization
---@param tbl table Table to convert
---@param indent? number Current indentation level
---@return string String representation of table
function BrowserUtils.tableToString(tbl, indent)
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
            value = BrowserUtils.tableToString(v, indent + 1)
        else
            value = tostring(v)
        end
        table.insert(result, string.format("%s  [%s] = %s,\n", spaces, key, value))
    end
    table.insert(result, spaces .. "}")
    
    return table.concat(result)
end

---Sort menu items by unread count
---@param items table[] Array of menu items to sort
---@param data_field string Field name containing the data object
---@param title_field string Field name containing the title (unused but kept for compatibility)
---@return nil
function BrowserUtils.sortItemsByUnreadCount(items, data_field, title_field)
    table.sort(items, function(a, b)
        local a_data = a[data_field] or {}
        local b_data = b[data_field] or {}
        local a_unread = a_data.unread_count or 0
        local b_unread = b_data.unread_count or 0
        local a_title = a_data.title or ""
        local b_title = b_data.title or ""
        
        -- First priority: items with unread entries come before items without
        if a_unread > 0 and b_unread == 0 then
            return true
        elseif a_unread == 0 and b_unread > 0 then
            return false
        elseif a_unread > 0 and b_unread > 0 then
            -- Both have unread entries: sort by unread count descending
            if a_unread ~= b_unread then
                return a_unread > b_unread
            else
                -- Same unread count: sort alphabetically
                return a_title:lower() < b_title:lower()
            end
        else
            -- Both have no unread entries: sort alphabetically
            return a_title:lower() < b_title:lower()
        end
    end)
end

---Get API options based on current settings
---@param settings SettingsManager Settings manager instance
---@return ApiOptions Options for API calls
function BrowserUtils.getApiOptions(settings)
    local options = {
        limit = settings:getLimit(),
        order = settings:getOrder(),
        direction = settings:getDirection(),
    }
    
    -- Use server-side filtering based on settings
    local hide_read_entries = settings:getHideReadEntries()
    if hide_read_entries then
        -- Only fetch unread entries
        options.status = {"unread"}
    else
        -- Fetch both read and unread entries, but never "removed" ones
        options.status = {"unread", "read"}
    end
    
    return options
end

function BrowserUtils.navigateToPreviousEntry(entry_info)
    -- Get current entry ID
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        return
    end
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    local _ = require("gettext")
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Finding previous entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get filter options based on current settings
    local options = BrowserUtils.getApiOptions(MinifluxSettings)
    options.limit = 1  -- We only want the immediate previous entry
    
    -- Fetch previous entry using before_entry_id
    local success, result = api:getPreviousEntry(current_entry_id, options)
    
    UIManager:close(loading_info)
    
    if success and result and result.entries and #result.entries > 0 then
        local prev_entry = result.entries[1]
        local prev_entry_id = tostring(prev_entry.id)
        
        -- Check if previous entry is already downloaded locally
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local prev_entry_dir = miniflux_dir .. "/miniflux/" .. prev_entry_id .. "/"
            local prev_html_file = prev_entry_dir .. "entry.html"
            
            if lfs.attributes(prev_html_file, "mode") == "file" then
                BrowserUtils.openEntryFile(prev_html_file)
                return
            end
        end
        
        -- Entry not downloaded locally, download and show it
        -- Create download directory
        local DataStorage = require("datastorage")
        local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
        
        -- Download and show the entry
        BrowserUtils.downloadEntry(prev_entry, api, download_dir, nil)
    else
        UIManager:show(InfoMessage:new{
            text = _("No previous entry available"),
            timeout = 3,
        })
    end
end

function BrowserUtils.navigateToNextEntry(entry_info)
    -- Get current entry ID
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        return
    end
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    local _ = require("gettext")
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Finding next entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get filter options based on current settings
    local options = BrowserUtils.getApiOptions(MinifluxSettings)
    options.limit = 1  -- We only want the immediate next entry
    
    -- Fetch next entry using after_entry_id
    local success, result = api:getNextEntry(current_entry_id, options)
    
    UIManager:close(loading_info)
    
    if success and result and result.entries and #result.entries > 0 then
        local next_entry = result.entries[1]
        local next_entry_id = tostring(next_entry.id)
        
        -- Check if next entry is already downloaded locally
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local next_entry_dir = miniflux_dir .. "/miniflux/" .. next_entry_id .. "/"
            local next_html_file = next_entry_dir .. "entry.html"
            
            if lfs.attributes(next_html_file, "mode") == "file" then
                BrowserUtils.openEntryFile(next_html_file)
                return
            end
        end
        
        -- Entry not downloaded locally, download and show it
        -- Create download directory
        local DataStorage = require("datastorage")
        local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
        
        -- Download and show the entry
        BrowserUtils.downloadEntry(next_entry, api, download_dir, nil)
    else
        UIManager:show(InfoMessage:new{
            text = _("No next entry available"),
            timeout = 3,
        })
    end
end

function BrowserUtils.fetchAndShowEntry(entry_id)
    local _ = require("gettext")
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Fetching entry from server..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Fetch the entry by ID
    local success, result = api:getEntry(entry_id)
    
    UIManager:close(loading_info)
    
    if success and result then
        -- Create download directory
        local DataStorage = require("datastorage")
        local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
        
        -- Download and show the entry without navigation context (will be handled by dynamic API calls)
        BrowserUtils.downloadEntry(result, api, download_dir, nil)
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to fetch entry: ") .. tostring(result),
            timeout = 5,
        })
    end
end

return BrowserUtils 