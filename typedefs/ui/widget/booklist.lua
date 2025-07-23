---@meta
---@module 'ui/widget/booklist'

---@class BookListOptions : MenuOptions
---@field path? string Directory path for book listing
---@field collate? string Collation method for sorting (see BookList.collates)
---@field reverse_collate? boolean Whether to reverse sort order
---@field show_parent? any Parent widget for showing dialogs
---@field ui? any UI context for accessing bookinfo and other services
---@field filemanager? any FileManager instance for file operations
---@field reader? any Reader instance for reader context
---@field file_filter? function Function to filter files in the list
---@field books_per_page? number Books per page (alias for perpage)
---@field show_hidden? boolean Whether to show hidden files
---@field show_unsupported? boolean Whether to show unsupported files
---@field search_mode? boolean Whether in search mode
---@field search_string? string Search query string
---@field sort_by? string Sort field (access, date, size, etc.)

---@class BookInfo
---@field been_opened boolean Whether book has been opened
---@field status string|nil Book status ("reading", "complete", "abandoned")
---@field pages number|nil Total pages in book
---@field has_annotations boolean|nil Whether book has annotations
---@field percent_finished number|nil Reading progress (0.0 to 1.0)
---@field last_read_time number|nil Last read timestamp
---@field read_time number|nil Total reading time
---@field highlight table|nil Highlight data
---@field bookmark table|nil Bookmark data
---@field annotations table|nil Annotations data
---@field summary table|nil Summary data including status
---@field stats table|nil Reading statistics
---@field doc_pages number|nil Document page count

---@class BookListItem : MenuItem
---@field text string Book title or filename
---@field mandatory? string Secondary info (date, size, progress)
---@field path string Full path to the book file
---@field file string Filename without path
---@field suffix string File extension
---@field attr table File attributes (size, modification time, etc.)
---@field opened boolean Whether book has been opened
---@field percent_finished number Reading progress (0.0 to 1.0)
---@field sort_percent number Progress for sorting purposes
---@field doc_props table Document properties (title, authors, etc.)
---@field is_file boolean Whether this is a file (not directory)
---@field is_dir boolean Whether this is a directory
---@field is_go_up boolean Whether this is a "go up" directory entry

---@class CollationConfig
---@field text? string Display name for collation method
---@field menu_order? number Order in collation menu
---@field can_collate_mixed? boolean Whether can sort mixed file types
---@field init_sort_func? fun(cache?: table): function, table? Initialize sort function
---@field item_func? fun(item: BookListItem, ui?: any): nil Process item before sorting
---@field mandatory_func? fun(item: BookListItem): string Generate mandatory text

---BookList widget for KOReader - A specialized Menu for displaying book collections
---
---The BookList widget extends Menu to provide book-specific functionality including:
---- Book status tracking (reading, finished, on hold)
---- Progress information and completion percentages
---- Book metadata display with sorting capabilities
---- File-based book information caching
---- Integration with DocSettings for persistent book state
---
---BookList is the foundation for file browsers and book collection displays in KOReader,
---providing rich book-specific features while maintaining the pagination and navigation
---capabilities of the base Menu widget.
---@class BookList : Menu
---@field covers_fullscreen boolean Whether covers fullscreen (default: true)
---@field is_borderless boolean Whether is borderless (default: true)
---@field is_popout boolean Whether is popout (default: false)
---@field book_info_cache table<string, BookInfo> Static cache for book info
---@field collates table<string, CollationConfig> Available collation methods
---@field path string Current directory path
---@field collate string Current collation method
---@field reverse_collate boolean Whether sort is reversed
---@field show_parent any Parent widget for dialogs
---@field ui any UI context
---@field filemanager any FileManager instance
---@field reader any Reader instance
---@field file_filter function File filter function
---@field show_hidden boolean Whether to show hidden files
---@field show_unsupported boolean Whether to show unsupported files
---@field search_mode boolean Whether in search mode
---@field search_string string Search query
---@field sort_by string Current sort field
---@field page number Current page number
---@field perpage number Items per page
---@field itemnumber number Current selected item number
---@field item_table table[] Current items being displayed
local BookList = {}

---Available collation methods for sorting books
---@type table<string, CollationConfig>
BookList.collates = {
    strcoll = {}, -- Sort by name (locale-aware)
    natural = {}, -- Natural sorting ("file2" before "file10")
    access = {}, -- Sort by last read date
    date = {}, -- Sort by modification date
    size = {}, -- Sort by file size
    type = {}, -- Sort by file type
    percent_unopened_first = {}, -- Sort by progress, unopened first
    percent_unopened_last = {}, -- Sort by progress, unopened last
    percent_natural = {}, -- Sort by progress with natural ordering
    title = {}, -- Sort by book title metadata
    authors = {}, -- Sort by author metadata
    series = {}, -- Sort by series metadata
    keywords = {}, -- Sort by keywords metadata
}

---Initialize BookList with options
---@param self BookList
---@param options? BookListOptions
function BookList:init(options) end

---Set book info cache entry (static method)
---@param file string File path
---@param doc_settings DocSettings Document settings
function BookList.setBookInfoCache(file, doc_settings) end

