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
    -- Get current entry ID
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
    
    -- Get filter options based on current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local options = BrowserUtils.getApiOptions(MinifluxSettings)
    options.limit = 1  -- We only want the immediate previous entry
    
    -- Fetch previous entry using before_entry_id
    local success, result = api:getPreviousEntry(current_entry_id, options)
    
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
        NavigationUtils.downloadAndShowEntry(prev_entry)
    else
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
    -- Get current entry ID
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
    
    -- Get filter options based on current settings
    local BrowserUtils = require("browser/utils/browser_utils")
    local options = BrowserUtils.getApiOptions(MinifluxSettings)
    options.limit = 1  -- We only want the immediate next entry
    
    -- Fetch next entry using after_entry_id
    local success, result = api:getNextEntry(current_entry_id, options)
    
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
        NavigationUtils.downloadAndShowEntry(next_entry)
    else
        UIManager:show(InfoMessage:new{
            text = _("No next entry available"),
            timeout = 3,
        })
    end
end

---Download and show an entry
---@param entry MinifluxEntry Entry to download and show
---@return nil
function NavigationUtils.downloadAndShowEntry(entry)
    -- Create download directory
    local DataStorage = require("datastorage")
    local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
    
    -- Download and show the entry
    local EntryUtils = require("browser/utils/entry_utils")
    local MinifluxAPI = require("api/api_client")
    local MinifluxSettingsManager = require("settings/settings_manager")
    local MinifluxSettings = MinifluxSettingsManager
    MinifluxSettings:init()
    
    local api = MinifluxAPI:new()
    api:init(MinifluxSettings:getServerAddress(), MinifluxSettings:getApiToken())
    
    EntryUtils.downloadEntry(entry, api, download_dir, nil)
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

return NavigationUtils 