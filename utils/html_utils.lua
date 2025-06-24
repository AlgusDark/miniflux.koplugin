--[[--
HTML Utilities for Miniflux Browser

This utility module handles HTML document creation and processing for offline
viewing of RSS entries in KOReader.

@module miniflux.browser.utils.html_utils
--]]

local _ = require("gettext")

local HtmlUtils = {}

---Get the CSS content for embedding
---@return string CSS content (empty string if file cannot be read)
function HtmlUtils.getCssContent()
    -- Get the plugin directory path
    local plugin_dir = debug.getinfo(1, "S").source:match("@(.*/)") or ""
    plugin_dir = plugin_dir:gsub("/utils/$", "")
    local css_path = plugin_dir .. "/assets/reader.css"

    -- Read CSS file content following KOReader's pattern
    local css_content = ""
    local f = io.open(css_path, "r")
    if f then
        css_content = f:read("*all")
        f:close()
        -- Trim whitespace (basic trim implementation)
        css_content = css_content:match("^%s*(.-)%s*$") or ""
    end

    return css_content
end

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
    local css_content = HtmlUtils.getCssContent()

    return string.format(
        [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style type="text/css">
%s
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
        css_content,                       -- CSS content embedded directly
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
