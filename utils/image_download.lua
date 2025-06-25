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
---@param config {url: string, entry_dir: string, filename: string} Configuration table
---@return boolean True if download successful
function ImageDownload.downloadImage(config)
    -- Combined validation with early returns
    if not config or type(config) ~= "table" or
        not config.url or not config.entry_dir or not config.filename then
        return false
    end

    local filepath = config.entry_dir .. config.filename
    local temp_filepath = filepath .. ".tmp"

    -- Helper function for robust cleanup
    local function cleanup_temp_file()
        pcall(function()
            os.remove(temp_filepath)
        end)
    end

    -- Helper function for comprehensive file validation
    local function validate_downloaded_file(expected_size)
        local file_size = 0
        local file_accessible = false

        local validation_success = pcall(function()
            local file_attr = io.open(temp_filepath, "rb")
            if file_attr then
                file_accessible = true
                file_attr:seek("end")
                file_size = file_attr:seek()
                file_attr:close()
            end
        end)

        local size_valid = file_size > 0

        -- If we have expected size from Content-Length, verify it matches
        if expected_size and expected_size > 0 then
            size_valid = size_valid and (file_size == expected_size)
        end

        return validation_success and file_accessible and size_valid, file_size
    end

    -- Helper function for basic content-type validation
    local function is_valid_content_type(content_type)
        if not content_type then
            return true -- Allow if no content-type header (common for images)
        end

        local content_type_lower = content_type:lower()
        local valid_types = {
            "image/jpeg", "image/jpg", "image/png", "image/gif",
            "image/webp", "image/svg+xml", "image/svg"
        }

        for _, valid_type in ipairs(valid_types) do
            if content_type_lower:find(valid_type, 1, true) then
                return true
            end
        end

        -- Allow generic image types and octet-stream (common fallback)
        return content_type_lower:find("image/", 1, true) or
            content_type_lower:find("application/octet-stream", 1, true)
    end

    -- Set timeout for network operations with error handling
    local timeout, maxtime = 10, 30
    local timeout_success = pcall(function()
        socketutil:set_timeout(timeout, maxtime)
    end)

    if not timeout_success then
        return false
    end

    -- Perform HTTP request with comprehensive error detection and header capture
    local result, status_code, response_headers
    local network_success = pcall(function()
        result, status_code, response_headers = http.request({
            url = config.url,
            sink = ltn12.sink.file(io.open(temp_filepath, "wb")),
        })
    end)

    -- Always reset timeout, even on failure
    pcall(function()
        socketutil:reset_timeout()
    end)

    -- Handle network/connection failures
    if not network_success then
        cleanup_temp_file()
        return false
    end

    -- Handle HTTP library failures (connection issues, DNS failures, etc.)
    if not result then
        cleanup_temp_file()
        return false
    end

    -- Handle HTTP status errors (404, 403, 500, etc.)
    if not status_code or status_code ~= 200 then
        cleanup_temp_file()
        return false
    end

    -- Extract and validate response headers
    local expected_content_length = nil
    local content_type = nil

    if response_headers and type(response_headers) == "table" then
        -- Extract Content-Length (case-insensitive)
        for key, value in pairs(response_headers) do
            local key_lower = key:lower()
            if key_lower == "content-length" then
                expected_content_length = tonumber(value)
            elseif key_lower == "content-type" then
                content_type = value
            end
        end
    end

    -- Validate content-type if available
    if not is_valid_content_type(content_type) then
        cleanup_temp_file()
        return false
    end

    -- Comprehensive file validation with content-length verification
    local file_valid, actual_file_size = validate_downloaded_file(expected_content_length)
    if not file_valid then
        cleanup_temp_file()
        return false
    end

    -- Additional sanity checks for image files
    local sanity_check_passed = true

    -- Check minimum file size (avoid empty or tiny non-image files)
    if actual_file_size < 10 then
        sanity_check_passed = false
    end

    -- Check maximum reasonable size (avoid downloading huge non-image files)
    -- 50MB limit for safety on low-powered devices
    if actual_file_size > 50 * 1024 * 1024 then
        sanity_check_passed = false
    end

    if not sanity_check_passed then
        cleanup_temp_file()
        return false
    end

    -- Atomic rename with enhanced error handling
    local rename_success = false
    local rename_error = pcall(function()
        -- Pre-cleanup: remove target file if it exists
        pcall(function() os.remove(filepath) end)

        -- Atomic rename operation
        local rename_result = os.rename(temp_filepath, filepath)
        rename_success = (rename_result == true) or (rename_result == nil)
    end)

    -- Handle rename operation failures
    if not rename_error or not rename_success then
        cleanup_temp_file()
        return false
    end

    -- Final verification: ensure target file exists and is accessible
    local final_verification = pcall(function()
        local verify_file = io.open(filepath, "rb")
        if verify_file then
            verify_file:close()
            return true
        end
        return false
    end)

    if not final_verification then
        -- Clean up both files if final verification fails
        cleanup_temp_file()
        pcall(function() os.remove(filepath) end)
        return false
    end

    return true
end

return ImageDownload
