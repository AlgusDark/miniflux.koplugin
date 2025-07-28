local _ = require('gettext')
local util = require('util') -- Use KOReader's built-in utilities

-- [Third party](https://github.com/koreader/koreader-base/tree/master/thirdparty) tool
-- https://github.com/msva/lua-htmlparser
local htmlparser = require('htmlparser')

-- Import dependencies for entry content processing
local Images = require('features/browser/download/utils/images')
local Error = require('shared/error')

-- **HtmlUtils** - HTML utilities for Miniflux Browser
--
-- This utility module handles HTML document creation and processing for offline
-- viewing of RSS entries in KOReader.
local HtmlUtils = {}

-- Escape string for use in Lua pattern matching
local function escapePattern(str)
    -- Escape special pattern characters: ( ) . % + - * ? [ ] ^ $
    return str:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')
end

-- =============================================================================
-- ENTRY CONTENT PROCESSING
-- =============================================================================

-- TODO: Think of a better name for this function
-- Current candidates: processEntryContent, transformEntryHtml, processHtmlContent
---Process and transform entry content HTML
---@param raw_content string Raw HTML content
---@param options table {entry_data, seen_images, base_url, include_images}
---@return string|nil processed_html, Error|nil error
function HtmlUtils.processEntryContent(raw_content, options)
    local entry_data = options.entry_data
    local seen_images = options.seen_images
    local base_url = options.base_url
    local include_images = options.include_images

    if not entry_data or not raw_content then
        return nil, Error.new('Invalid parameters for HTML processing')
    end

    -- Process and clean content
    local processed_content = Images.processHtmlImages(raw_content, {
        seen_images = seen_images,
        include_images = include_images,
        base_url = base_url,
    })
    processed_content = HtmlUtils.cleanHtmlContent(processed_content)

    -- Create HTML document
    local html_content = HtmlUtils.createHtmlDocument(entry_data, processed_content)

    if not html_content then
        return nil, Error.new('Failed to process HTML content')
    end

    return html_content, nil
end

-- =============================================================================
-- HTML DOCUMENT CREATION
-- =============================================================================

---Create a complete HTML document for an entry
---@param entry MinifluxEntry Entry data
---@param content string Processed HTML content
---@return string Complete HTML document
function HtmlUtils.createHtmlDocument(entry, content)
    local entry_title = entry.title or _('Untitled Entry')

    -- Use KOReader's built-in HTML escape (more robust than custom implementation)
    local escaped_title = util.htmlEscape(entry_title)

    -- Build metadata sections using table for efficient concatenation
    local metadata_sections = {}
    local section_count = 0

    -- Feed information
    if entry.feed and entry.feed.title then
        section_count = section_count + 1
        metadata_sections[section_count] = '<p><strong>'
            .. _('Feed')
            .. ':</strong> '
            .. util.htmlEscape(entry.feed.title)
            .. '</p>'
    end

    -- Publication date (no escaping needed for timestamp)
    if entry.published_at then
        section_count = section_count + 1
        metadata_sections[section_count] = '<p><strong>'
            .. _('Published')
            .. ':</strong> '
            .. entry.published_at
            .. '</p>'
    end

    -- Original URL
    if entry.url then
        local base_url = entry.url:match('^(https?://[^/]+)') or entry.url
        section_count = section_count + 1
        metadata_sections[section_count] = '<p><strong>'
            .. _('URL')
            .. ':</strong> <a href="'
            .. entry.url
            .. '">'
            .. util.htmlEscape(base_url)
            .. '</a></p>'
    end

    -- Build final HTML using efficient concatenation
    local metadata_html = table.concat(metadata_sections, '\n        ')

    -- Create HTML document with inlined template
    local html_parts = {
        string.format(
            [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>]],
            escaped_title,
            escaped_title
        ),
        metadata_html ~= '' and ('\n        ' .. metadata_html) or '',
        string.format(
            [[    </div>
    <div class="entry-content">
        %s
    </div>
</body>
</html>]],
            content
        ),
    }

    return table.concat(html_parts)
end

---Clean and normalize HTML content for offline viewing using DOM parser
---@param content string Raw HTML content
---@return string Cleaned HTML content
function HtmlUtils.cleanHtmlContent(content)
    if not content or content == '' then
        return ''
    end

    -- Elements that won't work offline - remove using CSS selectors
    local unwanted_selectors = {
        'script', -- Scripts (security and functionality)
        'iframe', -- Iframes (won't work offline)
        'video', -- Videos (won't work offline)
        'object', -- Objects and embeds (multimedia)
        'embed', -- Flash/multimedia embeds
        'form', -- Forms (won't work offline)
        'style', -- Style blocks (can cause display issues)
    }

    -- Use HTML parser approach (reliable)
    local root = htmlparser.parse(content, 5000)

    -- Track elements that get removed for efficient string replacement
    local removed_element_texts = {}
    local total_removed = 0

    -- Remove each type of unwanted element
    for _, selector in ipairs(unwanted_selectors) do
        local elements = root:select(selector)
        if elements then
            for _, element in ipairs(elements) do
                -- Get the original element text BEFORE removal
                local element_text = element:gettext()
                if element_text and element_text ~= '' then
                    removed_element_texts[element_text] = true
                    total_removed = total_removed + 1
                end
            end
        end
    end

    -- Use efficient string replacement instead of DOM reconstruction
    if total_removed > 0 then
        local cleaned_content = content
        for element_text, _ in pairs(removed_element_texts) do
            local escaped_pattern = escapePattern(element_text)
            cleaned_content = cleaned_content:gsub(escaped_pattern, '')
        end
        return cleaned_content
    else
        return content
    end
end

return HtmlUtils
