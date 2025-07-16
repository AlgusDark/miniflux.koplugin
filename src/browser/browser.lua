local BookList = require('ui/widget/booklist')
local UIManager = require('ui/uimanager')
local _ = require('gettext')

-- Navigation type definitions for generic browser functionality
---@class NavigationState<T>: {from: string, to: string, page_state: number, context?: T}
---@class RouteConfig<T>: {view_name: string, page_state?: number, context?: T, pending_nav_state?: NavigationState<T>}

---@class BrowserOptions : BookListOptions

---Browser operation modes
---@enum BrowserMode
local BrowserMode = {
    NORMAL = 'normal',
    SELECTION = 'selection',
}

-- Generic Browser - Base class for content browsers extending BookList
-- Implements state machine (normal/selection modes) with navigation stack
---@class Browser : BookList
---@field current_mode BrowserMode # Current browser mode (state machine)
---@field selected_items table<string|number, table>|nil # Selection mode state: nil = normal mode, table = selection mode (hash table with item IDs as keys, item data as values)
---@field last_selected_index number|nil # Track last selected item index for range selection
---@field selection_dialog ButtonDialog|nil # Dialog for selection mode actions
---@field paths table[] # Navigation history stack: {from: string, to: string, page_state: number, context?: any}[]
---@field show_parent any # Parent widget for UI management
---@field title_bar TitleBar # Custom title bar widget
local Browser = BookList:extend({
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = 'appbar.settings',
    perpage = 20,
})

-- Export BrowserMode enum
Browser.BrowserMode = BrowserMode

---Initialize Browser instance with state machine and custom title bar
---@param self Browser
function Browser:init()
    self.current_mode = BrowserMode.NORMAL
    self.selected_items = nil
    self.last_selected_index = nil
    self.show_parent = self.show_parent or self

    local TitleBar = require('ui/widget/titlebar')
    self.title_bar = TitleBar:new({
        show_parent = self.show_parent,
        fullscreen = 'true',
        align = 'center',
        title = self.title or _('Browser'),
        subtitle = '',
        subtitle_truncate_left = true,
        subtitle_fullwidth = true,

        left_icon = 'appbar.settings',
        left_icon_size_ratio = 1,
        left_icon_tap_callback = function()
            self:onLeftButtonTap()
        end,
        -- left_icon_hold_callback = function() self:onLeftButtonHold() end,
        right_icon = self.current_mode == BrowserMode.SELECTION and 'check' or 'exit',
        right_icon_size_ratio = 1,
        right_icon_tap_callback = function()
            self:onRightButtonTap()
        end,
        -- right_icon_hold_callback = function() self:onRightButtonHold() end,
    })

    -- Tell BookList to use our custom title bar
    self.custom_title_bar = self.title_bar

    -- Initialize BookList parent (sets up Menu infrastructure)
    BookList.init(self)
end

---Transition between normal and selection modes with proper state cleanup
---@param target_mode BrowserMode Target mode to transition to
function Browser:transitionTo(target_mode)
    if self.current_mode == target_mode then
        return
    end

    if target_mode == BrowserMode.NORMAL then
        -- Exiting selection mode - clean up all selection state
        self.selected_items = nil -- Reset selection mode (enables early returns in updateItemDimStatus)
        self.last_selected_index = nil -- Reset range selection tracking
        self.title_bar:setRightIcon('exit')
        self:clearVisualSelection() -- Remove visual indicators from all items
        -- self:refreshCurrentView()
    elseif target_mode == BrowserMode.SELECTION then
        -- Entering selection mode - initialize selection state
        self.selected_items = {} -- Initialize selection mode (empty table, not nil)
        self.last_selected_index = nil -- Initialize range selection tracking
        self.title_bar:setRightIcon('check')
    else
        error('Invalid browser mode: ' .. tostring(target_mode))
    end

    -- Update current state
    self.current_mode = target_mode
end

