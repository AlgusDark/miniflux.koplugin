--[[--
Navigation Service for Miniflux Entries

This service handles complex entry navigation logic including timestamp-based
previous/next navigation, API coordination, and context-aware filtering.

@module miniflux.services.navigation_service
--]] --

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- Import dependencies
local MinifluxAPI = require("api/api_client")
local NavigationContext = require("utils/navigation_context")
local MetadataLoader = require("utils/metadata_loader")

---@class NavigationService
---@field settings MinifluxSettings Settings instance
local NavigationService = {}

---Create a new NavigationService instance
---@param settings MinifluxSettings Settings instance
---@return NavigationService
function NavigationService:new(settings)
    local instance = {
        settings = settings
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- =============================================================================
-- TIMESTAMP UTILITIES
-- =============================================================================

-- ISO-8601 to Unix timestamp conversion
local function iso8601_to_unix(s)
    local Y, M, D, h, m, sec, sign, tzh, tzm = s:match(
        "(%d+)%-(%d+)%-(%d+)T" ..
        "(%d+):(%d+):(%d+)" ..
        "([%+%-])(%d%d):(%d%d)$"
    )
    if not Y then
        error("Bad ISO-8601 string: " .. tostring(s))
    end
    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    tzh, tzm = tonumber(tzh), tonumber(tzm)

    local y = Y
    local mo = M
    if mo <= 2 then
        y = y - 1
        mo = mo + 12
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (mo - 3) + 2) / 5) + D - 1
    local doe = yoe * 365 + math.floor(yoe / 4)
        - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468

    local utc_secs = days * 86400 + h * 3600 + m * 60 + sec

    local offs = tzh * 3600 + tzm * 60
    if sign == "+" then
        utc_secs = utc_secs - offs
    else
        utc_secs = utc_secs + offs
    end

    return utc_secs
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
        status = self.settings.hide_read_entries and { "unread" } or { "unread", "read" }
    }
    return options
end

-- =============================================================================
-- NAVIGATION METHODS
-- =============================================================================

---Navigate to the previous entry
---@param entry_info table Current entry information with file_path and entry_id
---@param entry_service table EntryService instance for callbacks
---@return nil
function NavigationService:navigateToPreviousEntry(entry_info, entry_service)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: API not available"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Finding previous entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local context_success, has_context = pcall(function()
        return NavigationContext.hasValidContext()
    end)

    if not context_success or not has_context then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: no browsing context available"),
            timeout = 3,
        })
        return
    end

    local metadata = MetadataLoader.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end

    local published_unix
    local ok = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end

    local base_options = self:getNavigationApiOptions()
    local options_success, options = pcall(function()
        return NavigationContext.getContextAwareOptions(base_options)
    end)

    if not options_success or not options then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: failed to get context options"),
            timeout = 3,
        })
        return
    end

    options.direction = "asc"
    options.published_after = published_unix
    options.limit = 1
    options.order = self.settings.order

    local success, result = api.entries:getEntries(options)
    UIManager:close(loading_info)

    if success and result and result.entries and #result.entries > 0 then
        local prev_entry = result.entries[1]
        local prev_entry_id = tostring(prev_entry.id)

        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local prev_entry_dir = miniflux_dir .. "/miniflux/" .. prev_entry_id .. "/"
            local prev_html_file = prev_entry_dir .. "entry.html"

            if lfs.attributes(prev_html_file, "mode") == "file" then
                entry_service:openEntryFile(prev_html_file)
                return
            end
        end

        self:downloadAndShowEntry(prev_entry, entry_service)
    else
        local current_context_success, current_context = pcall(function()
            return NavigationContext.getCurrentContext()
        end)

        if current_context_success and current_context and current_context.type and current_context.type ~= "global" then
            local global_options = self:getNavigationApiOptions()
            global_options.direction = "asc"
            global_options.published_after = published_unix
            global_options.limit = 1
            global_options.order = self.settings.order

            success, result = api.entries:getEntries(global_options)

            if success and result and result.entries and #result.entries > 0 then
                local prev_entry = result.entries[1]
                self:downloadAndShowEntry(prev_entry, entry_service)
                return
            end
        end

        UIManager:show(InfoMessage:new {
            text = _("No previous entry available"),
            timeout = 3,
        })
    end
end

---Navigate to the next entry
---@param entry_info table Current entry information with file_path and entry_id
---@param entry_service table EntryService instance for callbacks
---@return nil
function NavigationService:navigateToNextEntry(entry_info, entry_service)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing entry ID"),
            timeout = 3,
        })
        return
    end

    local api_success, api = pcall(function()
        return MinifluxAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token
        })
    end)

    if not api_success or not api then
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: API not available"),
            timeout = 3,
        })
        return
    end

    local loading_info = InfoMessage:new {
        text = _("Finding next entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()

    local context_success, has_context = pcall(function()
        return NavigationContext.hasValidContext()
    end)

    if not context_success or not has_context then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: no browsing context available"),
            timeout = 3,
        })
        return
    end

    local metadata = MetadataLoader.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end

    local published_unix
    local ok = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)

    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end

    local base_options = self:getNavigationApiOptions()
    local options_success, options = pcall(function()
        return NavigationContext.getContextAwareOptions(base_options)
    end)

    if not options_success or not options then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new {
            text = _("Cannot navigate: failed to get context options"),
            timeout = 3,
        })
        return
    end

    options.direction = "desc"
    options.published_before = published_unix
    options.limit = 1
    options.order = self.settings.order

    local success, result = api.entries:getEntries(options)
    UIManager:close(loading_info)

    if success and result and result.entries and #result.entries > 0 then
        local next_entry = result.entries[1]
        local next_entry_id = tostring(next_entry.id)

        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local next_entry_dir = miniflux_dir .. "/miniflux/" .. next_entry_id .. "/"
            local next_html_file = next_entry_dir .. "entry.html"

            if lfs.attributes(next_html_file, "mode") == "file" then
                entry_service:openEntryFile(next_html_file)
                return
            end
        end

        self:downloadAndShowEntry(next_entry, entry_service)
    else
        local current_context_success, current_context = pcall(function()
            return NavigationContext.getCurrentContext()
        end)

        if current_context_success and current_context and current_context.type and current_context.type ~= "global" then
            local global_options = self:getNavigationApiOptions()
            global_options.direction = "desc"
            global_options.published_before = published_unix
            global_options.limit = 1
            global_options.order = self.settings.order

            success, result = api.entries:getEntries(global_options)

            if success and result and result.entries and #result.entries > 0 then
                local next_entry = result.entries[1]
                self:downloadAndShowEntry(next_entry, entry_service)
                return
            end
        end

        UIManager:show(InfoMessage:new {
            text = _("No next entry available"),
            timeout = 3,
        })
    end
end

-- =============================================================================
-- HELPER METHODS
-- =============================================================================

---Download and show an entry (delegates to EntryService)
---@param entry MinifluxEntry Entry to download and show
---@param entry_service table EntryService instance for delegation
---@return nil
function NavigationService:downloadAndShowEntry(entry, entry_service)
    -- Delegate back to EntryService
    entry_service:downloadAndShowEntry(entry)
end

return NavigationService
