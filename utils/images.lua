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
local _ = require("gettext")

local Images = {}

-- =============================================================================
-- IMAGE DISCOVERY
-- =============================================================================

-- Pre-compiled patterns for better performance
local IMG_PATTERN = "(<%s*img [^>]*>)"
local SRC_PATTERN = [[src="([^"]*)]]
local WIDTH_PATTERN = [[width="([^"]*)]]
local HEIGHT_PATTERN = [[height="([^"]*)]]
local QUERY_PATTERN = "(.-)%?"
local EXT_PATTERN = ".*%.(%S%S%S?%S?%S?)$"

-- Pre-compiled URL type detection patterns
local PROTOCOL_RELATIVE_PREFIX = "//"
local ABSOLUTE_PATH_PREFIX = "/"
local DATA_URL_PREFIX = "data:"
local HTTP_PATTERN = "^https?://"

-- Pre-compiled extension validation lookup (constant table)
local VALID_EXTENSIONS = {
    jpg = true,
    jpeg = true,
    png = true,
    gif = true,
    webp = true,
    svg = true
}

---@class ImageInfo
---@field src string Original image URL
---@field original_tag string Original HTML img tag
---@field filename string Local filename for downloaded image
---@field width? number Image width
---@field height? number Image height
---@field downloaded boolean Whether image was successfully downloaded

-- Module-level function to avoid closure creation overhead
---@param img_tag string HTML img tag
---@param base_url? table Parsed base URL for resolving relative URLs
---@param images table Array to store discovered images
---@param seen_images table Map of URLs to image info
---@param image_count_ref table Reference to image counter
---@return string Original img tag (unchanged)
local function collectImgTag(img_tag, base_url, images, seen_images, image_count_ref)
    -- Extract src attribute
    local src = img_tag:match(SRC_PATTERN)
    if not src or src == "" then
        return img_tag
    end

    -- Skip data URLs with single prefix check
    if src:sub(1, 5) == DATA_URL_PREFIX then
        return img_tag
    end

    -- Normalize URL
    local normalized_src = Images.normalizeImageUrl(src, base_url)

    -- Check for duplicates
    if not seen_images[normalized_src] then
        image_count_ref[1] = image_count_ref[1] + 1
        local image_count = image_count_ref[1]

        -- Get file extension
        local ext = Images.getImageExtension(normalized_src)
        local filename = "image_" .. string.format("%03d", image_count) .. "." .. ext

        -- Extract dimensions with pre-compiled patterns
        local width = tonumber(img_tag:match(WIDTH_PATTERN))
        local height = tonumber(img_tag:match(HEIGHT_PATTERN))

        local image_info = {
            src = normalized_src,
            original_tag = img_tag,
            filename = filename,
            width = width,
            height = height,
            downloaded = false,
        }

        -- Use direct indexing instead of table.insert
        images[image_count] = image_info
        seen_images[normalized_src] = image_info
    end

    return img_tag
end

---Discover images in HTML content
---@param content string HTML content to scan
---@param base_url? table Parsed base URL for resolving relative URLs
---@return ImageInfo[] Array of discovered images
---@return table<string, ImageInfo> Map of URLs to image info for deduplication
function Images.discoverImages(content, base_url)
    local images = {}
    local seen_images = {}
    local image_count_ref = { 0 } -- Use table reference for counter

    -- Scan content for images using pre-compiled pattern
    local scan_success = pcall(function()
        content:gsub(IMG_PATTERN, function(img_tag)
            return collectImgTag(img_tag, base_url, images, seen_images, image_count_ref)
        end)
    end)

    if not scan_success then
        return {}, {}
    end

    return images, seen_images
end

---Normalize image URL for downloading with optimized type detection
---@param src string Original image URL
---@param base_url? table Parsed base URL
---@return string Normalized absolute URL
function Images.normalizeImageUrl(src, base_url)
    -- Single string analysis for URL type detection
    local first_char = src:sub(1, 1)
    local first_two = src:sub(1, 2)

    if first_two == PROTOCOL_RELATIVE_PREFIX then
        return "https:" .. src
    elseif first_char == ABSOLUTE_PATH_PREFIX and base_url then
        return socket_url.absolute(base_url, src)
    elseif not src:match(HTTP_PATTERN) and base_url then
        return socket_url.absolute(base_url, src)
    else
        return src
    end
end

