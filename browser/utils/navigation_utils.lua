--[[--
Navigation Utilities for Miniflux Browser

This utility module handles entry navigation operations, marking entries as read/unread,
file management, and integration with the file manager.

@module miniflux.browser.utils.navigation_utils
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local NavigationUtils = {}

--- Pure-Lua ISO-8601 → Unix timestamp (UTC)
-- Handles "YYYY-MM-DDTHH:MM:SS±HH:MM"
local function iso8601_to_unix(s)
    -- 1) Parse all the pieces in one go
    local Y, M, D, h, m, sec, sign, tzh, tzm = s:match(
      "(%d+)%-(%d+)%-(%d+)T"..
      "(%d+):(%d+):(%d+)"..
      "([%+%-])(%d%d):(%d%d)$"
    )
    if not Y then
      error("Bad ISO-8601 string: "..tostring(s))
    end
    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    tzh, tzm = tonumber(tzh), tonumber(tzm)
  
    -- 2) Convert date to days since Unix epoch via
    --    the "civil to days" algorithm (Howard Hinnant)
    local y = Y
    local mo = M
    if mo <= 2 then
      y = y - 1
      mo = mo + 12
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400                            -- [0, 399]
    local doy = math.floor((153 * (mo - 3) + 2) / 5) + D - 1  -- [0, 365]
    local doe = yoe * 365 + math.floor(yoe / 4)
              - math.floor(yoe / 100) + doy               -- [0, 146096]
    local days = era * 146097 + doe - 719468             -- days since 1970-01-01
  
    -- 3) Build a UTC-based seconds count
    local utc_secs = days * 86400 + h * 3600 + m * 60 + sec
  
    -- 4) Subtract the timezone offset to get back to UTC
    local offs = tzh * 3600 + tzm * 60
    if sign == "+" then
      utc_secs = utc_secs - offs
    else
      utc_secs = utc_secs + offs
    end
  
    return utc_secs
  end

---Navigate to the previous entry
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.navigateToPreviousEntry(entry_info)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        return
    end
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Finding previous entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Load current entry metadata to get published_at timestamp
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end
    
    -- Convert published_at to Unix timestamp
    local published_unix
    local ok, _ = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)
    
    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end
    
    -- Get filter options from current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local base_options = BrowserUtils.getApiOptions(MinifluxSettings)
    
    -- Apply context-aware filtering
    local options = NavigationUtils.buildContextAwareOptions(base_options, metadata)
    
    -- For Previous: direction=asc&published_after=${unix_timestamp}
    options.direction = "asc"
    options.published_after = published_unix
    options.limit = 1
    options.order = MinifluxSettings:getOrder()
    
    -- Fetch previous entry using regular getEntries API
    local success, result = api:getEntries(options)
    
    UIManager:close(loading_info)
    
    if success and result and result.entries and #result.entries > 0 then
        local prev_entry = result.entries[1]
        local prev_entry_id = tostring(prev_entry.id)
        
        -- Check if previous entry is already downloaded locally
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local prev_entry_dir = miniflux_dir .. "/miniflux/" .. prev_entry_id .. "/"
            local prev_html_file = prev_entry_dir .. "entry.html"
            
            if lfs.attributes(prev_html_file, "mode") == "file" then
                local EntryUtils = require("browser/utils/entry_utils")
                EntryUtils.openEntryFile(prev_html_file)
                return
            end
        end
        
        -- Entry not downloaded locally, download and show it
        NavigationUtils.downloadAndShowEntry(prev_entry, metadata)
    else
        -- If no previous entry found with browsing context, try global navigation
        if metadata and (metadata.browsing_feed_id or metadata.browsing_category_id) then
            -- Build global options (no feed/category filter for global search)
            local global_options = NavigationUtils.buildContextAwareOptions(base_options, nil)
            global_options.direction = "asc"
            global_options.published_after = published_unix
            global_options.limit = 1
            global_options.order = MinifluxSettings:getOrder()
            
            -- Global fallback for previous entry
            
            success, result = api:getEntries(global_options)
            
            if success and result and result.entries and #result.entries > 0 then
                local prev_entry = result.entries[1]
                NavigationUtils.downloadAndShowEntry(prev_entry, metadata)
                return
            end
        end
        
        UIManager:show(InfoMessage:new{
            text = _("No previous entry available"),
            timeout = 3,
        })
    end
end

