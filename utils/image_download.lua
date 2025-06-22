--[[--
Image Download Utilities

This utility module handles HTTP downloading of images for RSS entries.
Separated from image_utils.lua to improve organization and maintainability.

@module miniflux.utils.image_download
--]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")

local ImageDownload = {}

---Download a single image from URL
---@param url string Image URL to download
---@param entry_dir string Directory to save image in
---@param filename string Filename to save image as
---@return boolean True if download successful
function ImageDownload.downloadImage(url, entry_dir, filename)
    local filepath = entry_dir .. filename
    local response_body = {}

    -- Add robust timeout handling using socketutil
    local timeout, maxtime = 10, 30
    socketutil:set_timeout(timeout, maxtime)

    local result, status_code
    local network_success = pcall(function()
        result, status_code = http.request({
            url = url,
            sink = ltn12.sink.table(response_body),
        })
    end)

    socketutil:reset_timeout()

    if not network_success then
        return false
    end

    if not result then
        return false
    end

    if status_code == 200 then
        local content = table.concat(response_body)
        if content and #content > 0 then
            local file = io.open(filepath, "wb")
            if file then
                file:write(content)
                file:close()
                return true
            else
                return false
            end
        else
            return false
        end
    else
        return false
    end
end

return ImageDownload
