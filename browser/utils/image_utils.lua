--[[--
Image Utilities for Miniflux Browser

This utility module handles image discovery, downloading, and HTML processing
for offline viewing of RSS entries with embedded images.

@module miniflux.browser.utils.image_utils
--]]--

local http = require("socket.http")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local _ = require("gettext")

local ImageUtils = {}

---@class ImageInfo
---@field src string Original image URL
---@field original_tag string Original HTML img tag
---@field filename string Local filename for downloaded image
---@field width? number Image width
---@field height? number Image height
---@field downloaded boolean Whether image was successfully downloaded

---Discover images in HTML content
---@param content string HTML content to scan
---@param base_url? table Parsed base URL for resolving relative URLs
---@return ImageInfo[] Array of discovered images
---@return table<string, ImageInfo> Map of URLs to image info for deduplication
function ImageUtils.discoverImages(content, base_url)
    local images = {}
    local seen_images = {}
    local image_count = 0
    
    -- Collect all images from HTML content
    local collectImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            return img_tag -- Keep original tag
        end
        
        -- Skip data URLs
        if src and src:sub(1,5) == "data:" then
            return img_tag -- Keep original tag
        end
        
        -- Normalize URL
        local normalized_src = ImageUtils.normalizeImageUrl(src or "", base_url)
        
        if not seen_images[normalized_src] then
            image_count = image_count + 1
            
            -- Get file extension
            local ext = ImageUtils.getImageExtension(normalized_src)
            local filename = string.format("image_%03d.%s", image_count, ext)
            
            -- Extract dimensions if available
            local width = tonumber(img_tag:match([[width="([^"]*)"]]))
            local height = tonumber(img_tag:match([[height="([^"]*)"]]))
            
            local image_info = {
                src = normalized_src,
                original_tag = img_tag,
                filename = filename,
                width = width,
                height = height,
                downloaded = false
            }
            
            table.insert(images, image_info)
            seen_images[normalized_src] = image_info
        end
        
        return img_tag -- Keep original tag for now
    end
    
    -- Scan content for images
    local scan_success = pcall(function()
        content:gsub("(<%s*img [^>]*>)", collectImg)
    end)
    
    if not scan_success then
        return {}, {} -- Return empty tables if scanning failed
    end
    
    return images, seen_images
end

---Normalize image URL for downloading
---@param src string Original image URL
---@param base_url? table Parsed base URL
---@return string Normalized absolute URL
function ImageUtils.normalizeImageUrl(src, base_url)
    -- Handle different URL types
    if src:sub(1,2) == "//" then
        return "https:" .. src -- Use HTTPS for protocol-relative URLs
    elseif src:sub(1,1) == "/" and base_url then
        -- Absolute path, relative to domain
        return socket_url.absolute(base_url, src)
    elseif not src:match("^https?://") and base_url then
        -- Relative path
        return socket_url.absolute(base_url, src)
    else
        -- Already absolute URL
        return src
    end
end

---Get appropriate file extension for image URL
---@param url string Image URL
---@return string File extension (without dot)
function ImageUtils.getImageExtension(url)
    -- Remove query parameters
    local clean_url = url
    if clean_url:find("?") then
        clean_url = clean_url:match("(.-)%?")
    end
    
    -- Extract extension (2 to 5 characters)
    local ext = clean_url:match(".*%.(%S%S%S?%S?%S?)$")
    if ext == nil then
        ext = "jpg" -- default extension
    end
    ext = ext:lower()
    
    -- Valid image extensions
    local valid_exts = {jpg=true, jpeg=true, png=true, gif=true, webp=true, svg=true}
    if not valid_exts[ext] then
        ext = "jpg" -- fallback to jpg
    end
    
    return ext
end

---Download a single image from URL
---@param url string Image URL to download
---@param entry_dir string Directory to save image in
---@param filename string Filename to save image as
---@return boolean True if download successful
function ImageUtils.downloadImage(url, entry_dir, filename)
    local filepath = entry_dir .. filename
    local response_body = {}
    
    -- Add robust timeout handling using socketutil
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

---Download multiple images with progress tracking
---@param images ImageInfo[] Array of images to download
---@param entry_dir string Directory to save images in
---@param progress_callback? function Optional progress callback function(current, total, success)
---@return number Number of successfully downloaded images
function ImageUtils.downloadImages(images, entry_dir, progress_callback)
    local downloaded_count = 0
    
    for i, img in ipairs(images) do
        -- Call progress callback if provided
        if progress_callback then
            progress_callback(i - 1, #images, nil) -- Before download
        end
        
        local success = ImageUtils.downloadImage(img.src, entry_dir, img.filename)
        img.downloaded = success
        
        if success then
            downloaded_count = downloaded_count + 1
        end
        
        -- Call progress callback after download
        if progress_callback then
            progress_callback(i, #images, success)
        end
    end
    
    return downloaded_count
end

---Process HTML content to replace image tags based on download results
---@param content string Original HTML content
---@param seen_images table<string, ImageInfo> Map of URLs to image info
---@param include_images boolean Whether to include images in output
---@param base_url? table Parsed base URL for normalizing URLs
---@return string Processed HTML content
function ImageUtils.processHtmlImages(content, seen_images, include_images, base_url)
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
        if src and src:sub(1,5) == "data:" then
            if include_images then
                return img_tag -- Keep data URLs as-is
            else
                return "" -- Remove if include_images is false
            end
        end
        
        -- Normalize the URL to match what we stored
        local normalized_src = ImageUtils.normalizeImageUrl(src or "", base_url)
        
        local img_info = seen_images[normalized_src]
        if img_info then
            if include_images and img_info.downloaded then
                -- Image was successfully downloaded, use local path
                return ImageUtils.createLocalImageTag(img_info)
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
    
    -- Replace img tags in HTML content
    local processed_content
    local process_success = pcall(function()
        processed_content = content:gsub("(<%s*img [^>]*>)", replaceImg)
    end)
    
    if not process_success then
        return content -- Use original content if processing failed
    end
    
    return processed_content
end

---Create a local image tag with proper styling
---@param img_info ImageInfo Image information
---@return string HTML img tag for local image
function ImageUtils.createLocalImageTag(img_info)
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
end

---Clean HTML content by removing problematic elements
---@param content string HTML content to clean
---@return string Cleaned HTML content
function ImageUtils.cleanHtmlContent(content)
    local cleaned_content = content
    
    -- Remove iframe tags since they won't work in offline HTML files
    pcall(function()
        -- Remove iframe tags (both self-closing and with content)
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>.-<%s*/%s*iframe%s*>", "")  -- iframe with content
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*/%s*>", "")  -- self-closing iframe
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>", "")  -- opening iframe tag without closing
    end)
    
    return cleaned_content
end

---Create download summary for images
---@param include_images boolean Whether images were included
---@param images ImageInfo[] Array of image information
---@return string Summary message
function ImageUtils.createDownloadSummary(include_images, images)
    local images_downloaded = 0
    if include_images then
        for _, img in ipairs(images) do
            if img.downloaded then
                images_downloaded = images_downloaded + 1
            end
        end
    end
    
    local summary_parts = {}
    
    if include_images and #images > 0 then
        if images_downloaded == #images then
            table.insert(summary_parts, _("All images downloaded successfully"))
        elseif images_downloaded > 0 then
            table.insert(summary_parts, string.format(_("%d of %d images downloaded"), images_downloaded, #images))
        else
            table.insert(summary_parts, _("No images could be downloaded"))
        end
    elseif include_images and #images == 0 then
        table.insert(summary_parts, _("No images found in entry"))
    else
        table.insert(summary_parts, string.format(_("%d images found (skipped - disabled in settings)"), #images))
    end
    
    return table.concat(summary_parts, "\n")
end

return ImageUtils 