-- Show selection actions dialog with count and available batch operations
function Browser:showSelectionActionsDialog()
    local ButtonDialog = require('ui/widget/buttondialog')
    local T = require('ffi/util').template
    local N_ = require('gettext').ngettext

    local selected_count = self:getSelectedCount()
    local actions_enabled = selected_count > 0

    -- Build title showing selection count
    local title
    if actions_enabled then
        title = T(N_('1 item selected', '%1 items selected', selected_count), selected_count)
    else
        title = _('No items selected')
    end

    -- Get available actions from subclass
    local selection_actions = {}
    if actions_enabled then
        local available_actions = self:getSelectionActions()

        for i, action in ipairs(available_actions) do
            table.insert(selection_actions, {
                text = action.text,
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(self.selection_dialog)
                    local selected_items = self:getSelectedItems()
                    action.callback(selected_items)
                end,
            })
        end
    end

    -- Build button structure for ButtonDialog
    local buttons = {}

    -- Add selection actions as first row(s)
    if #selection_actions > 0 then
        -- Split actions into rows of 2 buttons each
        for i = 1, #selection_actions, 2 do
            local row = {}
            table.insert(row, selection_actions[i])
            if selection_actions[i + 1] then
                table.insert(row, selection_actions[i + 1])
            end
            table.insert(buttons, row)
        end
    end

    -- Add select/deselect all buttons
    table.insert(buttons, {
        {
            text = _('Select all'),
            callback = function()
                UIManager:close(self.selection_dialog)
                self:selectAll()
            end,
        },
        {
            text = _('Deselect all'),
            callback = function()
                UIManager:close(self.selection_dialog)
                self:deselectAll()
            end,
        },
    })

    -- Add exit selection mode button
    table.insert(buttons, {
        {
            text = _('Exit selection mode'),
            callback = function()
                UIManager:close(self.selection_dialog)
                self:transitionTo(BrowserMode.NORMAL)
            end,
        },
    })

    self.selection_dialog = ButtonDialog:new({
        title = title,
        title_align = 'center',
        buttons = buttons,
    })
    UIManager:show(self.selection_dialog)
end

---Handle right button tap
function Browser:onRightButtonTap()
    if self:isCurrentMode(BrowserMode.SELECTION) then
        self:showSelectionActionsDialog()
    else
        self:close()
    end
end

