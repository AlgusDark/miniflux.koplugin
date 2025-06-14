--[[--
Navigation Utilities for Miniflux Browser

This utility module handles entry navigation operations, marking entries as read/unread,
file management, and integration with the file manager.

@module miniflux.browser.utils.navigation_utils
--]]--

---Navigation context for preserving filtering state between entry navigations
---@alias NavigationContext {
---    entries: MinifluxEntry[],           -- List of entries in current context
---    current_index: integer,             -- Index of current entry in the list
---    context_type: string,               -- Type of context: "unread", "starred", "history", "category", "feed", "search"
---    category_id?: integer,              -- Category ID if browsing a specific category
---    feed_id?: integer,                  -- Feed ID if browsing a specific feed
---    status?: string,                    -- Entry status filter: "unread", "read", "removed"
---    starred?: boolean,                  -- Whether showing only starred entries
---    search_query?: string,              -- Search query if this is a search context
---    order?: string,                     -- Sort order: "published_at", "created_at", "status"
---    direction?: string,                 -- Sort direction: "asc", "desc"
---    limit?: integer,                    -- Number of entries per page
---    offset?: integer,                   -- Offset for pagination
---}

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local NavigationUtils = {}

---Get API options for navigation, preserving original context filtering
---@param entry_info table Current entry information
---@param settings SettingsManager Settings manager instance
---@return ApiOptions Options for API calls with preserved context
function NavigationUtils.getNavigationApiOptions(entry_info, settings)
    -- First, try to get the navigation context to preserve original filtering
    local navigation_context = NavigationUtils.getCurrentNavigationContext(entry_info)
    
    if navigation_context then
        -- Build options from navigation context to preserve original filtering
        local options = {
            order = navigation_context.order or settings:getOrder(),
            direction = navigation_context.direction or settings:getDirection(),
        }
        
        -- Preserve the original context filtering
        if navigation_context.status then
            options.status = navigation_context.status
        elseif navigation_context.context_type == "unread" then
            -- If context type is unread, force unread status
            options.status = {"unread"}
        elseif navigation_context.starred then
            -- If this was a starred context, we'll handle it in the API call
            options.starred = true
        else
            -- Fall back to current settings for status
            local hide_read_entries = settings:getHideReadEntries()
            if hide_read_entries then
                options.status = {"unread"}
            else
                options.status = {"unread", "read"}
            end
        end
        
        -- Preserve category and feed filters if they exist
        if navigation_context.category_id then
            options.category_id = navigation_context.category_id
        end
        
        if navigation_context.feed_id then
            options.feed_id = navigation_context.feed_id
        end
        
        return options
    else
        -- No navigation context available, fall back to current settings
        local BrowserUtils = require("browser/utils/browser_utils")
        return BrowserUtils.getApiOptions(settings)
    end
end