---Navigate to the next entry
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.navigateToNextEntry(entry_info)
    local current_entry_id = entry_info.entry_id
    if not current_entry_id then
        return
    end
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Finding next entry..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Load current entry metadata to get published_at timestamp
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if not metadata or not metadata.published_at then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Cannot navigate: missing timestamp information"),
            timeout = 3,
        })
        return
    end
    
    -- Convert published_at to Unix timestamp
    local published_unix
    local ok, _ = pcall(function()
        published_unix = iso8601_to_unix(metadata.published_at)
    end)
    
    if not ok or not published_unix then
        UIManager:close(loading_info)
        UIManager:show(InfoMessage:new{
            text = _("Cannot navigate: invalid timestamp format"),
            timeout = 3,
        })
        return
    end
    
    -- Get filter options from current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local base_options = BrowserUtils.getApiOptions(MinifluxSettings)
    
    -- Apply context-aware filtering
    local options = NavigationUtils.buildContextAwareOptions(base_options, metadata)
    
    -- For Next: direction=desc&published_before=${unix_timestamp}
    options.direction = "desc"
    options.published_before = published_unix
    options.limit = 1
    options.order = MinifluxSettings:getOrder()
    
    -- Fetch next entry using regular getEntries API
    local success, result = api:getEntries(options)
    
    UIManager:close(loading_info)
    
    if success and result and result.entries and #result.entries > 0 then
        local next_entry = result.entries[1]
        local next_entry_id = tostring(next_entry.id)
        
        -- Check if next entry is already downloaded locally
        local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
        if miniflux_dir then
            local next_entry_dir = miniflux_dir .. "/miniflux/" .. next_entry_id .. "/"
            local next_html_file = next_entry_dir .. "entry.html"
            
            if lfs.attributes(next_html_file, "mode") == "file" then
                local EntryUtils = require("browser/utils/entry_utils")
                EntryUtils.openEntryFile(next_html_file)
                return
            end
        end
        
        -- Entry not downloaded locally, download and show it
        NavigationUtils.downloadAndShowEntry(next_entry, metadata)
    else
        -- If no next entry found with browsing context, try global navigation
        if metadata and (metadata.browsing_feed_id or metadata.browsing_category_id) then
            -- Build global options (no feed/category filter for global search)
            local global_options = NavigationUtils.buildContextAwareOptions(base_options, nil)
            global_options.direction = "desc"
            global_options.published_before = published_unix
            global_options.limit = 1
            global_options.order = MinifluxSettings:getOrder()
            
            -- Global fallback for next entry
            
            success, result = api:getEntries(global_options)
            
            if success and result and result.entries and #result.entries > 0 then
                local next_entry = result.entries[1]
                NavigationUtils.downloadAndShowEntry(next_entry, metadata)
                return
            end
        end
        
        UIManager:show(InfoMessage:new{
            text = _("No next entry available"),
            timeout = 3,
        })
    end
end

---Load current entry metadata
---@param entry_info table Current entry information
---@return table|nil Entry metadata
function NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if not entry_info.file_path or not entry_info.entry_id then
        return nil
    end
    
    local entry_dir = entry_info.file_path:match("(.*)/entry%.html$")
    if not entry_dir then
        return nil
    end
    
    local metadata_file = entry_dir .. "/metadata.lua"
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return nil
    end
    
    local success, metadata = pcall(dofile, metadata_file)
    if success and metadata then
        return metadata
    end
    
    return nil
end

---Download and show an entry
---@param entry MinifluxEntry Entry to download and show
---@param source_metadata? table Optional source entry metadata for context inheritance
---@return nil
function NavigationUtils.downloadAndShowEntry(entry, source_metadata)
    -- Create download directory
    local DataStorage = require("datastorage")
    local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
    
    -- Build context to pass to new entry (inherit from source)
    local context = nil
    if source_metadata then
        context = {}
        if source_metadata.browsing_feed_id then
            context.feed_id = source_metadata.browsing_feed_id
        elseif source_metadata.browsing_category_id then
            context.category_id = source_metadata.browsing_category_id
        end
        -- If no browsing context in source → context remains nil (global navigation)
    end
    
    -- Download and show the entry
    local EntryUtils = require("browser/utils/entry_utils")
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    EntryUtils.downloadEntry({
        entry = entry,
        api = api,
        download_dir = download_dir,
        context = context  -- Pass inherited browsing context
    })
end

