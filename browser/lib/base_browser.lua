--[[--
Base browser class for Miniflux browsers

@module koplugin.miniflux.browser.base_browser
--]]--

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")

---@class NavigationData
---@field paths_updated? boolean Whether navigation paths were updated
---@field current_type? string Current context type
---@field current_data? table Current context data
---@field page_info? table Page restoration information
---@field restore_page_info? table Page information for restoration
---@field is_settings_refresh? boolean Whether this is a settings refresh
---@field current_title? string Current title for navigation

---@class CurrentContext
---@field type string Context type (main, feeds, categories, feed_entries, category_entries, unread_entries)
---@field data? table Context-specific data

---@class BaseBrowser : Menu
---@field title_shrink_font_to_fit boolean Whether to shrink title font to fit
---@field is_popout boolean Whether this is a popout window
---@field covers_fullscreen boolean Whether browser covers full screen
---@field is_borderless boolean Whether browser is borderless
---@field title_bar_fm_style boolean Whether to use file manager style title bar
---@field title_bar_left_icon string Icon for left side of title bar
---@field perpage number Number of items per page
---@field title string Browser title
---@field subtitle string Browser subtitle
---@field item_table table[] Menu items
---@field settings SettingsManager Settings manager instance
---@field api MinifluxAPI API client instance  
---@field download_dir string Download directory path
---@field config_dialog ButtonDialogTitle|nil Current config dialog
---@field current_context CurrentContext Current browser context
---@field page_state_manager any Page state manager instance
---@field onLeftButtonTap function Callback for left button tap
---@field onReturn function|nil Callback for back navigation
local BaseBrowser = Menu:extend{
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
}

---Initialize the base browser
---@return nil
function BaseBrowser:init()
    -- Set up common properties
    self.title = self.title or _("Miniflux")
    self.subtitle = self.subtitle or ""
    self.item_table = self.item_table or {}
    
    -- Set up settings button callback to show config dialog
    self.onLeftButtonTap = function()
        self:showConfigDialog()
    end
    
    Menu.init(self)
end

