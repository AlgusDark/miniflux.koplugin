--[[--
Image Processing Utilities

Consolidated image utilities for RSS entries including discovery, downloading,
and HTML processing. Combines functionality from image_discovery, image_download,
and image_utils for better organization.

@module miniflux.utils.images
--]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local Images = {}

-- =============================================================================
-- IMAGE DISCOVERY
-- =============================================================================

---@class ImageInfo
---@field src string Original image URL
---@field src2x? string High-resolution image URL from srcset
---@field original_tag string Original HTML img tag
---@field filename string Local filename for downloaded image
---@field width? number Image width
---@field height? number Image height
---@field downloaded boolean Whether image was successfully downloaded

-- Legacy regex-based image collection function (used as fallback)
local function collectImgTag(img_tag, base_url, images, seen_images, image_count_ref)
    local src = img_tag:match([[src="([^"]*)"]])
    if not src or src == "" or src:sub(1, 5) == "data:" then
        return img_tag
    end

    local normalized_src = Images.normalizeImageUrl(src, base_url)
    if not seen_images[normalized_src] then
        image_count_ref[1] = image_count_ref[1] + 1
        local image_count = image_count_ref[1]
        local ext = Images.getImageExtension(normalized_src)
        local filename = util.getSafeFilename("image_" .. string.format("%03d", image_count) .. "." .. ext)

        -- Simple attribute extraction for fallback
        local width = tonumber(img_tag:match([[width="([^"]*)"]]))
        local height = tonumber(img_tag:match([[height="([^"]*)"]]))

        local image_info = {
            src = normalized_src,
            original_tag = img_tag,
            filename = filename,
            width = width,
            height = height,
            downloaded = false,
        }

        images[image_count] = image_info
        seen_images[normalized_src] = image_info
    end
    return img_tag
end

---Discover images in HTML content using DOM parser (more reliable than regex)
---@param content string HTML content to scan
---@param base_url? table Parsed base URL for resolving relative URLs
---@return ImageInfo[] Array of discovered images
---@return table<string, ImageInfo> Map of URLs to image info for deduplication
function Images.discoverImages(content, base_url)
    local images = {}
    local seen_images = {}
    local image_count = 0

    -- Try DOM parser approach first (much more reliable than regex)
    local success = pcall(function()
        local htmlparser = require("htmlparser")
        local root = htmlparser.parse(content, 5000)
        local img_elements = root:select("img")

        if img_elements then
            for _, img_element in ipairs(img_elements) do
                local attrs = img_element.attributes or {}
                local src = attrs.src

                if src and src ~= "" and src:sub(1, 5) ~= "data:" then
                    -- Normalize URL
                    local normalized_src = Images.normalizeImageUrl(src, base_url)

                    -- Check for duplicates
                    if not seen_images[normalized_src] then
                        image_count = image_count + 1

                        -- Get file extension
                        local ext = Images.getImageExtension(normalized_src)

                        -- Use KOReader's safe filename utility
                        local base_filename = "image_" .. string.format("%03d", image_count) .. "." .. ext
                        local filename = util.getSafeFilename(base_filename)

                        -- Extract dimensions and srcset directly from DOM attributes
                        local width = tonumber(attrs.width)
                        local height = tonumber(attrs.height)
                        local srcset = attrs.srcset

                        -- Extract high-resolution image URL from srcset
                        local src2x
                        if srcset then
                            -- Add spaces around srcset for pattern matching
                            srcset = " " .. srcset .. ", "
                            src2x = srcset:match([[ (%S+) 2x, ]])
                            if src2x then
                                src2x = Images.normalizeImageUrl(src2x, base_url)
                            end
                        end

                        local image_info = {
                            src = normalized_src,
                            src2x = src2x,
                            original_tag = "", -- Will be reconstructed if needed
                            filename = filename,
                            width = width,
                            height = height,
                            downloaded = false,
                        }

                        -- Use direct indexing for performance
                        images[image_count] = image_info
                        seen_images[normalized_src] = image_info
                    end
                end
            end
        end
    end)

    if success and #images > 0 then
        return images, seen_images
    end

    -- Fallback to regex approach if DOM parser fails
    local fallback_success = pcall(function()
        local image_count_ref = { 0 }
        content:gsub("(<%s*img [^>]*>)", function(img_tag)
            return collectImgTag(img_tag, base_url, images, seen_images, image_count_ref)
        end)
    end)

    if not fallback_success then
        return {}, {}
    end

    return images, seen_images
end

---Normalize image URL for downloading using KOReader's socket_url utilities
---@param src string Original image URL
---@param base_url? table Parsed base URL
---@return string Normalized absolute URL
function Images.normalizeImageUrl(src, base_url)
    -- Handle protocol-relative URLs
    if src:sub(1, 2) == "//" then
        return "https:" .. src
    end

    -- Handle absolute and relative URLs using KOReader's URL utilities
    if src:sub(1, 1) == "/" and base_url then
        return socket_url.absolute(base_url, src)
    elseif not src:match("^https?://") and base_url then
        return socket_url.absolute(base_url, src)
    else
        return src
    end
end

---Get appropriate file extension for image URL
---@param url string Image URL
---@return string File extension (without dot)
function Images.getImageExtension(url)
    -- Remove query parameters and extract extension
    local clean_url = url:find("?") and url:match("(.-)%?") or url
    local ext = clean_url:match(".*%.(%S%S%S?%S?%S?)$")

    if not ext then
        return "jpg"
    end

    ext = ext:lower()

    -- Check if extension is valid
    local valid_extensions = {
        jpg = true, jpeg = true, png = true, gif = true, webp = true, svg = true
    }
    return valid_extensions[ext] and ext or "jpg"
end

-- =============================================================================
-- IMAGE DOWNLOADING
-- =============================================================================

---Download a single image from URL with high-res support
---@param config {url: string, url2x?: string, entry_dir: string, filename: string} Configuration table
---@return boolean True if download successful
function Images.downloadImage(config)
    -- Validate input
    if not config or type(config) ~= "table" or
        not config.url or not config.entry_dir or not config.filename then
        return false
    end

    local filepath = config.entry_dir .. config.filename

    -- Choose high-resolution image if available
    local download_url = config.url2x or config.url

    -- Use KOReader's proper timeout constants
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

    -- Perform HTTP request - download directly to final file
    local result, status_code, headers = http.request({
        url = download_url,
        sink = ltn12.sink.file(io.open(filepath, "wb")),
    })

    -- Always reset timeout
    socketutil:reset_timeout()

    -- Check for basic failure conditions
    if not result or status_code ~= 200 then
        os.remove(filepath) -- Clean up failed download
        return false
    end

    -- Validate content-type if available
    if headers and headers["content-type"] then
        local content_type = headers["content-type"]:lower()
        if not (content_type:find("image/", 1, true) or
                content_type:find("application/octet-stream", 1, true)) then
            os.remove(filepath) -- Clean up invalid content
            return false
        end
    end

    -- Check file was created and has reasonable size using lfs
    local file_attrs = lfs.attributes(filepath)
    if not file_attrs then
        os.remove(filepath)
        return false
    end

    local file_size = file_attrs.size

    -- Sanity check file size (10 bytes minimum, 50MB maximum)
    if file_size < 10 or file_size > 50 * 1024 * 1024 then
        os.remove(filepath) -- Clean up invalid size
        return false
    end

    -- Validate content-length if provided
    if headers and headers["content-length"] then
        local expected_size = tonumber(headers["content-length"])
        if expected_size and file_size ~= expected_size then
            os.remove(filepath) -- Clean up incomplete download
            return false
        end
    end

    return true
end

---Clean up temporary files in entry directory (legacy function - no longer creates .tmp files)
---@param entry_dir string Entry directory path
---@return number Number of temp files cleaned
function Images.cleanupTempFiles(entry_dir)
    local cleaned_count = 0

    if lfs.attributes(entry_dir, "mode") == "directory" then
        for file in lfs.dir(entry_dir) do
            if file:match("%.tmp$") then
                os.remove(entry_dir .. file)
                cleaned_count = cleaned_count + 1
            end
        end
    end

    return cleaned_count
end

-- =============================================================================
-- HTML IMAGE PROCESSING
-- =============================================================================

---Process HTML content to replace image tags based on download results using DOM parser
---@param content string Original HTML content
---@param seen_images table<string, ImageInfo> Map of URLs to image info
---@param include_images boolean Whether to include images in output
---@param base_url? table Parsed base URL for normalizing URLs
---@return string Processed HTML content
function Images.processHtmlImages(content, seen_images, include_images, base_url)
    -- Try DOM parser approach first (much more reliable)
    local success, processed_content = pcall(function()
        local htmlparser = require("htmlparser")
        local root = htmlparser.parse(content, 5000)
        local img_elements = root:select("img")

        if img_elements then
            for _, img_element in ipairs(img_elements) do
                local attrs = img_element.attributes or {}
                local src = attrs.src

                if src and src ~= "" then
                    -- Skip data URLs
                    if src:sub(1, 5) == "data:" then
                        if not include_images then
                            -- Remove data URL images if include_images is false
                            if img_element.parent then
                                for i, child in ipairs(img_element.parent) do
                                    if child == img_element then
                                        table.remove(img_element.parent, i)
                                        break
                                    end
                                end
                            end
                        end
                    else
                        -- Normalize the URL to match what we stored
                        local normalized_src = Images.normalizeImageUrl(src, base_url)
                        local img_info = seen_images[normalized_src]

                        if img_info then
                            if include_images and img_info.downloaded then
                                -- Image was successfully downloaded, replace with local path
                                attrs.src = img_info.filename
                                -- Preserve or set dimensions
                                if img_info.width then
                                    attrs.style = (attrs.style or "") ..
                                        string.format("width: %spx; ", img_info.width)
                                end
                                if img_info.height then
                                    attrs.style = (attrs.style or "") ..
                                        string.format("height: %spx; ", img_info.height)
                                end
                                -- Clean up style if it was empty before
                                if attrs.style and attrs.style:match("^%s*$") then
                                    attrs.style = nil
                                end
                            elseif not include_images then
                                -- Remove image from DOM
                                if img_element.parent then
                                    for i, child in ipairs(img_element.parent) do
                                        if child == img_element then
                                            table.remove(img_element.parent, i)
                                            break
                                        end
                                    end
                                end
                            end
                            -- If include_images is true but image wasn't downloaded,
                            -- leave the original img element unchanged
                        else
                            -- Image not in our list - handle gracefully
                            if not include_images then
                                -- Remove image from DOM
                                if img_element.parent then
                                    for i, child in ipairs(img_element.parent) do
                                        if child == img_element then
                                            table.remove(img_element.parent, i)
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    -- No src attribute - remove if include_images is false
                    if not include_images and img_element.parent then
                        for i, child in ipairs(img_element.parent) do
                            if child == img_element then
                                table.remove(img_element.parent, i)
                                break
                            end
                        end
                    end
                end
            end
        end

        return root:getcontent() or content
    end)

    if success and processed_content and processed_content ~= "" then
        return processed_content
    end

    -- Fallback to regex approach if DOM parser fails
    local replaceImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            return include_images and img_tag or ""
        end

        if src:sub(1, 5) == "data:" then
            return include_images and img_tag or ""
        end

        local normalized_src = Images.normalizeImageUrl(src or "", base_url)
        local img_info = seen_images[normalized_src]

        if img_info then
            if include_images and img_info.downloaded then
                return Images.createLocalImageTag(img_info)
            elseif include_images then
                return img_tag -- Keep original URL
            else
                return ""      -- Remove image
            end
        else
            return include_images and img_tag or ""
        end
    end

    local fallback_success, fallback_content = pcall(function()
        return content:gsub("(<%s*img [^>]*>)", replaceImg)
    end)

    return (fallback_success and fallback_content) or content
end

---Create a local image tag with proper styling
---@param img_info ImageInfo Image information
---@return string HTML img tag for local image
function Images.createLocalImageTag(img_info)
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

---Create download summary for images
---@param include_images boolean Whether images were included
---@param images ImageInfo[] Array of image information
---@return string Summary message
function Images.createDownloadSummary(include_images, images)
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

return Images