---Mark an entry as read
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.markEntryAsRead(entry_info)
    local entry_id = entry_info.entry_id
    
    if not entry_id then
        return
    end
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Marking entry as read..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get API instance (we'll need to figure out how to access this)
    -- For now, we'll create a new instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Mark as read
    local success, result = api:markEntryAsRead(tonumber(entry_id))
    
    UIManager:close(loading_info)
    
    if success then
        UIManager:show(InfoMessage:new{
            text = _("Entry marked as read"),
            timeout = 2,
        })
        
        -- Update local metadata to reflect the new status
        NavigationUtils.updateLocalEntryStatus(entry_info, "read")
        
        -- Delete local entry and go to miniflux folder
        UIManager:scheduleIn(0.5, function()
            NavigationUtils.deleteLocalEntry(entry_info)
        end)
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to mark entry as read: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Mark an entry as unread
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.markEntryAsUnread(entry_info)
    local entry_id = entry_info.entry_id
    
    if not entry_id then
        return
    end
    
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Marking entry as unread..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Mark as unread
    local success, result = api:markEntryAsUnread(tonumber(entry_id))
    
    UIManager:close(loading_info)
    
    if success then
        UIManager:show(InfoMessage:new{
            text = _("Entry marked as unread"),
            timeout = 2,
        })
        
        -- Update local metadata to reflect the new status
        NavigationUtils.updateLocalEntryStatus(entry_info, "unread")
        
        -- Show success message but don't delete the entry since it's now unread
        UIManager:show(InfoMessage:new{
            text = _("Entry marked as unread. File kept locally."),
            timeout = 3,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to mark entry as unread: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Update local entry metadata status
---@param entry_info table Current entry information
---@param new_status string New status to set
---@return boolean True if successfully updated
function NavigationUtils.updateLocalEntryStatus(entry_info, new_status)
    local entry_id = entry_info.entry_id
    if not entry_id then
        return false
    end
    
    -- Extract miniflux directory from file path
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return false
    end
    
    local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
    local metadata_file = entry_dir .. "metadata.lua"
    
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return false
    end
    
    -- Load existing metadata
    local success, metadata = pcall(dofile, metadata_file)
    if not success or not metadata then
        return false
    end
    
    -- Update the status
    metadata.status = new_status
    
    -- Save the updated metadata
    local BrowserUtils = require("browser/utils/browser_utils")
    local metadata_content = "return " .. BrowserUtils.tableToString(metadata)
    
    local file = io.open(metadata_file, "w")
    if file then
        file:write(metadata_content)
        file:close()
        return true
    end
    
    return false
end

---Delete a local entry
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.deleteLocalEntry(entry_info)
    local entry_id = entry_info.entry_id
    
    if not entry_id then
        return
    end
    
    -- Extract miniflux directory from file path
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return
    end
    
    local entry_dir = miniflux_dir .. "/miniflux/" .. entry_id .. "/"
    
    -- Close the current document first
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end
    
    -- Delete the directory
    local FFIUtil = require("ffi/util")
    
    local success = pcall(function()
        FFIUtil.purgeDir(entry_dir)
    end)
    
    if success then
        UIManager:show(InfoMessage:new{
            text = _("Local entry deleted successfully"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to delete local entry"),
            timeout = 3,
        })
    end
    
    -- Go to miniflux folder
    NavigationUtils.openMinifluxFolder(entry_info)
end

---Open the Miniflux folder in file manager
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.openMinifluxFolder(entry_info)
    -- Extract miniflux directory from file path
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return
    end
    
    local full_miniflux_dir = miniflux_dir .. "/miniflux/"
    
    -- Close the current document first
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
    end
    
    -- Open file manager to miniflux folder
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:reinit(full_miniflux_dir)
    else
        FileManager:showFiles(full_miniflux_dir)
    end
end

---Fetch and show entry by ID
---@param entry_id number Entry ID to fetch and show
---@return nil
function NavigationUtils.fetchAndShowEntry(entry_id)
    -- Show loading message
    local loading_info = InfoMessage:new{
        text = _("Fetching entry from server..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint()
    
    -- Get API instance with stored settings
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()  -- Create and initialize instance
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    -- Fetch the entry by ID
    local success, result = api:getEntry(entry_id)
    
    UIManager:close(loading_info)
    
    if success and result then
        NavigationUtils.downloadAndShowEntry(result)
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to fetch entry: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Build context-aware API options (similar to Miniflux's EntryQueryBuilder)
---@param base_options ApiOptions Base API options from settings  
---@param metadata table|nil Entry metadata containing browsing context
---@return ApiOptions Context-aware options with WithFeedID/WithCategoryID equivalent
function NavigationUtils.buildContextAwareOptions(base_options, metadata)
    local options = {}
    
    -- Copy base options
    for k, v in pairs(base_options) do
        options[k] = v
    end
    
    -- Add context-aware filtering (like Miniflux's WithFeedID/WithCategoryID)
    if metadata then
        if metadata.browsing_feed_id then
            -- WithFeedID equivalent - filter by the feed the user was browsing
            options.feed_id = metadata.browsing_feed_id
        elseif metadata.browsing_category_id then
            -- WithCategoryID equivalent - filter by the category the user was browsing  
            options.category_id = metadata.browsing_category_id
        end
        -- No browsing context = global navigation (unread entries view)
    end
    
    return options
end

return NavigationUtils 