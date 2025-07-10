---@meta
---@module 'ui/widget/menu'

---@class MenuOptions
---@field title? string Menu title displayed at top
---@field subtitle? string Menu subtitle displayed below title
---@field item_table? table[] Initial menu items array
---@field perpage? number Items per page (default: calculated based on screen size)
---@field is_popout? boolean Whether menu is a popout dialog (default: false)
---@field covers_fullscreen? boolean Whether menu covers fullscreen (default: false)
---@field is_borderless? boolean Whether menu is borderless (default: false)
---@field title_bar_fm_style? boolean Whether to use file manager title bar style (default: false)
---@field title_bar_left_icon? string Left icon in title bar (e.g., "appbar.settings")
---@field title_shrink_font_to_fit? boolean Whether to shrink title font to fit (default: false)
---@field custom_title_bar? TitleBar Custom title bar widget to use instead of default
---@field single_line? boolean Whether menu items should be single line (default: false)
---@field multilines_show_more_text? boolean Whether to show "more" text for multiline items (default: false)
---@field onReturn? function Back navigation callback when back button is pressed
---@field onLeftButtonTap? function Left button callback for title bar
---@field onRightButtonTap? function Right button callback for title bar
---@field onMenuSelect? function Item selection callback: fun(item: table)
---@field onMenuHold? function Item hold callback: fun(item: table)
---@field onMenuChoice? function Menu choice callback: fun(item: table)
---@field onClose? function Callback when menu is closed

---@class MenuItem
---@field text string Display text for the item
---@field mandatory? string Secondary text shown on the right side (e.g., counts, timestamps)
---@field callback? function Callback when item is selected
---@field hold_callback? function Callback when item is held
---@field dim? boolean Whether item should be dimmed (for selection indication)
---@field enabled? boolean Whether item is enabled for selection (default: true)
---@field icon? string Icon to display for the item
---@field id? string|number Unique identifier for the item
---@field keep_menu_open? boolean Whether to keep menu open after selection (default: false)
---@field separator? boolean Whether this item is a separator
---@field checked? boolean Whether item shows as checked
---@field radio_checked? boolean Whether item shows as radio checked
---@field bold? boolean Whether item text should be bold
---@field font_func? function Function to get font for item text
---@field color? number Color for item text
---@field fgcolor? number Foreground color for item text
---@field avoid_text_truncation? boolean Whether to avoid truncating text

---Menu widget for KOReader - A flexible pagination-based menu system
---
---The Menu widget provides a foundation for creating paginated lists with navigation,
---item selection, and optional title bars. It extends InputContainer to handle touch
---and keyboard input events.
---
---Core Features:
---- Pagination with page navigation controls
---- Item selection with tap/hold/key events
---- Optional title bar with custom icons and callbacks
---- Keyboard navigation support with shortcuts
---- Configurable item rendering and display
---- Support for both popout and fullscreen modes
---@class Menu : InputContainer
---@field title string Menu title
---@field subtitle string Menu subtitle
---@field item_table table[] Menu items array
---@field page number Current page number (1-based)
---@field selected table Selected items (for compatibility)
---@field itemnumber number Current item number within current page (1-based)
---@field perpage number Items per page
---@field paths table[] Navigation paths for hierarchical menus
---@field onReturn function|nil Back navigation callback
---@field onLeftButtonTap function Left button callback
---@field onRightButtonTap function Right button callback
---@field onMenuSelect function Item selection callback
---@field onMenuHold function Item hold callback
---@field onMenuChoice function Menu choice callback
---@field onClose function Close callback
---@field custom_title_bar TitleBar|nil Custom title bar widget
---@field title_bar_fm_style boolean Whether using file manager title bar style
---@field title_bar_left_icon string Left icon in title bar
---@field title_shrink_font_to_fit boolean Whether to shrink title font to fit
---@field is_popout boolean Whether menu is a popout
---@field covers_fullscreen boolean Whether menu covers fullscreen
---@field is_borderless boolean Whether menu is borderless
---@field single_line boolean Whether menu items are single line
---@field multilines_show_more_text boolean Whether to show "more" text
---@field item_width number Width of menu items
---@field item_height number Height of menu items
---@field page_info TextWidget Page information widget
---@field menu_frame FrameContainer Main menu frame container
---@field menu_title_group VerticalGroup Title group container
---@field item_group VerticalGroup Items group container
---@field show_parent any Parent widget for showing dialogs
---@field cur_page number Current page (alias for page)
---@field page_num number Total number of pages
---@field main_content VerticalGroup Main content container
---@field items_per_page number Items per page (alias for perpage)
---@field footer_left Button|nil Left footer button
---@field footer_right Button|nil Right footer button
---@field footer_center TextWidget|nil Center footer text
---@field no_title boolean Whether menu has no title
local Menu = {}

