--[[--
Navigation Service for Miniflux Entries

This service handles complex entry navigation logic including timestamp-based
previous/next navigation, API coordination, and context-aware filtering.

@module miniflux.services.navigation_service
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- Import dependencies
local NavigationContext = require("utils/navigation_context")
local MetadataLoader = require("utils/metadata_loader")
local TimeUtils = require("utils/time_utils")

-- Constants
local DIRECTION_PREVIOUS = "previous"
local DIRECTION_NEXT = "next"
local DIRECTION_ASC = "asc"
local DIRECTION_DESC = "desc"
local PUBLISHED_AFTER = "published_after"
local PUBLISHED_BEFORE = "published_before"
local MSG_FINDING_PREVIOUS = "Finding previous entry..."
local MSG_FINDING_NEXT = "Finding next entry..."

---@class NavigationService
---@field settings MinifluxSettings Settings instance
---@field api MinifluxAPI API client instance
local NavigationService = {}

---Create a new NavigationService instance
---@param dependencies table Dependencies containing settings and api
---@return NavigationService
function NavigationService:new(dependencies)
    local instance = {
        settings = dependencies.settings,
        api = dependencies.api,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- API OPTIONS BUILDING
-- =============================================================================

---Get API options based on settings for navigation
---@return table API options for entries
function NavigationService:getNavigationApiOptions()
    local options = {
        limit = self.settings.limit,
        order = self.settings.order,
        direction = self.settings.direction,
        status = self.settings.hide_read_entries and { "unread" } or { "unread", "read" },
    }
    return options
end

-- =============================================================================
-- HELPER METHODS
-- =============================================================================

---Validate navigation input parameters
---@param entry_info table Entry information with file_path and entry_id
---@return boolean success, string? error_message
function NavigationService:validateNavigationInput(entry_info)
    if not entry_info.entry_id then
        return false, _("Cannot navigate: missing entry ID")
    end

    if not self.api then
        return false, _("Cannot navigate: API not available")
    end

    local context_success, has_context = pcall(function()
        return NavigationContext.hasValidContext()
    end)

    if not context_success or not has_context then
        return false, _("Cannot navigate: no browsing context available")
    end

    return true
end

---Load and validate entry metadata
---@param entry_info table Entry information
---@return table? metadata, number? published_unix, string? error_message
function NavigationService:loadEntryMetadata(entry_info)
    local metadata = MetadataLoader.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        return nil, nil, _("Cannot navigate: missing timestamp information")
    end

    local published_unix
    local ok = pcall(function()
        published_unix = TimeUtils.iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        return nil, nil, _("Cannot navigate: invalid timestamp format")
    end

    return metadata, published_unix
end

---Build navigation options based on direction
---@param published_unix number Unix timestamp of current entry
---@param direction string Navigation direction ("previous" or "next")
---@return table? options, string? error_message
function NavigationService:buildNavigationOptions(published_unix, direction)
    local base_options = self:getNavigationApiOptions()
    local options_success, options = pcall(function()
        return NavigationContext.getContextAwareOptions(base_options)
    end)

    if not options_success or not options then
        return nil, _("Cannot navigate: failed to get context options")
    end

    if direction == DIRECTION_PREVIOUS then
        options.direction = DIRECTION_ASC
        options[PUBLISHED_AFTER] = published_unix
    elseif direction == DIRECTION_NEXT then
        options.direction = DIRECTION_DESC
        options[PUBLISHED_BEFORE] = published_unix
    else
        return nil, _("Invalid navigation direction")
    end

    options.limit = 1
    options.order = self.settings.order

    return options
end

---Try to open local file if it exists
---@param entry_info table Current entry information
---@param entry_data table Entry data from API
---@param entry_service EntryService Entry service instance
---@return boolean success True if local file was opened
function NavigationService:tryLocalFileFirst(entry_info, entry_data, entry_service)
    local entry_id = tostring(entry_data.id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")

    if miniflux_dir then
        local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
        local html_file = entry_dir .. "entry.html"

        if lfs.attributes(html_file, "mode") == "file" then
            entry_service:openEntryFile(html_file)
            return true
        end
    end

    return false
end

---Perform navigation search
---@param options table API options for search
---@param direction string Navigation direction for loading message
---@return boolean success, EntriesResponse|string result_or_error
function NavigationService:performNavigationSearch(options, direction)
    local loading_message = direction == DIRECTION_PREVIOUS and MSG_FINDING_PREVIOUS or MSG_FINDING_NEXT

    return self.api.entries:getEntries(options, {
        dialogs = {
            loading = { text = loading_message }
        }
    })
end

-- =============================================================================
-- NAVIGATION METHODS
-- =============================================================================

---Navigate to an entry in specified direction
---@param entry_info table Current entry information with file_path and entry_id
---@param options table Navigation options with direction
---@param entry_service EntryService Entry service instance
---@return nil
function NavigationService:navigateToEntry(entry_info, options, entry_service)
    local direction = options.direction

    -- Validate input
    local valid, error_msg = self:validateNavigationInput(entry_info)
    if not valid then
        UIManager:show(InfoMessage:new({
            text = error_msg,
            timeout = 3,
        }))
        return
    end

    -- Load metadata
    local metadata, published_unix, metadata_error = self:loadEntryMetadata(entry_info)
    if not metadata then
        UIManager:show(InfoMessage:new({
            text = metadata_error,
            timeout = 3,
        }))
        return
    end

    -- Build navigation options
    local nav_options, options_error = self:buildNavigationOptions(published_unix, direction)
    if not nav_options then
        UIManager:show(InfoMessage:new({
            text = options_error,
            timeout = 3,
        }))
        return
    end

    -- Perform search
    local success, result = self:performNavigationSearch(nav_options, direction)

    if success and result and result.entries and #result.entries > 0 then
        local target_entry = result.entries[1]

        -- Try local file first, fallback to reading entry
        if not self:tryLocalFileFirst(entry_info, target_entry, entry_service) then
            entry_service:readEntry(target_entry)
        end
    else
        local no_entry_msg = direction == DIRECTION_PREVIOUS
            and _("No previous entry available")
            or _("No next entry available")

        UIManager:show(InfoMessage:new({
            text = no_entry_msg,
            timeout = 3,
        }))
    end
end

return NavigationService
