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
    
    -- Get filter options from current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local base_options = BrowserUtils.getApiOptions(MinifluxSettings)
    
    -- Apply context-aware filtering (like Miniflux's EntryQueryBuilder)
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    local options = NavigationUtils.buildContextAwareOptions(base_options, metadata)
    options.limit = 1  -- We only want the immediate previous entry
    
    -- Get the correct API method based on sort direction  
    local direction = options.direction or MinifluxSettings:getDirection() or "desc"
    local api_method = NavigationUtils.getPreviousApiMethod(direction)
    
    -- Fetch previous entry using direction-aware API method
    local success, result = api[api_method](api, current_entry_id, options)
    
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
            global_options.limit = 1
            success, result = api[api_method](api, current_entry_id, global_options)
            
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
    
    -- Get filter options from current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local base_options = BrowserUtils.getApiOptions(MinifluxSettings)
    
    -- Apply context-aware filtering (like Miniflux's EntryQueryBuilder)
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    local options = NavigationUtils.buildContextAwareOptions(base_options, metadata)
    options.limit = 1  -- We only want the immediate next entry
    
    -- Get the correct API method based on sort direction
    local direction = options.direction or MinifluxSettings:getDirection() or "desc"
    local api_method = NavigationUtils.getNextApiMethod(direction)
    
    -- Fetch next entry using direction-aware API method
    local success, result = api[api_method](api, current_entry_id, options)
    
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
            global_options.limit = 1
            success, result = api[api_method](api, current_entry_id, global_options)
            
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

---Get API method for previous entry based on sort direction
---
--- Navigation Logic Explanation:
--- - "Previous" = go UP visually in the list (towards index 1)
--- - "Next" = go DOWN visually in the list (towards higher index)
---
--- Sort Direction Impact:
--- - DESC (newest first): previous=newer entry, next=older entry
--- - ASC (oldest first): previous=older entry, next=newer entry  
---
---@param direction string Sort direction ("asc" or "desc")
---@return string API method name ("getNextEntry" or "getPreviousEntry")
function NavigationUtils.getPreviousApiMethod(direction)
    if direction == "desc" then
        -- DESC: previous = go up = chronologically newer = use getNextEntry (after_entry_id)
        return "getNextEntry"
    else
        -- ASC: previous = go up = chronologically older = use getPreviousEntry (before_entry_id)
        return "getPreviousEntry"
    end
end

---Get API method for next entry based on sort direction
---@param direction string Sort direction ("asc" or "desc")
---@return string API method name ("getNextEntry" or "getPreviousEntry")
function NavigationUtils.getNextApiMethod(direction)
    if direction == "desc" then
        -- DESC: next = go down = chronologically older = use getPreviousEntry (before_entry_id)
        return "getPreviousEntry"
    else
        -- ASC: next = go down = chronologically newer = use getNextEntry (after_entry_id)
        return "getNextEntry"  
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