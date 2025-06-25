--[[--
Image Discovery Utilities

This utility module handles image discovery and URL processing for RSS entries.
Separated from image_utils.lua to improve organization and maintainability.

@module miniflux.utils.image_discovery
--]]

local socket_url = require("socket.url")
local _ = require("gettext")

local ImageDiscovery = {}

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
    local normalized_src = ImageDiscovery.normalizeImageUrl(src, base_url)

    -- Check for duplicates
    if not seen_images[normalized_src] then
        image_count_ref[1] = image_count_ref[1] + 1
        local image_count = image_count_ref[1]

        -- Get file extension
        local ext = ImageDiscovery.getImageExtension(normalized_src)
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
function ImageDiscovery.discoverImages(content, base_url)
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
function ImageDiscovery.normalizeImageUrl(src, base_url)
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
function ImageDiscovery.getImageExtension(url)
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

return ImageDiscovery