---Navigate to the previous entry
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.navigateToPreviousEntry(entry_info)
    -- First try to use the stored navigation context
    local prev_entry_id = NavigationUtils.getPreviousEntryFromContext(entry_info)
    
    if prev_entry_id then
        -- Get the current navigation context (don't load from target entry)
        local current_context = NavigationUtils.getCurrentNavigationContext(entry_info)
        if current_context then
            -- Update context to point to the previous entry
            local updated_context = NavigationUtils.updateNavigationContextForEntry(current_context, prev_entry_id)
            
            -- Check if previous entry is already downloaded locally
            local prev_html_file = NavigationUtils.getLocalEntryPath(entry_info, prev_entry_id)
            if prev_html_file and lfs.attributes(prev_html_file, "mode") == "file" then
                -- Update the target entry's metadata with correct context
                NavigationUtils.updateEntryMetadataContext(entry_info, prev_entry_id, updated_context)
                
                local EntryUtils = require("browser/utils/entry_utils")
                EntryUtils.openEntryFile(prev_html_file, updated_context)
                return
            else
                -- Entry not downloaded locally, fetch it from server with updated context
                NavigationUtils.fetchAndShowEntryWithContext(prev_entry_id, updated_context)
                return
            end
        else
            -- Fall back to using stored context from entry_info
            NavigationUtils.fetchAndShowEntryWithContext(prev_entry_id, entry_info.navigation_context)
            return
        end
    end
    
    -- Fallback: if no context available, use direct API call
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
    
    -- Get filter options - use navigation context if available, otherwise fall back to settings
    local options = NavigationUtils.getNavigationApiOptions(entry_info, MinifluxSettings)
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
        NavigationUtils.downloadAndShowEntry(prev_entry)
    else
        -- Create more descriptive error message based on context
        local error_message = _("No previous entry available")
        local navigation_context = NavigationUtils.getCurrentNavigationContext(entry_info)
        if navigation_context and navigation_context.context_type == "unread" then
            error_message = _("No previous unread entry available")
        end
        
        UIManager:show(InfoMessage:new{
            text = error_message,
            timeout = 3,
        })
        end
end

---Navigate to the next entry
---@param entry_info table Current entry information
---@return nil
function NavigationUtils.navigateToNextEntry(entry_info)
    -- First try to use the stored navigation context
    local next_entry_id = NavigationUtils.getNextEntryFromContext(entry_info)
    
    if next_entry_id then
        -- Get the current navigation context (don't load from target entry)
        local current_context = NavigationUtils.getCurrentNavigationContext(entry_info)
        if current_context then
            -- Update context to point to the next entry
            local updated_context = NavigationUtils.updateNavigationContextForEntry(current_context, next_entry_id)
            
            -- Check if next entry is already downloaded locally
            local next_html_file = NavigationUtils.getLocalEntryPath(entry_info, next_entry_id)
            if next_html_file and lfs.attributes(next_html_file, "mode") == "file" then
                -- Update the target entry's metadata with correct context
                NavigationUtils.updateEntryMetadataContext(entry_info, next_entry_id, updated_context)
                
                local EntryUtils = require("browser/utils/entry_utils")
                EntryUtils.openEntryFile(next_html_file, updated_context)
                return
            else
                -- Entry not downloaded locally, fetch it from server with updated context
                NavigationUtils.fetchAndShowEntryWithContext(next_entry_id, updated_context)
                return
            end
        else
            -- Fall back to using stored context from entry_info
            NavigationUtils.fetchAndShowEntryWithContext(next_entry_id, entry_info.navigation_context)
            return
        end
    end
    
    -- Fallback: if no context available, use direct API call
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
    
    -- Get filter options - use navigation context if available, otherwise fall back to settings
    local options = NavigationUtils.getNavigationApiOptions(entry_info, MinifluxSettings)
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
        NavigationUtils.downloadAndShowEntry(next_entry)
    else
        -- Create more descriptive error message based on context
        local error_message = _("No next entry available")
        local navigation_context = NavigationUtils.getCurrentNavigationContext(entry_info)
        if navigation_context and navigation_context.context_type == "unread" then
            error_message = _("No next unread entry available")
        end
        
        UIManager:show(InfoMessage:new{
            text = error_message,
            timeout = 3,
        })
    end
end

---Get previous entry ID from navigation context
---@param entry_info table Current entry information
---@return integer|nil Previous entry ID
function NavigationUtils.getPreviousEntryFromContext(entry_info)
    -- First, try to load metadata from the current entry
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if metadata and metadata.navigation_context then
        local context = metadata.navigation_context
        local current_index = context.current_index
        
        if current_index and context.entries then
            local prev_entry = NavigationUtils.getPreviousEntryByDirection(context, current_index)
            if prev_entry and prev_entry.id then
                return prev_entry.id
            end
        end
    end
    
    -- Fallback: try from stored entry info
    if entry_info.navigation_context then
        local context = entry_info.navigation_context
        local current_index = context.current_index
        
        if current_index and context.entries then
            local prev_entry = NavigationUtils.getPreviousEntryByDirection(context, current_index)
            if prev_entry and prev_entry.id then
                return prev_entry.id
            end
        end
    end
    
    return nil
end

---Get next entry ID from navigation context
---@param entry_info table Current entry information
---@return integer|nil Next entry ID
function NavigationUtils.getNextEntryFromContext(entry_info)
    -- First, try to load metadata from the current entry
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if metadata and metadata.navigation_context then
        local context = metadata.navigation_context
        local current_index = context.current_index
        
        if current_index and context.entries then
            local next_entry = NavigationUtils.getNextEntryByDirection(context, current_index)
            if next_entry and next_entry.id then
                return next_entry.id
            end
        end
    end
    
    -- Fallback: try from stored entry info
    if entry_info.navigation_context then
        local context = entry_info.navigation_context
        local current_index = context.current_index
        
        if current_index and context.entries then
            local next_entry = NavigationUtils.getNextEntryByDirection(context, current_index)
            if next_entry and next_entry.id then
                return next_entry.id
            end
        end
    end
    
    return nil
end

---Get previous entry from context array (always go up visually)
---@param context NavigationContext Navigation context
---@param current_index integer Current entry index
---@return MinifluxEntry|nil Previous entry
function NavigationUtils.getPreviousEntryByDirection(context, current_index)
    -- Previous = go up visually in the list (regardless of sort direction)
    if current_index > 1 then
        return context.entries[current_index - 1]
    end
    return nil
end

---Get next entry from context array (always go down visually)
---@param context NavigationContext Navigation context
---@param current_index integer Current entry index
---@return MinifluxEntry|nil Next entry
function NavigationUtils.getNextEntryByDirection(context, current_index)
    -- Next = go down visually in the list (regardless of sort direction)
    if current_index < #context.entries then
        return context.entries[current_index + 1]
    end
    return nil
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

---Load navigation context for a specific entry
---@param entry_info table Current entry information
---@param target_entry_id integer|string Target entry ID
---@return NavigationContext|nil Navigation context for target entry
function NavigationUtils.loadNavigationContext(entry_info, target_entry_id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return nil
    end
    
    local target_entry_dir = miniflux_dir .. "/miniflux/" .. tostring(target_entry_id) .. "/"
    local metadata_file = target_entry_dir .. "metadata.lua"
    
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return nil
    end
    
    local success, metadata = pcall(dofile, metadata_file)
    if success and metadata and metadata.navigation_context then
        return metadata.navigation_context
    end
    
    return nil
end

---Get current navigation context from various sources
---@param entry_info table Current entry information
---@return NavigationContext|nil Current navigation context
function NavigationUtils.getCurrentNavigationContext(entry_info)
    -- First priority: navigation context stored in entry_info (most recent)
    if entry_info.navigation_context then
        return entry_info.navigation_context
    end
    
    -- Second priority: try to load from current entry's metadata
    local metadata = NavigationUtils.loadCurrentEntryMetadata(entry_info)
    if metadata and metadata.navigation_context then
        return metadata.navigation_context
    end
    
    return nil
end

---Update target entry's metadata with correct navigation context
---@param entry_info table Current entry information
---@param target_entry_id integer|string Target entry ID
---@param updated_context NavigationContext Updated navigation context
---@return boolean True if successfully updated
function NavigationUtils.updateEntryMetadataContext(entry_info, target_entry_id, updated_context)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return false
    end
    
    local target_entry_dir = miniflux_dir .. "/miniflux/" .. tostring(target_entry_id) .. "/"
    local metadata_file = target_entry_dir .. "metadata.lua"
    
    if lfs.attributes(metadata_file, "mode") ~= "file" then
        return false
    end
    
    -- Load existing metadata
    local success, metadata = pcall(dofile, metadata_file)
    if not success or not metadata then
        return false
    end
    
    -- Update the navigation context
    metadata.navigation_context = updated_context
    
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

---Get local path for an entry
---@param entry_info table Current entry information
---@param entry_id integer|string Entry ID
---@return string|nil Local file path
function NavigationUtils.getLocalEntryPath(entry_info, entry_id)
    local miniflux_dir = entry_info.file_path:match("(.*)/miniflux/")
    if not miniflux_dir then
        return nil
    end
    
    local entry_dir = miniflux_dir .. "/miniflux/" .. tostring(entry_id) .. "/"
    local html_file = entry_dir .. "entry.html"
    
    return html_file
end

---Fetch and show entry with navigation context
---@param entry_id integer Entry ID to fetch
---@param navigation_context NavigationContext Navigation context
---@return nil
function NavigationUtils.fetchAndShowEntryWithContext(entry_id, navigation_context)
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
        -- Update the navigation context with the new current index
        local updated_context = NavigationUtils.updateNavigationContextForEntry(navigation_context, entry_id)
        NavigationUtils.downloadAndShowEntryWithContext(result, updated_context)
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to fetch entry: ") .. tostring(result),
            timeout = 5,
        })
    end
end

---Update navigation context for a specific entry
---@param navigation_context NavigationContext Original context
---@param entry_id integer Entry ID to find in context
---@return NavigationContext Updated context
function NavigationUtils.updateNavigationContextForEntry(navigation_context, entry_id)
    if not navigation_context or not navigation_context.entries then
        return navigation_context
    end
    
    -- Find the entry in the context and update current_index
    for i, entry in ipairs(navigation_context.entries) do
        if entry.id == entry_id then
            local updated_context = {}
            for k, v in pairs(navigation_context) do
                updated_context[k] = v
            end
            updated_context.current_index = i
            return updated_context
        end
    end
    
    return navigation_context
end

---Download and show an entry with context
---@param entry MinifluxEntry Entry to download and show
---@param navigation_context NavigationContext Navigation context
---@return nil
function NavigationUtils.downloadAndShowEntryWithContext(entry, navigation_context)
    -- Create download directory
    local DataStorage = require("datastorage")
    local download_dir = ("%s/%s/"):format(DataStorage:getFullDataDir(), "miniflux")
    
    -- Download and show the entry with context
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
        navigation_context = navigation_context
    })
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
    
    EntryUtils.downloadEntry({
        entry = entry,
        api = api,
        download_dir = download_dir
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

return NavigationUtils 