--[[--
EmmyLua type definitions for BookList

@meta koplugin.miniflux.typedefs.BookList
--]] --

---@class BookListOptions : MenuOptions
---@field custom_title_bar? TitleBar Custom title bar to use instead of Menu's default

---@class BookList : Menu
---@field title_bar_fm_style boolean Whether to use FileManager title bar style
---@field custom_title_bar TitleBar|nil Custom title bar widget
---@field book_info_cache table Static cache for book information
---@field collates table Static sorting/collation configurations
---@field init fun(self: BookList): nil Initialize BookList (sets title_bar_fm_style based on custom_title_bar)
---@field extend fun(self: BookList, o: BookListOptions): BookList Extend BookList class
---@field new fun(self: BookList, o: BookListOptions): BookList Create new BookList instance
---@field setBookInfoCache fun(file: string, doc_settings: DocSettings): nil Set book info cache (static method)
---@field getBookInfo fun(file: string): table Get book info with caching (static method)
---@field hasBookBeenOpened fun(file: string): boolean Check if book has been opened (static method)
---@field getDocSettings fun(file: string): DocSettings Get DocSettings with caching (static method)
