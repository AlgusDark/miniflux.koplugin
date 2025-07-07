---@meta
---@module 'ui/widget/booklist'

---@class BookListOptions : MenuOptions

---@class BookList : Menu
---@field extend fun(self: BookList, o: BookListOptions): BookList
---@field init fun(self: BookList): nil Initialize BookList (sets title_bar_fm_style based on custom_title_bar)
---@field new fun(self: BookList, o: BookListOptions): BookList Create new BookList instance
---@field setBookInfoCache fun(file: string, doc_settings: DocSettings): nil Set book info cache (static method)
---@field getBookInfo fun(file: string): table Get book info with caching (static method)
---@field hasBookBeenOpened fun(file: string): boolean Check if book has been opened (static method)
---@field getDocSettings fun(file: string): DocSettings Get DocSettings with caching (static method)
local BookList = {}

return BookList