---Set specific book info cache property (static method)
---@param file string File path
---@param prop_name string Property name
---@param prop_value any Property value
function BookList.setBookInfoCacheProperty(file, prop_name, prop_value) end

---Reset book info cache for file (static method)
---@param file string File path
function BookList.resetBookInfoCache(file) end

---Check if book info is cached (static method)
---@param file string File path
---@return boolean True if cached
function BookList.hasBookInfoCache(file) end

---Get book info with caching (static method)
---@param file string File path
---@return BookInfo Book information
function BookList.getBookInfo(file) end

---Check if book has been opened (static method)
---@param file string File path
---@return boolean True if book has been opened
function BookList.hasBookBeenOpened(file) end

---Get DocSettings with caching (static method)
---@param file string File path
---@return DocSettings Document settings
function BookList.getDocSettings(file) end

---Get book status (static method)
---@param file string File path
---@return string Book status ("new", "reading", "complete", "abandoned")
function BookList.getBookStatus(file) end

---Get book status string with localization (static method)
---@param status string Status code
---@param with_prefix? boolean Whether to include "Status:" prefix
---@param singular? boolean Whether to use singular form
---@return string|nil Localized status string
function BookList.getBookStatusString(status, with_prefix, singular) end

---Get current collation configuration
---@param self BookList
---@return CollationConfig Current collation config
function BookList:getCurrentCollation() end

---Set collation method
---@param self BookList
---@param collate string Collation method name
---@param reverse? boolean Whether to reverse sort
function BookList:setCollation(collate, reverse) end

---Sort items using current collation
---@param self BookList
---@param items BookListItem[] Items to sort
---@return BookListItem[] Sorted items
function BookList:sortItems(items) end

---Apply current file filter to items
---@param self BookList
---@param items BookListItem[] Items to filter
---@return BookListItem[] Filtered items
function BookList:filterItems(items) end

---Generate book list item from file info
---@param self BookList
---@param file string File path
---@param attr table File attributes
---@return BookListItem Generated item
function BookList:getBookListItem(file, attr) end

---Update book display after status change
---@param self BookList
---@param file string File path
function BookList:updateBookDisplay(file) end

---Refresh book list display
---@param self BookList
function BookList:refreshBooks() end

---Handle book selection
---@param self BookList
---@param item BookListItem Selected item
function BookList:onBookSelect(item) end

---Handle book hold gesture
---@param self BookList
---@param item BookListItem Held item
function BookList:onBookHold(item) end

---Show book info dialog
---@param self BookList
---@param item BookListItem Book item
function BookList:showBookInfo(item) end

---Show book actions dialog
---@param self BookList
---@param item BookListItem Book item
function BookList:showBookActions(item) end

---Mark book as read
---@param self BookList
---@param item BookListItem Book item
function BookList:markAsRead(item) end

---Mark book as unread
---@param self BookList
---@param item BookListItem Book item
function BookList:markAsUnread(item) end

---Set book status
---@param self BookList
---@param item BookListItem Book item
---@param status string New status
function BookList:setBookStatus(item, status) end

---Delete book file
---@param self BookList
---@param item BookListItem Book item
function BookList:deleteBook(item) end

---Show book statistics
---@param self BookList
---@param item BookListItem Book item
function BookList:showBookStats(item) end

---Export book annotations
---@param self BookList
---@param item BookListItem Book item
function BookList:exportAnnotations(item) end

---Search books by query
---@param self BookList
---@param query string Search query
function BookList:searchBooks(query) end

---Clear search results
---@param self BookList
function BookList:clearSearch() end

---Toggle between search and normal mode
---@param self BookList
function BookList:toggleSearch() end

---Handle directory navigation
---@param self BookList
---@param path string Directory path
function BookList:changeDirectory(path) end

---Go up one directory level
---@param self BookList
function BookList:goUp() end

---Refresh current directory
---@param self BookList
function BookList:refresh() end

---Handle file system changes
---@param self BookList
function BookList:onFileSystemChange() end

---Update item display with book info
---@param self BookList
---@param item BookListItem Item to update
function BookList:updateItemDisplay(item) end

---Get book cover image path
---@param self BookList
---@param item BookListItem Book item
---@return string|nil Cover image path
function BookList:getBookCover(item) end

---Show book cover
---@param self BookList
---@param item BookListItem Book item
function BookList:showBookCover(item) end

---Handle book metadata update
---@param self BookList
---@param item BookListItem Book item
---@param metadata table New metadata
function BookList:updateBookMetadata(item, metadata) end

---Handle collection changes
---@param self BookList
---@param collection string Collection name
---@param action string Action ("add", "remove")
---@param items BookListItem[] Affected items
function BookList:handleCollectionChange(collection, action, items) end

---Extend BookList class with new options
---@param self BookList
---@param o BookListOptions Options to extend with
---@return BookList Extended BookList class
function BookList:extend(o) end

---Create new BookList instance
---@param self BookList
---@param o BookListOptions Options for new instance
---@return BookList New BookList instance
function BookList:new(o) end

return BookList