---Initialize menu widget with options
---@param self Menu
---@param options MenuOptions
function Menu:init(options) end

---Switch menu content to new items and title
---@param self Menu
---@param title string New menu title
---@param items table[] New menu items
---@param select_number? number Item to select (1-based)
---@param menu_title? string Menu title (deprecated, use title)
---@param subtitle? string Menu subtitle
function Menu:switchItemTable(title, items, select_number, menu_title, subtitle) end

---Update page information display
---@param self Menu
function Menu:updatePageInfo() end

---Update menu items display
---@param self Menu
---@param select_number? number Item to select (1-based)
---@param no_recalculate_dimen? boolean Skip dimension recalculation for performance
function Menu:updateItems(select_number, no_recalculate_dimen) end

---Go to specific page
---@param self Menu
---@param page number Page number to go to (1-based)
function Menu:goToPage(page) end

---Go to next page
---@param self Menu
function Menu:nextPage() end

---Go to previous page
---@param self Menu
function Menu:prevPage() end

---Go to first page
---@param self Menu
function Menu:firstPage() end

---Go to last page
---@param self Menu
function Menu:lastPage() end

---Handle menu select event (item tap)
---@param self Menu
---@param item table Selected item
function Menu:onMenuSelect(item) end

---Handle menu hold event (item hold)
---@param self Menu
---@param item table Held item
function Menu:onMenuHold(item) end

---Handle menu choice event
---@param self Menu
---@param item table Chosen item
function Menu:onMenuChoice(item) end

---Handle close event
---@param self Menu
function Menu:onClose() end

---Handle back key event
---@param self Menu
function Menu:onBack() end

---Handle next page key event
---@param self Menu
function Menu:onNextPage() end

---Handle previous page key event
---@param self Menu
function Menu:onPrevPage() end

---Handle first page key event
---@param self Menu
function Menu:onFirst() end

---Handle last page key event
---@param self Menu
function Menu:onLast() end

---Handle select key event
---@param self Menu
function Menu:onSelect() end

---Handle tap gesture
---@param self Menu
---@param arg table Gesture arguments
function Menu:onTap(arg) end

---Handle hold gesture
---@param self Menu
---@param arg table Gesture arguments
function Menu:onHold(arg) end

---Handle swipe gesture
---@param self Menu
---@param arg table Gesture arguments
function Menu:onSwipe(arg) end

---Handle multiswipe gesture
---@param self Menu
---@param arg table Gesture arguments
function Menu:onMultiSwipe(arg) end

---Get current selected item
---@param self Menu
---@return table|nil Selected item or nil if none
function Menu:getCurrentItem() end

---Get item at specific index
---@param self Menu
---@param index number Item index (1-based)
---@return table|nil Item at index or nil if not found
function Menu:getItemAtIndex(index) end

---Get total number of items
---@param self Menu
---@return number Total item count
function Menu:getItemCount() end

---Get current page items
---@param self Menu
---@return table[] Items on current page
function Menu:getCurrentPageItems() end

---Check if menu is at first page
---@param self Menu
---@return boolean True if at first page
function Menu:isFirstPage() end

---Check if menu is at last page
---@param self Menu
---@return boolean True if at last page
function Menu:isLastPage() end

---Calculate dimensions for menu layout
---@param self Menu
function Menu:_recalculateDimen() end

---Update menu title
---@param self Menu
---@param title string New title
function Menu:setTitle(title) end

---Update menu subtitle
---@param self Menu
---@param subtitle string New subtitle
function Menu:setSubtitle(subtitle) end

---Extend menu class with new options
---@param self Menu
---@param o MenuOptions Options to extend with
---@return Menu Extended menu class
function Menu:extend(o) end

---Create new menu instance
---@param self Menu
---@param o MenuOptions Options for new instance
---@return Menu New menu instance
function Menu:new(o) end

return Menu
