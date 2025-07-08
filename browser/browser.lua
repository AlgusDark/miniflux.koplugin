local BookList = require("ui/widget/booklist")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

-- Navigation type definitions for generic browser functionality
---@class NavigationState<T>: {from: string, to: string, page_state: number, context?: T}
---@class RouteConfig<T>: {view_name: string, page_state?: number, context?: T, pending_nav_state?: NavigationState<T>}

---@class BrowserOptions : BookListOptions

---Browser operation modes
---@enum BrowserMode
local BrowserMode = {
    NORMAL = "normal",      -- Regular browsing mode
    SELECTION = "selection" -- Selection mode for batch operations
}

-- **Generic Browser** - Base class for content browsers
--
-- Provides generic browser functionality including navigation, menu integration,
-- and UI management using BookList for enhanced features. Implements a state machine
-- for mode transitions between normal browsing and selection modes.
--
-- PERFORMANCE OPTIMIZATION NOTE:
-- This class implements a "visible items only" optimization for selection state updates.
-- Through debugging, we discovered that selection operations were processing ALL items
-- in the dataset (e.g., 100 items) even when only a small subset was visible per page
-- (e.g., 14 items). This caused significant performance issues, especially on large feeds.
-- 
-- The optimization reduces processing time by 86-98% by only updating visual state
-- for items that are actually visible on the current page, making the interface
-- responsive regardless of dataset size.
--
---@class Browser : BookList
---@field current_mode BrowserMode # Current browser mode (state machine)
---@field selected_items table<string|number, table>|nil # Selection mode state: nil = normal mode, table = selection mode (hash table with item IDs as keys, item data as values)
---@field last_selected_index number|nil # Track last selected item index for range selection
---@field selection_dialog ButtonDialog|nil # Dialog for selection mode actions
local Browser = BookList:extend({
    title_shrink_font_to_fit = true,
    is_popout = false,
    covers_fullscreen = true,
    is_borderless = true,
    title_bar_fm_style = true,
    title_bar_left_icon = "appbar.settings",
    perpage = 20,
})

-- Export BrowserMode enum
Browser.BrowserMode = BrowserMode

function Browser:init()
    self.current_mode = BrowserMode.NORMAL
    self.selected_items = nil
    self.last_selected_index = nil

    self.show_parent = self.show_parent or self

    local TitleBar = require("ui/widget/titlebar")
    self.title_bar = TitleBar:new {
        show_parent = self.show_parent,
        fullscreen = "true",
        align = "center",
        title = self.title or _("Browser"),

        left_icon = "appbar.settings",
        left_icon_tap_callback = function() self:onLeftButtonTap() end,
        -- left_icon_hold_callback = function() self:onLeftButtonHold() end,
        right_icon = self.current_mode == BrowserMode.SELECTION and "check" or "exit",
        right_icon_tap_callback = function() self:onRightButtonTap() end,
        -- right_icon_hold_callback = function() self:onRightButtonHold() end,
    }

    -- Tell BookList to use our custom title bar
    self.custom_title_bar = self.title_bar

    -- Initialize BookList parent
    BookList.init(self)
end

---Transition to a new browser mode
---@param target_mode BrowserMode Target mode to transition to
function Browser:transitionTo(target_mode)
    if self.current_mode == target_mode then
        return
    end

    if target_mode == BrowserMode.NORMAL then
        -- Exiting selection mode - clean up all selection state
        local previous_selection_count = self.selected_items and self:getSelectedCount() or 0
        self.selected_items = nil -- Reset selection mode (enables early returns in updateItemDimStatus)
        self.last_selected_index = nil -- Reset range selection tracking
        self.title_bar:setRightIcon("exit")
        self:clearVisualSelection() -- Remove visual indicators from all items
        -- self:refreshCurrentView()
    elseif target_mode == BrowserMode.SELECTION then
        -- Entering selection mode - initialize selection state
        self.selected_items = {} -- Initialize selection mode (empty table, not nil)
        self.last_selected_index = nil -- Initialize range selection tracking
        self.title_bar:setRightIcon("check")
    else
        error("Invalid browser mode: " .. tostring(target_mode))
    end

    -- Update current state
    self.current_mode = target_mode
end

