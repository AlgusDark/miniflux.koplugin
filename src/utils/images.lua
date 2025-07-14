local http = require('socket.http')
local ltn12 = require('ltn12')
local socket_url = require('socket.url')
local socketutil = require('socketutil')
local lfs = require('libs/libkoreader-lfs')
local util = require('util')
local _ = require('gettext')

-- [Third party](https://github.com/koreader/koreader-base/tree/master/thirdparty) tool
-- https://github.com/msva/lua-htmlparser
local htmlparser = require('htmlparser')

-- **Images** - Consolidated image utilities for RSS entries including discovery,
-- downloading, and HTML processing. Combines functionality from image_discovery,
-- image_download, and image_utils for better organization.
local Images = {}

-- Pre-compiled regex patterns for performance
local IMG_SRC_PATTERN = [[src="([^"]*)"]]
local IMG_TAG_PATTERN = '(<%s*img [^>]*>)'

-- =============================================================================
-- IMAGE UTILITIES
-- =============================================================================

-- Valid image file extensions for validation
local valid_extensions = {
    jpg = true,
    jpeg = true,
    png = true,
    gif = true,
    webp = true,
    svg = true,
}

-- Generate consistent image filename with safe formatting
local function generateImageFilename(image_count, ext)
    local base_filename = 'image_' .. string.format('%03d', image_count) .. '.' .. ext
    return util.getSafeFilename(base_filename)
end

-- Format CSS pixel values consistently
local function formatPixelValue(dimension, value)
    return string.format('%s: %spx', dimension, value)
end

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
---@field error_reason? string Error reason if download failed

---Discover images in HTML content using DOM parser (more reliable than regex)
---@param content string HTML content to scan
---@param base_url? table Parsed base URL for resolving relative URLs
---@return ImageInfo[] images, table<string, ImageInfo> seen_images
function Images.discoverImages(content, base_url)
    local images = {}
    local seen_images = {}
    local image_count = 0

    -- Use DOM parser approach (reliable)
    local root = htmlparser.parse(content, 5000)
    local img_elements = root:select('img')

    if img_elements then
        for i, img_element in ipairs(img_elements) do
            local attrs = img_element.attributes or {}
            local src = attrs.src

            if src and src ~= '' and src:sub(1, 5) ~= 'data:' then
                -- Normalize URL
                local normalized_src = Images.normalizeImageUrl(src, base_url)

                -- Check for duplicates
                if not seen_images[normalized_src] then
                    image_count = image_count + 1

                    -- Get file extension
                    local ext = Images.getImageExtension(normalized_src)

                    -- Use KOReader's safe filename utility
                    local filename = generateImageFilename(image_count, ext)

                    -- Extract dimensions and srcset directly from DOM attributes
                    local width = tonumber(attrs.width)
                    local height = tonumber(attrs.height)
                    local srcset = attrs.srcset

                    -- Extract high-resolution image URL from srcset
                    local src2x
                    if srcset then
                        -- Add spaces around srcset for pattern matching
                        srcset = ' ' .. srcset .. ', '
                        src2x = srcset:match([[ (%S+) 2x, ]])
                        if src2x then
                            src2x = Images.normalizeImageUrl(src2x, base_url)
                        end
                    end

                    local image_info = {
                        src = normalized_src,
                        src2x = src2x,
                        original_tag = '', -- Will be reconstructed if needed
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

    return images, seen_images
end

---Normalize image URL for downloading using KOReader's socket_url utilities
---@param src string Original image URL
---@param base_url? table Parsed base URL
---@return string Normalized absolute URL
function Images.normalizeImageUrl(src, base_url)
    -- Handle protocol-relative URLs
    if src:sub(1, 2) == '//' then
        return 'https:' .. src
    end

    -- Handle root-relative and other relative URLs using KOReader's URL utilities
    if src:sub(1, 1) == '/' and base_url then
        return socket_url.absolute(base_url, src)
    elseif base_url and not (src:sub(1, 7) == 'http://' or src:sub(1, 8) == 'https://') then
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
    local clean_url = url:find('?') and url:match('(.-)%?') or url
    local ext = clean_url:match('.*%.(%S%S%S?%S?%S?)$')

    if not ext then
        return 'jpg'
    end

    ext = ext:lower()

    -- Check if extension is valid
    return valid_extensions[ext] and ext or 'jpg'
end

-- =============================================================================
-- IMAGE DOWNLOADING
-- =============================================================================

---Apply proxy URL to image download URL if proxy is enabled and configured
---@param settings MinifluxSettings Settings instance with proxy configuration
---@param image_url string Original image URL to download
---@return string Final URL to use for download (proxied or original)
function Images.applyProxyUrl(settings, image_url)
    -- Check if proxy is enabled and URL is configured
    if
        settings.proxy_image_downloader_enabled
        and settings.proxy_image_downloader_url
        and settings.proxy_image_downloader_url ~= ''
    then
        return settings.proxy_image_downloader_url .. util.urlEncode(image_url)
    end

    -- Return original URL if proxy not configured
    return image_url
end

---Download a single image from URL with high-res support
---@param config {url: string, url2x?: string, entry_dir: string, filename: string, settings?: MinifluxSettings} Configuration table
---@return boolean True if download successful
function Images.downloadImage(config)
    -- Validate input
    if
        not config
        or type(config) ~= 'table'
        or not config.url
        or not config.entry_dir
        or not config.filename
    then
        return false
    end

    local filepath = config.entry_dir .. config.filename

    -- Choose high-resolution image if available
    local download_url = config.url2x or config.url

    -- Build HTTP request configuration
    local http_config = {
        url = download_url,
        sink = ltn12.sink.file(io.open(filepath, 'wb')),
    }

    -- Apply proxy settings if provided
    if config.settings then
        download_url = Images.applyProxyUrl(config.settings, download_url)
        http_config.url = download_url

        -- Add proxy authentication headers if needed
        if
            config.settings.proxy_image_downloader_enabled
            and config.settings.proxy_image_downloader_token
            and config.settings.proxy_image_downloader_token ~= ''
        then
            http_config.headers = {
                ['Authorization'] = 'Bearer ' .. config.settings.proxy_image_downloader_token,
            }
        end
    end

    -- Use KOReader's proper timeout constants
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

    -- Perform HTTP request - download directly to final file
    local result, status_code, headers = http.request(http_config)

    -- Always reset timeout
    socketutil:reset_timeout()

    -- Check for basic failure conditions
    if not result or status_code ~= 200 then
        os.remove(filepath) -- Clean up failed download
        return false
    end

    -- Validate content-type if available
    if headers and headers['content-type'] then
        local content_type = headers['content-type']:lower()
        if
            not (
                content_type:find('image/', 1, true)
                or content_type:find('application/octet-stream', 1, true)
            )
        then
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
    if headers and headers['content-length'] then
        local expected_size = tonumber(headers['content-length'])
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

    if lfs.attributes(entry_dir, 'mode') == 'directory' then
        for file in lfs.dir(entry_dir) do
            if file:match('%.tmp$') then
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
---@param opts table Options containing seen_images, include_images, base_url
---@return string Processed HTML content
function Images.processHtmlImages(content, opts)
    -- Extract parameters from opts
    local seen_images = opts.seen_images
    local include_images = opts.include_images
    local base_url = opts.base_url

    -- If include_images is false, return content unchanged (no processing needed)
    if not include_images then
        return content
    end

    -- Use regex approach for image replacement (proven pattern used by newsdownloader.koplugin)
    local replaceImg = function(img_tag)
        local src = img_tag:match(IMG_SRC_PATTERN)

        -- Skip data URLs, empty src, or if include_images is false
        if not src or src == '' or src:sub(1, 5) == 'data:' then
            return img_tag
        end

        local normalized_src = Images.normalizeImageUrl(src, base_url)
        local img_info = seen_images[normalized_src]

        -- Only replace if image was successfully downloaded
        if img_info and img_info.downloaded then
            return Images.createLocalImageTag(img_info)
        else
            return img_tag -- Leave original unchanged
        end
    end

    local processed_content = content:gsub(IMG_TAG_PATTERN, replaceImg)

    return processed_content
end

---Create a local image tag with proper styling
---@param img_info ImageInfo Image information
---@return string HTML img tag for local image
function Images.createLocalImageTag(img_info)
    local style_props = {}

    if img_info.width then
        table.insert(style_props, formatPixelValue('width', img_info.width))
    end
    if img_info.height then
        table.insert(style_props, formatPixelValue('height', img_info.height))
    end

    local style = table.concat(style_props, '; ')
    if style ~= '' then
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
        for i, img in ipairs(images) do
            if img.downloaded then
                images_downloaded = images_downloaded + 1
            end
        end
    end

    local summary_parts = {}

    if include_images and #images > 0 then
        if images_downloaded == #images then
            table.insert(summary_parts, _('All images downloaded successfully'))
        elseif images_downloaded > 0 then
            table.insert(
                summary_parts,
                string.format(_('%d of %d images downloaded'), images_downloaded, #images)
            )
        else
            table.insert(summary_parts, _('No images could be downloaded'))
        end
    elseif include_images and #images == 0 then
        table.insert(summary_parts, _('No images found in entry'))
    else
        table.insert(
            summary_parts,
            string.format(_('%d images found (skipped - disabled in settings)'), #images)
        )
    end

    return table.concat(summary_parts, '\n')
end

return Images
