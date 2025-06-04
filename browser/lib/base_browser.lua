--[[--
Base browser class for Miniflux browsers

@module koplugin.miniflux.browser.base_browser
--]]--

local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local _ = require("gettext")

local BaseBrowser = Menu:extend{
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
}

function BaseBrowser:init()
    -- Set up common properties
    self.title = self.title or _("Miniflux")
    self.subtitle = self.subtitle or ""
    self.item_table = self.item_table or {}
    
    -- Set up settings button callback to show config dialog
    self.onLeftButtonTap = function()
        if self.debug then 
            self.debug:info("Settings button tapped - showing config dialog") 
        end
        self:showConfigDialog()
    end
    
    Menu.init(self)
end

function BaseBrowser:showConfigDialog()
    -- Get settings module - will be available through parent browser
    local settings = self.settings
    if not settings then
        if self.debug then
            self.debug:info("Settings not available in showConfigDialog")
        end
        self:showErrorMessage(_("Settings not available"))
        return
    end
    
    -- Check if settings has the required methods
    if not settings.getHideReadEntries or not settings.toggleHideReadEntries then
        if self.debug then
            self.debug:info("Settings object missing required methods")
        end
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

function BaseBrowser:toggleReadEntriesVisibility()
    -- Get settings module
    local settings = self.settings
    if not settings then
        if self.debug then
            self.debug:info("Settings not available in toggleReadEntriesVisibility")
        end
        self:showErrorMessage(_("Settings not available"))
        return
    end
    
    -- Check if settings has the required methods
    if not settings.getHideReadEntries or not settings.toggleHideReadEntries then
        if self.debug then
            self.debug:info("Settings object missing required methods")
        end
        self:showErrorMessage(_("Settings configuration error"))
        return
    end
    
    local was_hidden = settings:getHideReadEntries()
    local now_hidden = settings:toggleHideReadEntries()
    
    -- Show confirmation message
    local message = now_hidden and _("Now showing only unread entries") or _("Now showing all entries")
    self:showInfoMessage(message, 2)
    
    -- Notify about settings change to invalidate caches
    self:onSettingsChanged("hide_read_entries", now_hidden)
    
    -- Refresh current view safely - this is just local filtering, no API calls needed
    if self.refreshCurrentView then
        -- Use pcall to safely call refresh and catch any errors
        local success, err = pcall(function()
            self:refreshCurrentView()
        end)
        
        if not success then
            if self.debug then
                self.debug:info("Error during refresh:", tostring(err))
            end
            self:showErrorMessage(_("Error refreshing view"))
        end
    else
        if self.debug then
            self.debug:info("refreshCurrentView method not available")
        end
    end
end

-- Check if we're currently viewing entries (not main menu, feeds list, or categories list)
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

