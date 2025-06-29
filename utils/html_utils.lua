--[[--
HTML Utilities for Miniflux Browser

This utility module handles HTML document creation and processing for offline
viewing of RSS entries in KOReader.

@module miniflux.browser.utils.html_utils
--]]

local _ = require("gettext")
local util = require("util") -- Use KOReader's built-in utilities

local HtmlUtils = {}

-- Pre-compiled HTML template parts for better performance
local HTML_TEMPLATE_HEAD = [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>]]

local HTML_TEMPLATE_TAIL = [[    </div>
    <div class="entry-content">
        %s
    </div>
</body>
</html>]]

-- Simple cleanup patterns for better performance
local CLEANUP_PATTERNS = {
    -- Scripts (security and functionality)
    "<%s*script[^>]*>.-<%s*/%s*script%s*>",
    "<%s*script[^>]*>",
    -- Iframes (won't work offline)
    "<%s*iframe[^>]*>.-<%s*/%s*iframe%s*>",
    "<%s*iframe[^>]*/%s*>",
    "<%s*iframe[^>]*>",
    -- Videos (won't work offline)
    "<%s*video[^>]*>.-<%s*/%s*video%s*>",
    "<%s*video[^>]*/%s*>",
    "<%s*video[^>]*>",
    -- Objects and embeds (multimedia)
    "<%s*object[^>]*>.-<%s*/%s*object%s*>",
    "<%s*embed[^>]*>",
    -- Forms (won't work offline)
    "<%s*form[^>]*>.-<%s*/%s*form%s*>",
    -- Style blocks
    "<%s*style[^>]*>.-<%s*/%s*style%s*>",
}

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

    -- Build final HTML using pre-compiled templates and efficient concatenation
    local metadata_html = table.concat(metadata_sections, "\n        ")

    return string.format(HTML_TEMPLATE_HEAD, escaped_title, escaped_title) ..
        (metadata_html ~= "" and ("\n        " .. metadata_html) or "") ..
        string.format(HTML_TEMPLATE_TAIL, content)
end

---Escape HTML special characters using KOReader's built-in utility
---@param text string Text to escape
---@return string Escaped text
function HtmlUtils.escapeHtml(text)
    if not text then
        return ""
    end
    -- Use KOReader's built-in HTML escape function (handles more entities than custom version)
    return util.htmlEscape(text)
end

---Clean and normalize HTML content with optimized pattern matching
---@param content string Raw HTML content
---@return string Cleaned HTML content
function HtmlUtils.cleanHtmlContent(content)
    if not content or content == "" then
        return ""
    end

    local cleaned_content = content

    -- Use single pcall for all operations to reduce overhead
    local success = pcall(function()
        -- Pre-cache patterns table to avoid repeated table access
        local patterns = CLEANUP_PATTERNS
        local pattern_count = #patterns

        -- Apply all cleanup patterns efficiently
        for i = 1, pattern_count do
            cleaned_content = cleaned_content:gsub(patterns[i], "")
        end
    end)

    if not success then
        -- If cleaning fails, return original content (safer than empty string)
        return content
    end

    return cleaned_content
end

return HtmlUtils
