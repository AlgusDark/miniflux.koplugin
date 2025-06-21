--[[--
Entry Entity

This entity represents a Miniflux entry with its business logic and rules.
It encapsulates entry status management, validation, and file operations.

@module koplugin.miniflux.entities.entry
--]] --

local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

---@class Entry
---@field id number Entry ID
---@field title string Entry title
---@field url? string Entry URL
---@field status string Entry status ("read", "unread", "removed")
---@field published_at? string Publication timestamp
---@field content? string Entry content (HTML)
---@field summary? string Entry summary/excerpt
---@field feed? MinifluxFeed Feed information
local Entry = {}

---Create a new Entry instance
---@param data table Entry data from API
---@return Entry
function Entry:new(data)
    local instance = {
        id = data.id,
        title = data.title or _("Untitled Entry"),
        url = data.url,
        status = data.status or "unread",
        published_at = data.published_at,
        content = data.content,
        summary = data.summary,
        feed = data.feed
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- STATUS MANAGEMENT
-- =============================================================================

---Check if entry is read
---@return boolean
function Entry:isRead()
    return self.status == "read"
end

---Get the appropriate toggle button text for current status
---@return string Button text for marking entry
function Entry:getToggleButtonText()
    if self:isRead() then
        return _("✓ Mark as unread")
    else
        return _("✓ Mark as read")
    end
end

-- =============================================================================
-- VALIDATION
-- =============================================================================

---Check if entry has valid ID
---@return boolean
function Entry:hasValidId()
    return self.id and type(self.id) == "number" and self.id > 0
end

---Check if entry has content to display
---@return boolean
function Entry:hasContent()
    local content = self.content or self.summary or ""
    return content ~= ""
end

---Validate entry data for download
---@return boolean success, string? error_message
function Entry:validateForDownload()
    if not self:hasValidId() then
        return false, _("Invalid entry ID")
    end

    if not self:hasContent() then
        return false, _("No content available for this entry")
    end

    return true
end

-- =============================================================================
-- FILE PATH OPERATIONS
-- =============================================================================

---Get the local directory path for this entry
---@param download_dir string Base download directory
---@return string Entry directory path
function Entry:getLocalDirectory(download_dir)
    return download_dir .. tostring(self.id) .. "/"
end

---Get the local HTML file path for this entry
---@param download_dir string Base download directory
---@return string HTML file path
function Entry:getLocalHtmlPath(download_dir)
    return self:getLocalDirectory(download_dir) .. "entry.html"
end

---Get the local metadata file path for this entry
---@param download_dir string Base download directory
---@return string Metadata file path
function Entry:getLocalMetadataPath(download_dir)
    return self:getLocalDirectory(download_dir) .. "metadata.lua"
end

---Check if entry is already downloaded locally
---@param download_dir string Base download directory
---@return boolean
function Entry:isDownloaded(download_dir)
    local html_file = self:getLocalHtmlPath(download_dir)
    return lfs.attributes(html_file, "mode") == "file"
end

-- =============================================================================
-- METADATA OPERATIONS
-- =============================================================================

---Create metadata for this entry
---@param include_images boolean Whether images were included
---@param images_count number Number of images processed
---@return table Metadata table
function Entry:createMetadata(include_images, images_count)
    return {
        -- Entry identification
        id = self.id,
        title = self.title,
        url = self.url,

        -- Entry status and properties
        status = self.status,
        published_at = self.published_at,

        -- Image processing results
        images_included = include_images or false,
        images_count = images_count or 0
    }
end

return Entry