-- Check if hiding read entries would result in no entries
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
    
    if self.debug then
        self.debug:info("Current view has " .. unread_count .. " unread entries out of " .. #self.item_table .. " total entries")
    end
    
    return unread_count == 0
end

-- Method to notify about settings changes - can be overridden by subclasses
function BaseBrowser:onSettingsChanged(setting_name, new_value)
    if self.debug then
        self.debug:info("Settings changed:", setting_name, "=", tostring(new_value))
    end
    
    -- Default implementation - subclasses can override for specific behavior
    if setting_name == "hide_read_entries" then
        -- Invalidate any cached data that depends on read/unread status
        if self.invalidateEntryCaches then
            self:invalidateEntryCaches()
        end
    end
end

-- Method to invalidate entry-related caches - can be overridden by subclasses  
function BaseBrowser:invalidateEntryCaches()
    if self.debug then
        self.debug:info("BaseBrowser:invalidateEntryCaches called - should be implemented by subclass")
    end
end

function BaseBrowser:refreshCurrentView()
    -- This method should be overridden by subclasses to refresh their specific content
    -- For now, we'll just debug log
    if self.debug then
        self.debug:info("refreshCurrentView called - should be implemented by subclass")
    end
end

function BaseBrowser:closeAll()
    -- Close this browser (single instance pattern like OPDS)
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
end

function BaseBrowser:updateBrowser(title, items, subtitle, navigation_data)
    -- Update the current browser with new content (like OPDS updateCatalog)
    
    self:debugLog("=== updateBrowser called ===")
    self:debugLog("Current title: " .. tostring(self.title))
    self:debugLog("New title: " .. tostring(title))
    self:debugLog("Items count: " .. #items)
    
    -- Determine if this is forward navigation or back navigation
    local is_back_navigation = navigation_data and navigation_data.paths_updated == true
    local is_settings_refresh = navigation_data and navigation_data.is_settings_refresh == true
    local select_number = nil
    
    if is_settings_refresh then
        self:debugLog("Settings refresh detected - resetting to page 1 but maintaining navigation")
        -- For settings refresh, reset to page 1 but maintain navigation paths
        self.page = 1
        self.selected = {1}  -- Reset selection to first item
        self.itemnumber = 1  -- Reset item number
        select_number = 1
    elseif is_back_navigation then
        self:debugLog("Back navigation detected - preserving current page state")
        
        -- Check if we need to restore page info from navigation_data
        if navigation_data and navigation_data.restore_page_info then
            local target_page = navigation_data.restore_page_info.page
            if target_page and type(target_page) == "number" and target_page >= 1 then
                -- Calculate the select_number that would put us on the target page
                local perpage = self.perpage or 14 -- Default perpage if not set
                select_number = (target_page - 1) * perpage + 1
                
                self:debugLog("Restoring to page " .. target_page .. " by selecting item " .. select_number)
                
                -- Ensure select_number is within bounds
                if select_number > #items then
                    select_number = #items > 0 and #items or 1
                    self:debugLog("Adjusted select_number to " .. select_number .. " (out of bounds)")
                end
            else
                self:debugLog("Invalid page info for restoration")
            end
        else
            self:debugLog("No page restoration info provided")
        end
    else
        self:debugLog("Forward navigation detected - resetting to page 1")
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
    
    self:debugLog("Browser updated with title: " .. title .. ", subtitle: " .. (subtitle or ""), ", items: " .. #items)
    self:debugLog("=== updateBrowser end ===")
end

function BaseBrowser:showMainContent()
    -- To be implemented by subclasses
    self:debugLog("showMainContent called - should be implemented by subclass")
end

function BaseBrowser:showFeedsContent()
    -- To be implemented by subclasses  
    self:debugLog("showFeedsContent called - should be implemented by subclass")
end

function BaseBrowser:showCategoriesContent()
    -- To be implemented by subclasses
    self:debugLog("showCategoriesContent called - should be implemented by subclass")
end

function BaseBrowser:showFeedEntries(feed_id, feed_title, paths_updated)
    -- To be implemented by subclasses
    self:debugLog("showFeedEntries called - should be implemented by subclass")
end

function BaseBrowser:showCategoryEntries(category_id, category_title, paths_updated)
    -- To be implemented by subclasses
    self:debugLog("showCategoryEntries called - should be implemented by subclass")
end

function BaseBrowser:showLoadingMessage(text)
    local loading_info = InfoMessage:new{
        text = text or _("Loading..."),
    }
    UIManager:show(loading_info)
    UIManager:forceRePaint() -- Force immediate display before API call blocks
    return loading_info
end

function BaseBrowser:closeLoadingMessage(loading_info)
    if loading_info then
        UIManager:close(loading_info)
    end
end

function BaseBrowser:showErrorMessage(message, timeout)
    UIManager:show(InfoMessage:new{
        text = message,
        timeout = timeout or 5,
    })
end

function BaseBrowser:showInfoMessage(message, timeout)
    UIManager:show(InfoMessage:new{
        text = message,
        timeout = timeout or 3,
    })
end

function BaseBrowser:debugLog(message)
    if self.debug then
        self.debug:info("[" .. (self.browser_type or "Browser") .. "] " .. message)
    end
end

function BaseBrowser:handleApiError(success, result, error_prefix)
    if not success then
        self:showErrorMessage((error_prefix or _("API Error")) .. ": " .. tostring(result))
        return false
    end
    return true
end

function BaseBrowser:validateData(data, data_name)
    if not data or (type(data) == "table" and #data == 0) then
        self:showInfoMessage(_("No ") .. (data_name or "data") .. _(" found"))
        return false
    end
    return true
end

return BaseBrowser 