---Show configuration dialog
---@return nil
function BaseBrowser:showConfigDialog()
    -- Get settings module - will be available through parent browser
    local settings = self.settings
    if not settings then
        self:showErrorMessage(_("Settings not available"))
        return
    end
    
    -- Check if settings has the required methods
    if not settings.getHideReadEntries or not settings.toggleHideReadEntries then
        self:showErrorMessage(_("Settings configuration error"))
        return
    end
    
    -- Only show the read/unread toggle if we're in an entries view AND not in unread entries view
    local is_entry_view = self:isInEntryView()
    local is_unread_entries_view = self.current_context and self.current_context.type == "unread_entries"
    
    local buttons = {}
    
    -- Show the toggle only for entry views that are NOT the unread entries view
    -- The unread entries view should always show only unread entries by design
    if is_entry_view and not is_unread_entries_view then
        local hide_read_entries = settings:getHideReadEntries()
        local eye_icon = hide_read_entries and "◯ " or "⊘ "
        local button_text = eye_icon .. (hide_read_entries and _("Show all entries") or _("Show only unread entries"))
        
        table.insert(buttons, {
            {
                text = button_text,
                callback = function()
                    local dialog_ref = self.config_dialog
                    UIManager:close(dialog_ref)
                    self:toggleReadEntriesVisibility()
                end,
            },
        })
    end
    
    -- Always show close button
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                local dialog_ref = self.config_dialog
                UIManager:close(dialog_ref)
            end,
        },
    })
    
    self.config_dialog = ButtonDialogTitle:new{
        title = _("Miniflux Settings"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.config_dialog)
end

---Toggle read entries visibility
---@return nil
function BaseBrowser:toggleReadEntriesVisibility()
    -- Get settings module
    local settings = self.settings
    if not settings then
        self:showErrorMessage(_("Settings not available"))
        return
    end
    
    -- Check if settings has the required methods
    if not settings.getHideReadEntries or not settings.toggleHideReadEntries then
        self:showErrorMessage(_("Settings configuration error"))
        return
    end
    
    local now_hidden = settings:toggleHideReadEntries()
    
    -- Show confirmation message
    local message = now_hidden and _("Now showing only unread entries") or _("Now showing all entries")
    self:showInfoMessage(message, 2)
    
    -- Notify about settings change to invalidate caches
    self:onSettingsChanged("hide_read_entries", now_hidden)
    
    -- Refresh current view safely - this is just local filtering, no API calls needed
    if self.refreshCurrentView then
        -- Use pcall to safely call refresh and catch any errors
        local success = pcall(function()
            self:refreshCurrentView()
        end)
        
        if not success then
            self:showErrorMessage(_("Error refreshing view"))
        end
    end
end

---Check if we're currently viewing entries (not main menu, feeds list, or categories list)
---@return boolean True if in entry view
function BaseBrowser:isInEntryView()
    if not self.title then
        return false
    end
    
    -- Check if we're in an entry view by looking at the title
    -- Entry views typically have titles like "Feed Name" or "Category Name" or "Unread Entries"
    -- Main views have titles like "Miniflux", "Feeds", "Categories"
    local main_titles = {
        [_("Miniflux")] = true,
        [_("Feeds")] = true,
        [_("Categories")] = true
    }
    
    return not main_titles[self.title]
end

---Check if hiding read entries would result in no entries
---@return boolean True if hiding would result in no entries
function BaseBrowser:willHideResultInNoEntries()
    -- Look at current items to see if they're all read entries
    if not self.item_table or #self.item_table == 0 then
        return true
    end
    
    -- Count unread entries in current view
    local unread_count = 0
    for _, item in ipairs(self.item_table) do
        if item.entry_data and item.entry_data.status == "unread" then
            unread_count = unread_count + 1
        end
    end
    
    return unread_count == 0
end

---Method to notify about settings changes - can be overridden by subclasses
---@param setting_name string Name of the setting that changed
---@param new_value any New value of the setting
---@return nil
function BaseBrowser:onSettingsChanged(setting_name, new_value)
    -- Default implementation - subclasses can override for specific behavior
    if setting_name == "hide_read_entries" then
        -- Invalidate any cached data that depends on read/unread status
        if self.invalidateEntryCaches then
            self:invalidateEntryCaches()
        end
    end
end

---Method to invalidate entry-related caches - can be overridden by subclasses
---@return nil
function BaseBrowser:invalidateEntryCaches()
    -- Should be implemented by subclasses
end

---Refresh current view - should be overridden by subclasses
---@return nil
function BaseBrowser:refreshCurrentView()
    -- This method should be overridden by subclasses to refresh their specific content
end

---Close all browsers (single instance pattern)
---@return nil
function BaseBrowser:closeAll()
    -- Close this browser (single instance pattern like OPDS)
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
end

---Update browser with new content
---@param title string New browser title
---@param items table[] New menu items
---@param subtitle? string New browser subtitle
---@param navigation_data? NavigationData Navigation context data
---@return nil
function BaseBrowser:updateBrowser(title, items, subtitle, navigation_data)
    -- Update the current browser with new content (like OPDS updateCatalog)
    
    -- Determine if this is forward navigation or back navigation
    local is_back_navigation = navigation_data and navigation_data.paths_updated == true
    local is_settings_refresh = navigation_data and navigation_data.is_settings_refresh == true
    local select_number = nil
    
    if is_settings_refresh then
        -- For settings refresh, reset to page 1 but maintain navigation paths
        self.page = 1
        self.selected = {1}  -- Reset selection to first item
        self.itemnumber = 1  -- Reset item number
        select_number = 1
    elseif is_back_navigation then
        -- Check if we need to restore page info from navigation_data
        if navigation_data and navigation_data.restore_page_info then
            local target_page = navigation_data.restore_page_info.page
            if target_page and type(target_page) == "number" and target_page >= 1 then
                -- Calculate the select_number that would put us on the target page
                local perpage = self.perpage or 14 -- Default perpage if not set
                select_number = (target_page - 1) * perpage + 1
                
                -- Ensure select_number is within bounds
                if select_number > #items then
                    select_number = #items > 0 and #items or 1
                end
            end
        end
    else
        -- For forward navigation, reset Menu state to start fresh
        self.page = 1
        self.selected = {1}  -- Reset selection to first item
        self.itemnumber = 1  -- Reset item number
        select_number = 1
    end
    
    -- Simply update the current browser with new content
    self.title = title
    self.subtitle = subtitle or ""
    
    -- Update the browser content with title and subtitle
    self:switchItemTable(title, items, select_number, nil, subtitle)
end

---Show main content - to be implemented by subclasses
---@return nil
function BaseBrowser:showMainContent()
    -- To be implemented by subclasses
end

---Show feeds content - to be implemented by subclasses
---@return nil
function BaseBrowser:showFeedsContent()
    -- To be implemented by subclasses  
end

---Show categories content - to be implemented by subclasses
---@return nil
function BaseBrowser:showCategoriesContent()
    -- To be implemented by subclasses
end

---Show entries for a specific feed - to be implemented by subclasses
---@param feed_id number Feed ID
---@param feed_title string Feed title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function BaseBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    -- To be implemented by subclasses
end

---Show entries for a specific category - to be implemented by subclasses
---@param category_id number Category ID
---@param category_title string Category title
---@param paths_updated? boolean Whether navigation paths were updated
---@return nil
function BaseBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    -- To be implemented by subclasses
end

---Show loading message
---@param text? string Loading message text
---@return InfoMessage Loading message widget
function BaseBrowser:showLoadingMessage(text)
    local loading_info = InfoMessage:new{
        text = text or _("Loading..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint() -- Force immediate display before API call blocks
    return loading_info
end

---Close loading message
---@param loading_info InfoMessage Loading message widget to close
---@return nil
function BaseBrowser:closeLoadingMessage(loading_info)
    if loading_info then
        UIManager:close(loading_info)
    end
end

---Show error message
---@param message string Error message text
---@param timeout? number Message timeout in seconds
---@return nil
function BaseBrowser:showErrorMessage(message, timeout)
    UIManager:show(InfoMessage:new{
        text = message,
        timeout = timeout or 5,
    })
end

---Show info message
---@param message string Info message text
---@param timeout? number Message timeout in seconds
---@return nil
function BaseBrowser:showInfoMessage(message, timeout)
    UIManager:show(InfoMessage:new{
        text = message,
        timeout = timeout or 3,
    })
end

---Handle API errors with user feedback
---@param success boolean API call success status
---@param result any API result or error message
---@param error_prefix? string Prefix for error messages
---@return boolean True if successful, false if error was handled
function BaseBrowser:handleApiError(success, result, error_prefix)
    if not success then
        self:showErrorMessage((error_prefix or _("API Error")) .. ": " .. tostring(result))
        return false
    end
    return true
end

---Validate data and show message if invalid
---@param data any Data to validate
---@param data_name? string Name of data for error message
---@return boolean True if data is valid
function BaseBrowser:validateData(data, data_name)
    if not data or (type(data) == "table" and #data == 0) then
        self:showInfoMessage(_("No ") .. (data_name or "data") .. _(" found"))
        return false
    end
    return true
end

---Show entries list (base implementation for all browsers)
---@param entries table[] List of entries or message items
---@param title_prefix string Screen title
---@param is_category? boolean Whether this is a category view
---@param navigation_data? table Navigation context data
---@return nil
function BaseBrowser:showEntriesList(entries, title_prefix, is_category, navigation_data)
    local menu_items = {}
    local has_no_entries_message = false
    
    for i, entry in ipairs(entries) do
        -- Check if this is a special non-entry item (like "no entries" message)
        if entry.action_type == "no_action" then
            local menu_item = {
                text = entry.text,
                mandatory = entry.mandatory or "",
                action_type = entry.action_type,
            }
            table.insert(menu_items, menu_item)
            has_no_entries_message = true
        else
            -- This is a regular entry, process it normally
            local entry_title = entry.title or _("Untitled Entry")
            local feed_title = entry.feed and entry.feed.title or _("Unknown Feed")
            
            -- Add read/unread status indicator
            local status_indicator = ""
            if entry.status == "read" then
                status_indicator = "○ "  -- Open circle for read entries
            else
                status_indicator = "● "  -- Filled circle for unread entries
            end
            
            local display_text = status_indicator .. entry_title
            if is_category then
                display_text = status_indicator .. entry_title .. " (" .. feed_title .. ")"
            end
            
            local menu_item = {
                text = display_text,
                entry_data = entry,
                action_type = "read_entry",
            }
            
            table.insert(menu_items, menu_item)
        end
    end
    
    if #menu_items == 0 then
        menu_items = {{
            text = _("No entries found"),
            action_type = "none",
        }}
    end
    
    -- Build subtitle with appropriate icon and count
    local hide_read_entries = self.settings and self.settings:getHideReadEntries()
    local eye_icon = hide_read_entries and "⊘ " or "◯ "
    local subtitle = eye_icon .. #entries .. _(" entries")
    
    self:updateBrowser(title_prefix, menu_items, subtitle, navigation_data)
end

return BaseBrowser 