---Get appropriate file extension for image URL with optimized processing
---@param url string Image URL
---@return string File extension (without dot)
function Images.getImageExtension(url)
    -- Single operation to remove query parameters
    local clean_url = url:find("?") and url:match(QUERY_PATTERN) or url

    -- Extract extension with pre-compiled pattern
    local ext = clean_url:match(EXT_PATTERN)
    if not ext then
        return "jpg"
    end

    ext = ext:lower()

    -- Use pre-compiled lookup table
    return VALID_EXTENSIONS[ext] and ext or "jpg"
end

-- =============================================================================
-- IMAGE DOWNLOADING
-- =============================================================================

---Download a single image from URL with atomic .tmp file handling
---@param config {url: string, entry_dir: string, filename: string} Configuration table
---@return boolean True if download successful
function Images.downloadImage(config)
    -- Validate input
    if not config or type(config) ~= "table" or
        not config.url or not config.entry_dir or not config.filename then
        return false
    end

    local filepath = config.entry_dir .. config.filename
    local temp_filepath = filepath .. ".tmp"

    -- Simple cleanup helper
    local function cleanup_temp()
        os.remove(temp_filepath)
    end

    -- Set network timeout
    socketutil:set_timeout(10, 30)

    -- Perform HTTP request
    local result, status_code, headers = http.request({
        url = config.url,
        sink = ltn12.sink.file(io.open(temp_filepath, "wb")),
    })

    -- Always reset timeout
    socketutil:reset_timeout()

    -- Check for basic failure conditions
    if not result or status_code ~= 200 then
        cleanup_temp()
        return false
    end

    -- Validate content-type if available
    if headers and headers["content-type"] then
        local content_type = headers["content-type"]:lower()
        if not (content_type:find("image/", 1, true) or
                content_type:find("application/octet-stream", 1, true)) then
            cleanup_temp()
            return false
        end
    end

    -- Check file was actually created and has reasonable size
    local temp_file = io.open(temp_filepath, "rb")
    if not temp_file then
        cleanup_temp()
        return false
    end

    temp_file:seek("end")
    local file_size = temp_file:seek()
    temp_file:close()

    -- Sanity check file size (10 bytes minimum, 50MB maximum)
    if file_size < 10 or file_size > 50 * 1024 * 1024 then
        cleanup_temp()
        return false
    end

    -- Validate content-length if provided
    if headers and headers["content-length"] then
        local expected_size = tonumber(headers["content-length"])
        if expected_size and file_size ~= expected_size then
            cleanup_temp()
            return false
        end
    end

    -- Atomic rename from .tmp to final file
    os.remove(filepath) -- Remove target if exists
    local rename_success = os.rename(temp_filepath, filepath)

    if not rename_success then
        cleanup_temp()
        return false
    end

    -- Final verification that target file exists
    local final_file = io.open(filepath, "rb")
    if not final_file then
        os.remove(filepath)
        return false
    end
    final_file:close()

    return true
end

---Clean up temporary files in entry directory
---@param entry_dir string Entry directory path
---@return number Number of temp files cleaned
function Images.cleanupTempFiles(entry_dir)
    local lfs = require("libs/libkoreader-lfs")
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

---Process HTML content to replace image tags based on download results
---@param content string Original HTML content
---@param seen_images table<string, ImageInfo> Map of URLs to image info
---@param include_images boolean Whether to include images in output
---@param base_url? table Parsed base URL for normalizing URLs
---@return string Processed HTML content
function Images.processHtmlImages(content, seen_images, include_images, base_url)
    local replaceImg = function(img_tag)
        -- Find which image this tag corresponds to
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            if include_images then
                return img_tag -- Keep original if we can't identify it
            else
                return ""      -- Remove if include_images is false
            end
        end

        -- Skip data URLs
        if src and src:sub(1, 5) == "data:" then
            if include_images then
                return img_tag -- Keep data URLs as-is
            else
                return ""      -- Remove if include_images is false
            end
        end

        -- Normalize the URL to match what we stored
        local normalized_src = Images.normalizeImageUrl(src or "", base_url)

        local img_info = seen_images[normalized_src]
        if img_info then
            if include_images and img_info.downloaded then
                -- Image was successfully downloaded, use local path
                return Images.createLocalImageTag(img_info)
            elseif include_images then
                -- Image download failed but include_images is true - keep original URL
                return img_tag
            else
                -- include_images is false - remove image
                return ""
            end
        else
            -- Image not in our list (shouldn't happen, but handle gracefully)
            if include_images then
                return img_tag -- Keep original
            else
                return ""      -- Remove
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
