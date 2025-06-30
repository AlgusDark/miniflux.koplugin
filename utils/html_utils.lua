--[[--
HTML Utilities for Miniflux Browser

This utility module handles HTML document creation and processing for offline
viewing of RSS entries in KOReader.

@module miniflux.browser.utils.html_utils
--]]

local _ = require("gettext")
local util = require("util") -- Use KOReader's built-in utilities

local HtmlUtils = {}

---Create a complete HTML document for an entry
---@param entry MinifluxEntry Entry data
---@param content string Processed HTML content
---@return string Complete HTML document
function HtmlUtils.createHtmlDocument(entry, content)
    local entry_title = entry.title or _("Untitled Entry")

    -- Use KOReader's built-in HTML escape (more robust than custom implementation)
    local escaped_title = util.htmlEscape(entry_title)

    -- Build metadata sections using table for efficient concatenation
    local metadata_sections = {}
    local section_count = 0

    -- Feed information
    if entry.feed and entry.feed.title then
        section_count = section_count + 1
        metadata_sections[section_count] = "<p><strong>" ..
            _("Feed") .. ":</strong> " .. util.htmlEscape(entry.feed.title) .. "</p>"
    end

    -- Publication date (no escaping needed for timestamp)
    if entry.published_at then
        section_count = section_count + 1
        metadata_sections[section_count] = "<p><strong>" ..
            _("Published") .. ":</strong> " .. entry.published_at .. "</p>"
    end

    -- Original URL
    if entry.url then
        local base_url = entry.url:match("^(https?://[^/]+)") or entry.url
        section_count = section_count + 1
        metadata_sections[section_count] = '<p><strong>' ..
            _("URL") .. ':</strong> <a href="' .. entry.url .. '">' .. util.htmlEscape(base_url) .. '</a></p>'
    end

    -- Build final HTML using efficient concatenation
    local metadata_html = table.concat(metadata_sections, "\n        ")

    -- Create HTML document with inlined template
    local html_parts = {
        string.format([[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>]], escaped_title, escaped_title),
        metadata_html ~= "" and ("\n        " .. metadata_html) or "",
        string.format([[    </div>
    <div class="entry-content">
        %s
    </div>
</body>
</html>]], content)
    }

    return table.concat(html_parts)
end

---Clean and normalize HTML content for offline viewing using DOM parser
---@param content string Raw HTML content
---@return string Cleaned HTML content
function HtmlUtils.cleanHtmlContent(content)
    if not content or content == "" then
        return ""
    end

    -- Try HTML parser approach first (much more reliable)
    local success, cleaned_content = pcall(function()
        local htmlparser = require("htmlparser")
        local root = htmlparser.parse(content, 5000)

        -- Elements that won't work offline - remove using CSS selectors
        local unwanted_selectors = {
            "script", -- Scripts (security and functionality)
            "iframe", -- Iframes (won't work offline)
            "video",  -- Videos (won't work offline)
            "object", -- Objects and embeds (multimedia)
            "embed",  -- Flash/multimedia embeds
            "form",   -- Forms (won't work offline)
            "style",  -- Style blocks (can cause display issues)
        }

        -- Remove each type of unwanted element
        for _, selector in ipairs(unwanted_selectors) do
            local elements = root:select(selector)
            if elements then
                for _, element in ipairs(elements) do
                    -- Remove the element from DOM
                    if element.parent then
                        for i, child in ipairs(element.parent) do
                            if child == element then
                                table.remove(element.parent, i)
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Return the cleaned HTML
        return root:getcontent() or content
    end)

    if success and cleaned_content and cleaned_content ~= "" then
        return cleaned_content
    end

    -- Fallback to regex patterns if HTML parser fails
    local fallback_success, fallback_content = pcall(function()
        local temp_content = content

        -- Basic fallback patterns for critical elements
        temp_content = temp_content:gsub("<%s*script[^>]*>.-<%s*/%s*script%s*>", "")
        temp_content = temp_content:gsub("<%s*script[^>]*>", "")
        temp_content = temp_content:gsub("<%s*style[^>]*>.-<%s*/%s*style%s*>", "")

        return temp_content
    end)

    if fallback_success and fallback_content then
        return fallback_content
    end

    -- If everything fails, return original content (safer than empty string)
    return content
end

---Clean tracking parameters from URLs in HTML using DOM parser
---@param content string HTML content with URLs
---@return string HTML with cleaned URLs
function HtmlUtils.cleanTrackingUrls(content)
    if not content or content == "" then
        return ""
    end

    -- Try DOM parser approach
    local success, cleaned_content = pcall(function()
        local htmlparser = require("htmlparser")
        local root = htmlparser.parse(content, 5000)

        -- Clean tracking parameters from links
        local link_elements = root:select("a[href]")
        if link_elements then
            for _, link in ipairs(link_elements) do
                local href = link.attributes.href
                if href then
                    -- Remove common tracking parameters
                    local cleaned_href = href:gsub("[?&]utm_[^&]*", "")
                        :gsub("[?&]fbclid=[^&]*", "")
                        :gsub("[?&]gclid=[^&]*", "")
                        :gsub("[?&]ref=[^&]*", "")
                        :gsub("[?&]source=[^&]*", "")
                        :gsub("^([^?]*)[?]&", "%1?") -- Fix malformed query strings
                        :gsub("^([^?]*)[?]$", "%1")  -- Remove trailing ?
                    link.attributes.href = cleaned_href
                end
            end
        end

        return root:getcontent() or content
    end)

    return (success and cleaned_content) or content
end

---Extract main content from article HTML using common content selectors
---@param content string Full HTML content
---@return string Extracted main content
function HtmlUtils.extractMainContent(content)
    if not content or content == "" then
        return ""
    end

    -- Try DOM parser approach with content extraction (similar to newsdownloader)
    local success, extracted_content = pcall(function()
        local htmlparser = require("htmlparser")
        local root = htmlparser.parse(content, 5000)

        -- Try common content selectors (ordered by specificity)
        local content_selectors = {
            "article",
            "main",
            ".article-content",
            ".entry-content",
            ".post-content",
            ".content",
            "#content",
            ".main-content",
            "#main",
        }

        for _, selector in ipairs(content_selectors) do
            local elements = root:select(selector)
            if elements and #elements > 0 then
                local content_element = elements[1]         -- Take first match
                local extracted = content_element:getcontent()
                if extracted and extracted:len() > 100 then -- Ensure substantial content
                    return "<!DOCTYPE html><html><head></head><body>" .. extracted .. "</body></html>"
                end
            end
        end

        -- If no specific content found, return cleaned full content
        return content
    end)

    return (success and extracted_content) or content
end

return HtmlUtils
