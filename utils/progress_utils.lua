--[[--
Progress Utilities for Miniflux Browser

Simple progress tracking for entry downloading with image processing.

@module miniflux.browser.utils.progress_utils
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local ProgressUtils = {}

---Create a simple progress tracker for entry downloads
---@param entry_title string Title of the entry being downloaded
---@return table Simple progress tracker with update/close methods
function ProgressUtils.createEntryProgress(entry_title)
    local progress = {
        title = entry_title,
        current_dialog = nil,
        downloaded_images = 0,
        total_images = 0,
        include_images = true,
    }

    -- Simple update method that handles all progress scenarios
    function progress:update(step, image_progress, can_cancel)
        if image_progress then
            self.downloaded_images = image_progress.current
            self.total_images = image_progress.total
        end

        -- Build progress message
        local message_parts = { T(_("Downloading: %1"), self.title), "", step }

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

        -- Close previous dialog and show new one
        if self.current_dialog then
            UIManager:close(self.current_dialog)
        end

        self.current_dialog = InfoMessage:new({
            text = table.concat(message_parts, "\n"),
            timeout = can_cancel and 30 or nil,
        })

        UIManager:show(self.current_dialog)
        UIManager:forceRePaint()

        return true -- Always continue (simplified cancellation)
    end

    -- Set image configuration
    function progress:setImageConfig(include_images, total_images)
        self.include_images = include_images
        self.total_images = total_images
    end

    -- Increment downloaded images counter
    function progress:incrementDownloadedImages()
        self.downloaded_images = self.downloaded_images + 1
    end

    -- Close progress dialog
    function progress:close()
        if self.current_dialog then
            UIManager:close(self.current_dialog)
            self.current_dialog = nil
        end
    end

    return progress
end

return ProgressUtils
