--[[--
Image Discovery Utilities

This utility module handles image discovery and URL processing for RSS entries.
Separated from image_utils.lua to improve organization and maintainability.

@module miniflux.utils.image_discovery
--]]

local socket_url = require("socket.url")
local _ = require("gettext")

local ImageDiscovery = {}

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
function ImageDiscovery.discoverImages(content, base_url)
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
        if src and src:sub(1, 5) == "data:" then
            return img_tag -- Keep original tag
        end

        -- Normalize URL
        local normalized_src = ImageDiscovery.normalizeImageUrl(src or "", base_url)

        if not seen_images[normalized_src] then
            image_count = image_count + 1

            -- Get file extension
            local ext = ImageDiscovery.getImageExtension(normalized_src)
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
                downloaded = false,
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
function ImageDiscovery.normalizeImageUrl(src, base_url)
    -- Handle different URL types
    if src:sub(1, 2) == "//" then
        return "https:" .. src -- Use HTTPS for protocol-relative URLs
    elseif src:sub(1, 1) == "/" and base_url then
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
function ImageDiscovery.getImageExtension(url)
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
    local valid_exts = { jpg = true, jpeg = true, png = true, gif = true, webp = true, svg = true }
    if not valid_exts[ext] then
        ext = "jpg" -- fallback to jpg
    end

    return ext
end

return ImageDiscovery
