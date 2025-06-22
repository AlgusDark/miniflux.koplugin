--[[--
Image Processing Utilities

This utility module handles HTML image processing, tag manipulation,
and provides image-related helper functions.

@module miniflux.utils.image_utils
--]]

local ImageDiscovery = require("utils/image_discovery")
local _ = require("gettext")

local ImageUtils = {}

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
        local normalized_src = ImageDiscovery.normalizeImageUrl(src or "", base_url)

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
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>.-<%s*/%s*iframe%s*>", "") -- iframe with content
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*/%s*>", "")                 -- self-closing iframe
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>", "")                     -- opening iframe tag without closing
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