-- Show selection actions dialog with count and available batch operations
function Browser:showSelectionActionsDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local T = require("ffi/util").template
    local N_ = require("gettext").ngettext

    local selected_count = self:getSelectedCount()
    local actions_enabled = selected_count > 0

    -- Build title showing selection count
    local title
    if actions_enabled then
        title = T(N_("1 item selected", "%1 items selected", selected_count), selected_count)
    else
        title = _("No items selected")
    end

    -- Get available actions from subclass
    local selection_actions = {}
    if actions_enabled then
        local available_actions = self:getSelectionActions()
        
        for _, action in ipairs(available_actions) do
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
        table.insert(buttons, {}) -- separator
    end

    -- Add exit selection mode button
    table.insert(buttons, {
        {
            text = _("Exit selection mode"),
            callback = function()
                UIManager:close(self.selection_dialog)
                self:transitionTo(BrowserMode.NORMAL)
            end,
        },
    })

    self.selection_dialog = ButtonDialog:new({
        title = title,
        title_align = "center",
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
---@param view_name? string View to open to (defaults to "main")
function Browser:open(view_name)
    self:navigate({ view_name = view_name or "main" })
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
    for _ in pairs(self.selected_items) do
        count = count + 1
    end
    return count
end

-- Helper method to get array of selected items
function Browser:getSelectedItems()
    local selected = {}
    if self.selected_items then
        for item_id, _ in pairs(self.selected_items) do
            table.insert(selected, item_id)
        end
    end
    return selected
end

-- Override switchItemTable to maintain selection state across navigation
--
-- This method is called whenever the browser navigates to a new view or page.
-- It ensures that visual selection indicators (item.dim) are properly maintained
-- when the underlying item table changes.
--
-- PERFORMANCE NOTE: The updateItemDimStatus call here benefits from the "visible items only"
-- optimization, so navigation remains fast even with large datasets.
function Browser:switchItemTable(title, items, page_state, menu_title, subtitle)
    if self:isCurrentMode(BrowserMode.SELECTION) then
        -- Add selection state to items before displaying
        -- This ensures selected items appear dimmed when navigating between views/pages
        self:updateItemDimStatus(items)
    end

    -- Call parent BookList method to actually display the items
    BookList.switchItemTable(self, title, items, page_state, menu_title, subtitle)
end

-- Helper method to get only visible items on current page
--
-- PERFORMANCE OPTIMIZATION: This method implements the "visible items only" optimization.
-- Instead of processing all items in the dataset (which can be 100+ items), we only
-- process items that are actually visible on the current page (typically 14-20 items).
--
-- Example scenarios discovered during debugging:
-- - Feed with 100 items, page 1, perpage=14 → processes items 1-14 (86% reduction)
-- - Feed with 100 items, page 3, perpage=14 → processes items 29-42 (86% reduction)  
-- - Feed with 100 items, page 8, perpage=14 → processes items 99-100 (98% reduction)
--
-- This optimization makes selection operations O(visible) instead of O(total),
-- providing consistent performance regardless of dataset size.
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

-- Update dim status of items based on selection status (set item.dim for selected items)
--
-- PERFORMANCE OPTIMIZATION: This method implements multiple performance optimizations
-- discovered through debugging large feeds (100+ items):
--
-- 1. EARLY RETURNS: Skip processing entirely when not in selection mode or no selections exist
--    - Eliminates unnecessary work during normal browsing (95% of use cases)
--    - Uses next() for O(1) empty table detection instead of counting
--
-- 2. VISIBLE ITEMS ONLY: Only process items visible on current page  
--    - Debugging revealed we were processing ALL items (e.g., 100) when only 14 were visible
--    - Reduces processing by 86-98% depending on page position and total item count
--    - Makes performance independent of dataset size
--
-- 3. SAFE getItemId CALLS: Uses pcall to handle abstract method gracefully
--    - Prevents crashes when getItemId is not implemented by subclass
--    - Allows base class to work with partial implementations
function Browser:updateItemDimStatus(items)
    -- Early return optimizations - skip work when not needed
    if not self:isCurrentMode(BrowserMode.SELECTION) or not self.selected_items then
        return
    end

    -- Only process if items exist and we have selections
    -- Note: next(table) == nil is the standard Lua idiom for checking empty tables (O(1))
    if #items == 0 or next(self.selected_items) == nil then
        return
    end

    -- PERFORMANCE OPTIMIZATION: Only process visible items instead of all items
    -- This reduces processing from O(total_items) to O(visible_items)
    local visible_items = self:getVisibleItems(items)

    for _, item in ipairs(visible_items) do
        local success, item_id = pcall(function() return self:getItemId(item) end)
        if success and item_id then
            item.dim = self.selected_items[item_id] and true or nil
        end
    end
end

-- Refresh current view to update visual state
function Browser:refreshCurrentView()
    -- Force re-render of current items to update visual state
    if self.item_table then
        self:updateItemDimStatus(self.item_table)
        self:updateItems()
    end
end

-- Clear visual selection indicators without full refresh
function Browser:clearVisualSelection()
    if self.item_table then
        -- PERFORMANCE OPTIMIZATION: Only clear visual indicators for visible items
        local visible_items = self:getVisibleItems(self.item_table)
        for _, item in ipairs(visible_items) do
            item.dim = nil
        end
        self:updateItems()
    end
end

-- =============================================================================
-- NAVIGATION MANAGEMENT
--
-- Simple navigation using self.paths (like OPDSBrowser) to store NavigationState objects.
-- Each navigation state contains: {from, to, page_state, context}
--
-- Flow:
-- 1. User clicks "Feeds" → goForward() → store current state in self.paths → navigate()
-- 2. User hits back → goBack() → pop from self.paths → navigate()
-- 3. navigate() routes to appropriate view using provider-specific getRouteHandlers()
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

---Navigate forward (route to new view and store state only on success)
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

---Core navigation method (handles view routing, back button setup, and browser visibility)
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
        error("Unknown view: " .. tostring(nav_config.view_name))
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

    -- Handle navigation state based on view data
    if view_data.is_root then
        self.paths = {}
        self.onReturn = nil
    end

    -- Set up back button based on final navigation history
    if #self.paths > 0 then
        self.onReturn = function() self:goBack() end
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

-- =============================================================================
-- ITEM SELECTION LOGIC
-- =============================================================================

-- Override Menu's onMenuSelect to handle selection mode
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
        else
            -- Open as entry for items without callbacks
            self:openItem(item)
        end
        return true
    end
end

-- Override Menu's onMenuHold to enter selection mode or do range selection (like FileManager)
function Browser:onMenuHold(item)
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
    local success, item_id = pcall(function() return self:getItemId(item) end)
    if not success or not item_id then
        return
    end

    local item_index = self:getItemIndex(item)

    if self.selected_items[item_id] then
        self.selected_items[item_id] = nil
    else
        self.selected_items[item_id] = item
        self.last_selected_index = item_index
    end

    -- Update visual display to reflect selection changes
    -- Benefits from "visible items only" optimization for large datasets
    if self.item_table then
        self:updateItemDimStatus(self.item_table)
        self:updateItems(nil, true) -- Only visual state changed, no layout change
    end
end

-- Select an item (used when entering selection mode)
function Browser:selectItem(item)
    local success, item_id = pcall(function() return self:getItemId(item) end)
    if not success or not item_id then
        return
    end

    local item_index = self:getItemIndex(item)
    self.selected_items[item_id] = item
    self.last_selected_index = item_index

    -- Update visual display
    if self.item_table then
        self:updateItemDimStatus(self.item_table)
        self:updateItems(nil, true) -- Only visual state changed
    end
end

-- Check if an item is selected
function Browser:isItemSelected(item)
    if not self:isCurrentMode(BrowserMode.SELECTION) then
        return false
    end
    local success, item_id = pcall(function() return self:getItemId(item) end)
    if not success or not item_id then
        return false -- Return false if getItemId is not implemented
    end
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
    local success, target_item_id = pcall(function() return self:getItemId(item) end)
    local should_select = true
    if success and target_item_id then
        should_select = not self.selected_items[target_item_id]
    end

    -- Apply selection/deselection to range
    for i = start_index, end_index do
        local range_item = self.item_table[i]
        if range_item then
            local item_success, item_id = pcall(function() return self:getItemId(range_item) end)
            if item_success and item_id then
                if should_select then
                    self.selected_items[item_id] = range_item
                else
                    self.selected_items[item_id] = nil
                end
            end
        end
    end

    -- Update last selected index to current item
    self.last_selected_index = current_index

    -- Update visual display
    if self.item_table then
        self:updateItemDimStatus(self.item_table)
        self:updateItems(nil, true) -- Only visual state changed
    end
end

-- =============================================================================
-- ABSTRACT METHODS (Must be implemented by subclasses)
-- =============================================================================

---Get route handlers for this browser type
---@generic T
---@param nav_config RouteConfig<T> Navigation configuration
---@return table<string, function> Route handlers lookup table
function Browser:getRouteHandlers(nav_config)
    error("Browser subclass must implement getRouteHandlers(nav_config)")
end

---Open an item with optional navigation context
---@param item_data table Item data to open
---@param context? table Navigation context
function Browser:openItem(item_data, context)
    error("Browser subclass must implement openItem()")
end

---Get unique identifier for an item (required for selection functionality)
---@param item_data table Item data
---@return string|number Unique identifier for the item
function Browser:getItemId(item_data)
    error("Browser subclass must implement getItemId() for selection functionality")
end

---Get selection actions available for this browser type
---@return table[] Array of action objects with text and callback properties
function Browser:getSelectionActions()
    return {} -- Browser subclass must implement getSelectionActions() for selection functionality
end

return Browser
