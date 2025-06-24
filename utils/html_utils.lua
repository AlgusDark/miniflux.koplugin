--[[--
HTML Utilities for Miniflux Browser

This utility module handles HTML document creation and processing for offline
viewing of RSS entries in KOReader.

@module miniflux.browser.utils.html_utils
--]]

local _ = require("gettext")

local HtmlUtils = {}

---Create a complete HTML document for an entry
---@param entry MinifluxEntry Entry data
---@param content string Processed HTML content
---@return string Complete HTML document
function HtmlUtils.createHtmlDocument(entry, content)
    local entry_title = entry.title or _("Untitled Entry")

    -- Build metadata sections
    local metadata_sections = {}

    -- Feed information
    if entry.feed and entry.feed.title then
        table.insert(metadata_sections, string.format("<p><strong>%s:</strong> %s</p>", _("Feed"), entry.feed.title))
    end

    -- Publication date
    if entry.published_at then
        table.insert(
            metadata_sections,
            string.format("<p><strong>%s:</strong> %s</p>", _("Published"), entry.published_at)
        )
    end

    -- Original URL
    if entry.url then
        table.insert(
            metadata_sections,
            string.format('<p><strong>%s:</strong> <a href="%s">%s</a></p>', _("URL"), entry.url, entry.url)
        )
    end

    local metadata_html = table.concat(metadata_sections, "\n        ")

    return string.format(
        [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        img {
            max-width: 100%%;
            height: auto;
            display: block;
            margin: 10px 0;
        }
        .entry-meta {
            border-bottom: 1px solid #ccc;
            padding-bottom: 10px;
            margin-bottom: 20px;
            color: #666;
        }
        .entry-content {
            text-align: justify;
        }
        .entry-content p {
            margin-bottom: 1em;
        }
        .entry-content h1, .entry-content h2, .entry-content h3 {
            margin-top: 0;
            margin-bottom: 0.5em;
        }
        .entry-content blockquote {
            margin: 1em 0;
            padding-left: 1em;
            border-left: 3px solid #ccc;
            font-style: italic;
        }
        .entry-content pre {
            background-color: #f5f5f5;
            padding: 10px;
            border-radius: 3px;
            overflow-x: auto;
        }
        .entry-content code {
            background-color: #f5f5f5;
            padding: 2px 4px;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>
        %s
    </div>
    <div class="entry-content">
        %s
    </div>
</body>
</html>]],
        HtmlUtils.escapeHtml(entry_title), -- Title in head
        HtmlUtils.escapeHtml(entry_title), -- Title in body
        metadata_html,
        content                            -- Content is already processed, don't escape it
    )
end

---Escape HTML special characters
---@param text string Text to escape
---@return string Escaped text
function HtmlUtils.escapeHtml(text)
    if not text then
        return ""
    end

    local escape_map = {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
    }

    return (text:gsub("[&<>\"']", escape_map))
end

---Clean and normalize HTML content
---@param content string Raw HTML content
---@return string Cleaned HTML content
function HtmlUtils.cleanHtmlContent(content)
    local cleaned_content = content

    -- Remove potentially problematic elements that don't work offline
    pcall(function()
        -- Remove script tags (security and functionality)
        cleaned_content = cleaned_content:gsub("<%s*script[^>]*>.-<%s*/%s*script%s*>", "")
        cleaned_content = cleaned_content:gsub("<%s*script[^>]*>", "")

        -- Remove iframe tags (won't work offline)
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>.-<%s*/%s*iframe%s*>", "")
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*/%s*>", "")
        cleaned_content = cleaned_content:gsub("<%s*iframe[^>]*>", "")

        -- Remove object and embed tags (multimedia that won't work offline)
        cleaned_content = cleaned_content:gsub("<%s*object[^>]*>.-<%s*/%s*object%s*>", "")
        cleaned_content = cleaned_content:gsub("<%s*embed[^>]*>", "")

        -- Remove form elements (won't work offline)
        cleaned_content = cleaned_content:gsub("<%s*form[^>]*>.-<%s*/%s*form%s*>", "")

        -- Remove style blocks that might interfere with our styling
        -- Note: We keep inline styles on elements, just remove style blocks
        cleaned_content = cleaned_content:gsub("<%s*style[^>]*>.-<%s*/%s*style%s*>", "")
    end)

    return cleaned_content
end

return HtmlUtils