---Open the browser (defaults to main view, but flexible for future use)
---@param view_name? string View to open to (defaults to "main')
function Browser:open(view_name)
    self:navigate({ view_name = view_name or 'main' })
end

-- Helper method to check if browser is in a specific mode
function Browser:isCurrentMode(mode)
    return self.current_mode == mode
end

-- Helper method to get count of selected items
function Browser:getSelectedCount()
    if not self.selected_items then
        return 0
    end
    local count = 0
    for i in pairs(self.selected_items) do
        count = count + 1
    end
    return count
end

-- Helper method to get array of selected item IDs
function Browser:getSelectedItemIds()
    local selected = {}
    if self.selected_items then
        for item_id, i in pairs(self.selected_items) do
            table.insert(selected, item_id)
        end
    end
    return selected
end

-- Helper method to get array of selected item objects
function Browser:getSelectedItems()
    local selected = {}
    if self.selected_items then
        for item_id, item_object in pairs(self.selected_items) do
            table.insert(selected, item_object)
        end
    end
    return selected
end

-- Helper method to get item type for selection processing
function Browser:getItemType(item_data)
    -- Default implementation - subclasses can override
    if item_data.entry_data then
        return 'entry'
    end
    if item_data.feed_data then
        return 'feed'
    end
    if item_data.category_data then
        return 'category'
    end
    return nil
end

---Override switchItemTable to maintain selection state across navigation
---@param title string Menu title
---@param items table[] Array of item objects to display
---@param page_state number|nil Item number for focus/pagination
---@param menu_title string|nil Title for menu header
---@param subtitle string|nil Subtitle text
function Browser:switchItemTable(title, items, page_state, menu_title, subtitle)
    if self:isCurrentMode(BrowserMode.SELECTION) then
        -- Add selection state to items before displaying
        -- Use visible-only update for fast page navigation (HashMap lookup per visible item)
        local visible_items = self:getVisibleItems(items)
        self:updateItemDimStatus(visible_items)
    end

    -- Call parent BookList method to actually display the items
    BookList.switchItemTable(self, title, items, page_state, menu_title, subtitle)
end

-- Helper method to get only visible items on current page (performance optimization)
function Browser:getVisibleItems(all_items)
    local page = self.page or 1
    local perpage = self.perpage or 20
    local start_idx = (page - 1) * perpage + 1
    local end_idx = math.min(start_idx + perpage - 1, #all_items)

    local visible_items = {}
    for i = start_idx, end_idx do
        if all_items[i] then
            table.insert(visible_items, all_items[i])
        end
    end

    return visible_items
end

---Update dim status of items based on selection status with performance optimizations
---@param items table[] Array of item objects to process (caller determines scope)
function Browser:updateItemDimStatus(items)
    -- Early return optimizations - skip work when not needed
    if not self:isCurrentMode(BrowserMode.SELECTION) or not self.selected_items then
        return
    end

    -- Only process if items exist
    if #items == 0 then
        return
    end

    -- Process all items passed to this function (caller determines scope)
    -- When called from switchItemTable: processes current page items
    -- When called from refreshCurrentView: processes visible items only
    for i, item in ipairs(items) do
        local item_id = self:getItemId(item)
        item.dim = self.selected_items[item_id] and true or nil
    end
end

-- Refresh current view to update visual state
function Browser:refreshCurrentView()
    -- Let updateItems handle the visual state update efficiently
    if self.item_table then
        self:updateItems(nil, true) -- select_number=1, no_recalculate_dimen=true
    end
end

-- Clear visual selection indicators without full refresh
function Browser:clearVisualSelection()
    if self.item_table then
        -- PERFORMANCE OPTIMIZATION: Only clear visual indicators for visible items
        local visible_items = self:getVisibleItems(self.item_table)
        for i, item in ipairs(visible_items) do
            item.dim = nil
        end
        self:updateItems(1, true) -- select_number=1, no_recalculate_dimen=true
    end
end

-- =============================================================================
-- NAVIGATION MANAGEMENT
-- =============================================================================

---Get current item number for page state restoration
---@return number Current item number (for use with switchItemTable)
function Browser:getCurrentItemNumber()
    local page = tonumber(self.page) or 1
    local perpage = tonumber(self.perpage) or 20
    local current_item = tonumber(self.itemnumber) or 1

    if page > 1 then
        local item_number = (page - 1) * perpage + current_item
        return math.max(item_number, 1)
    end

    return math.max(current_item, 1)
end

---Navigate forward with atomic state management
---@generic T
---@param nav_config NavigationState<T> Forward navigation configuration
function Browser:goForward(nav_config)
    -- Prepare navigation state but don't add to stack yet
    self.paths = self.paths or {}
    local nav_state = {
        from = nav_config.from,
        to = nav_config.to,
        page_state = self:getCurrentItemNumber(),
    }
    if nav_config.context then
        nav_state.context = nav_config.context
    end

    -- Navigate to new view (always start fresh when going forward)
    local route_config = {
        view_name = nav_config.to,
        page_state = nil, -- start fresh
        pending_nav_state = nav_state, -- Add to stack only on successful view render
    }
    if nav_config.context then
        route_config.context = nav_config.context
    end
    self:navigate(route_config)
end

---Navigate back (pop previous state from paths and route back)
function Browser:goBack()
    -- Exit selection mode before navigating back to prevent crashes
    if self:isCurrentMode(BrowserMode.SELECTION) then
        self:transitionTo(BrowserMode.NORMAL)
    end

    local prev_nav = table.remove(self.paths)
    if prev_nav then
        -- Navigate back to previous view (restore page position)
        local route_config = {
            view_name = prev_nav.from,
            page_state = prev_nav.page_state, -- restore position
        }
        if prev_nav.context then
            route_config.context = prev_nav.context
        end
        self:navigate(route_config)
    end
end

---Core navigation method - handles view routing, back button setup, and browser visibility
---@generic T
---@param nav_config RouteConfig<T> Navigation configuration
function Browser:navigate(nav_config)
    if not UIManager:isWidgetShown(self) then
        UIManager:show(self)
    end

    -- Get provider-specific route handlers
    local view_handlers = self:getRouteHandlers(nav_config)
    local handler = view_handlers[nav_config.view_name]
    if not handler then
        error('Unknown view: ' .. tostring(nav_config.view_name))
    end

    -- Get view data from the view component
    local view_data = handler()
    if not view_data then
        return -- Error already handled by view component - no navigation state change
    end

    -- Success! Add navigation state to stack if this was a forward navigation
    if nav_config.pending_nav_state then
        table.insert(self.paths, nav_config.pending_nav_state)
    end

    -- Store view data for access by subclasses (e.g., settings dialog)
    self.view_data = view_data

    -- Handle navigation state based on view data
    if view_data.is_root then
        self.paths = {}
        self.onReturn = nil
    end

    -- Set up back button based on final navigation history
    if #self.paths > 0 then
        self.onReturn = function()
            self:goBack()
        end
    else
        self.onReturn = nil -- At root
    end

    -- Render the view using returned data
    self:switchItemTable(
        view_data.title,
        view_data.items,
        view_data.page_state,
        view_data.menu_title,
        view_data.subtitle
    )
end

---Close the browser (for compatibility with entry service)
function Browser:close()
    UIManager:close(self)
end

-- Page navigation methods are inherited from BookList
-- No need to override unless adding specific Browser functionality

-- Override updateItems to maintain selection state during page navigation
-- Clean approach: apply selection state to items before Menu builds the UI components
---@param select_number number|nil
---@param no_recalculate_dimen boolean|nil
function Browser:updateItems(select_number, no_recalculate_dimen)
    -- Apply selection state to items BEFORE calling parent updateItems
    -- This way Menu builds MenuItem widgets with the correct item.dim state from the start
    if self:isCurrentMode(BrowserMode.SELECTION) and self.item_table then
        local visible_items = self:getVisibleItems(self.item_table)
        self:updateItemDimStatus(visible_items)
    end

    -- Now let parent build the UI with the correctly updated item.dim states
    BookList.updateItems(self, select_number, no_recalculate_dimen)
end

-- =============================================================================
-- ITEM SELECTION LOGIC
-- =============================================================================

---Override Menu's onMenuSelect to handle selection mode
---@param item table Item data object with id, callback, and other properties
---@return boolean true (event handled)
function Browser:onMenuSelect(item)
    if self:isCurrentMode(BrowserMode.SELECTION) then
        -- Selection mode: toggle item selection
        self:toggleItemSelection(item)
        return true
    else
        -- Normal mode: check if item has callback (navigation) or should be opened (entry)
        if item.callback then
            -- Execute callback for navigation items (Unread, Feeds, Categories, etc.)
            item.callback()
        elseif item.action_type == 'no_action' then
            -- Ignore items marked as non-interactive (e.g., "No offline content available")
            return true
        else
            -- Open as entry for items without callbacks
            self:openItem(item)
        end
        return true
    end
end

---Override Menu's onMenuHold to enter selection mode or do range selection
---@param item table Item data object
---@return boolean true (event handled)
function Browser:onMenuHold(item)
    -- Ignore items marked as non-interactive
    if item.action_type == 'no_action' then
        return true
    end

    -- Only allow selection mode for items that have IDs (getItemId returns non-nil)
    local item_id = self:getItemId(item)
    if not item_id then
        return true -- Item not selectable, ignore hold event
    end

    if not self:isCurrentMode(BrowserMode.SELECTION) then
        -- Enter selection mode and select this item
        self:transitionTo(BrowserMode.SELECTION)
        self:selectItem(item)
    else
        -- Already in selection mode, do range selection
        self:doRangeSelection(item)
    end
    return true
end

-- Toggle selection state of an item
function Browser:toggleItemSelection(item)
    local item_id = self:getItemId(item)
    local item_index = self:getItemIndex(item)

    if self.selected_items[item_id] then
        self.selected_items[item_id] = nil
    else
        self.selected_items[item_id] = item
        self.last_selected_index = item_index
    end

    -- Update visual display to reflect selection changes
    -- Use refreshCurrentView for better performance - navigation handles cross-page consistency
    self:refreshCurrentView()
end

-- Select an item (used when entering selection mode)
function Browser:selectItem(item)
    local item_id = self:getItemId(item)
    local item_index = self:getItemIndex(item)

    self.selected_items[item_id] = item
    self.last_selected_index = item_index

    -- Update visual display
    self:refreshCurrentView()
end

-- Check if an item is selected
function Browser:isItemSelected(item)
    if not self:isCurrentMode(BrowserMode.SELECTION) then
        return false
    end
    local item_id = self:getItemId(item)

    return self.selected_items[item_id] ~= nil
end

-- Get the index of an item in the current item table
function Browser:getItemIndex(item)
    if not self.item_table then
        return nil
    end

    for i, table_item in ipairs(self.item_table) do
        if table_item == item then
            return i
        end
    end
    return nil
end

-- Perform range selection from last selected item to current item
function Browser:doRangeSelection(item)
    if not self:isCurrentMode(BrowserMode.SELECTION) or not self.item_table then
        return
    end

    local current_index = self:getItemIndex(item)
    if not current_index then
        return
    end

    -- If no previous selection, just select this item
    if not self.last_selected_index then
        self:selectItem(item)
        return
    end

    -- Calculate range
    local start_index = math.min(self.last_selected_index, current_index)
    local end_index = math.max(self.last_selected_index, current_index)

    -- Determine if we should select or deselect based on the target item's current state
    local target_item_id = self:getItemId(item)
    local should_select = not self.selected_items[target_item_id]

    -- Apply selection/deselection to range
    for i = start_index, end_index do
        local range_item = self.item_table[i]
        if range_item then
            local item_id = self:getItemId(range_item)
            if should_select then
                self.selected_items[item_id] = range_item
            else
                self.selected_items[item_id] = nil
            end
        end
    end

    -- Update last selected index to current item
    self.last_selected_index = current_index

    -- Update visual display (HashMap + current page only, other pages updated on navigation)
    self:refreshCurrentView()
end

---Select all items in the current view (FileChooser pattern)
---@param do_select boolean|nil true to select all, false to deselect all, nil defaults to true
function Browser:selectAllInCurrentView(do_select)
    if not self:isCurrentMode(BrowserMode.SELECTION) or not self.item_table then
        return
    end

    -- Default to select if not specified
    if do_select == nil then
        do_select = true
    end

    -- Update selection state for all items (following FileChooser pattern)
    for i, item in ipairs(self.item_table) do
        local item_id = self:getItemId(item)
        if item_id then
            if do_select then
                self.selected_items[item_id] = item
                item.dim = true
            else
                self.selected_items[item_id] = nil
                item.dim = nil
            end
        end
    end

    -- Update last selected index for range selection
    if do_select then
        self.last_selected_index = #self.item_table
    else
        self.last_selected_index = nil
    end

    -- Efficient visual update (following FileChooser pattern)
    self:updateItems(1, true)
end

-- Legacy method for backward compatibility
function Browser:selectAll()
    self:selectAllInCurrentView(true)
end

-- Legacy method for backward compatibility
function Browser:deselectAll()
    self:selectAllInCurrentView(false)
end

-- =============================================================================
-- ABSTRACT METHODS (Must be implemented by subclasses)
-- =============================================================================

---Get route handlers for this browser type (abstract method)
---@generic T
---@param nav_config RouteConfig<T> Navigation configuration
---@return table<string, function> Route handlers lookup table
function Browser:getRouteHandlers(nav_config)
    error('Browser subclass must implement getRouteHandlers(nav_config)')
end

---Open an item with optional navigation context
---@param item_data table Item data to open
---@param context? table Navigation context
function Browser:openItem(item_data, context)
    error('Browser subclass must implement openItem()')
end

---Get unique identifier for an item (required for selection functionality)
---@param item_data table Item data object
---@return string|number Unique identifier for the item
function Browser:getItemId(item_data)
    error('Browser subclass must implement getItemId() for selection functionality')
end

---Get selection actions available for this browser type
---@return table[] Array of action objects with text and callback properties
function Browser:getSelectionActions()
    return {} -- Browser subclass must implement getSelectionActions() for selection functionality
end

return Browser
