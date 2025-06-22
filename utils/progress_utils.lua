--[[--
Progress Utilities for Miniflux Browser

This utility module provides progress tracking and user feedback for long-running operations,
particularly entry downloading with image processing.

@module miniflux.browser.utils.progress_utils
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local ProgressUtils = {}

---@class EntryDownloadProgress
---@field dialog InfoMessage|nil Progress dialog instance
---@field completion_dialog InfoMessage|nil Completion dialog instance
---@field title string Entry title being downloaded
---@field current_step string Current step description
---@field total_images number Total number of images found
---@field downloaded_images number Number of images successfully downloaded
---@field include_images boolean Whether images are being downloaded
local EntryDownloadProgress = {}

---Create a new progress tracker
---@param entry_title string Title of the entry being downloaded
---@return EntryDownloadProgress
function EntryDownloadProgress:new(entry_title)
    local obj = {
        title = entry_title,
        current_step = _("Preparing download…"),
        total_images = 0,
        downloaded_images = 0,
        include_images = true,
        dialog = nil,
        completion_dialog = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Update the progress dialog with current status
---@param step string Current step description
---@param image_progress? {current: number, total: number} Optional image progress
---@param can_cancel? boolean Whether the operation can be cancelled
---@return boolean True if user wants to continue, false to cancel
function EntryDownloadProgress:update(step, image_progress, can_cancel)
    self.current_step = step

    if image_progress then
        self.downloaded_images = image_progress.current
        self.total_images = image_progress.total
    end

    -- Build progress message
    local message_parts = {
        T(_("Downloading: %1"), self.title),
        "",
        self.current_step,
    }

    -- Add image progress if relevant
    if self.include_images and self.total_images > 0 then
        table.insert(message_parts, "")
        if image_progress then
            table.insert(message_parts, T(_("Images: %1 / %2 downloaded"), self.downloaded_images, self.total_images))
        else
            table.insert(message_parts, T(_("Images found: %1"), self.total_images))
        end
    elseif not self.include_images and self.total_images > 0 then
        table.insert(message_parts, "")
        table.insert(message_parts, T(_("Images: %1 found (skipped)"), self.total_images))
    end

    local message = table.concat(message_parts, "\n")

    -- Close previous dialog if exists
    if self.dialog then
        UIManager:close(self.dialog)
    end

    -- Create new progress dialog
    self.dialog = InfoMessage:new({
        text = message,
        timeout = can_cancel and 30 or nil, -- Allow longer timeout for cancellable operations
    })

    UIManager:show(self.dialog)
    UIManager:forceRePaint()

    -- For cancellable operations, check if user wants to continue
    if can_cancel then
        -- This is a simplified approach - in a real implementation,
        -- we might want to add proper cancel button support
        return true
    end

    return true
end

---Set image configuration
---@param include_images boolean Whether images will be downloaded
---@param total_images number Total number of images found
---@return nil
function EntryDownloadProgress:setImageConfig(include_images, total_images)
    self.include_images = include_images
    self.total_images = total_images
end

---Increment downloaded images counter
---@return nil
function EntryDownloadProgress:incrementDownloadedImages()
    self.downloaded_images = self.downloaded_images + 1
end

---Close the progress dialog
---@return nil
function EntryDownloadProgress:close()
    if self.dialog then
        UIManager:close(self.dialog)
        self.dialog = nil
    end
end

-- Export the class through the module
ProgressUtils.EntryDownloadProgress = EntryDownloadProgress

---Create a new entry download progress tracker
---@param entry_title string Title of the entry being downloaded
---@return EntryDownloadProgress
function ProgressUtils.createEntryProgress(entry_title)
    return EntryDownloadProgress:new(entry_title)
end

return ProgressUtils
