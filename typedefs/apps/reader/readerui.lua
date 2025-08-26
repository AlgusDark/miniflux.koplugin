---@meta
---@module 'apps/reader/readerui'

---ReaderUI is an abstraction for a reader interface
---@class ReaderUI : InputContainer
---@field name string Widget name ("ReaderUI")
---@field active_widgets table[] Array of always active widgets
---@field dialog table Parent container reference
---@field document table Document interface
---@field password string Password for document unlock
---@field postInitCallback function[] Post initialization callbacks
---@field postReaderReadyCallback function[] Post reader ready callbacks
---@field doc_settings table Document settings
---@field dimen table Widget dimensions
---
--- Core reader modules (always present)
---@field view table ReaderView module
---@field link table ReaderLink module
---@field highlight table ReaderHighlight module
---@field menu table ReaderMenu module
---@field handmade table ReaderHandMade module
---@field toc table ReaderToc module
---@field bookmark table ReaderBookmark module
---@field annotation table ReaderAnnotation module
---@field gotopage table ReaderGoto module
---@field languagesupport table LanguageSupport module
---@field dictionary table ReaderDictionary module
---@field wikipedia table ReaderWikipedia module
---@field screenshot table Screenshoter module
---@field devicestatus table ReaderDeviceStatus module
---@field scrolling table ReaderScrolling module
---@field back table ReaderBack module
---@field search table ReaderSearch module
---@field status table ReaderStatus module
---@field thumbnail table ReaderThumbnail module
---@field filesearcher table FileManagerFileSearcher module
---@field folder_shortcuts table FileManagerShortcuts module
---@field history table FileManagerHistory module
---@field collections table FileManagerCollection module
---@field bookinfo table FileManagerBookInfo module
---@field devicelistener table DeviceListener module
---@field networklistener table NetworkListener module
---
--- Document type specific modules (conditional)
---@field config? table ReaderConfig module (PDF/DJVU only)
---@field koptlistener? table ReaderKoptListener module (PDF/DJVU only)
---@field crelistener? table ReaderCoptListener module (PDF/DJVU only)
---@field activityindicator? table ReaderActivityIndicator module (PDF/DJVU only)
---@field cropping? table ReaderCropping module (PDF/DJVU only)
---@field paging? table ReaderPaging module (PDF/DJVU only)
---@field zooming? table ReaderZooming module (PDF/DJVU only)
---@field panning? table ReaderPanning module (PDF/DJVU only)
---@field hinting? table ReaderHinting module (PDF/DJVU only)
---@field styletweak? table ReaderStyleTweak module (EPUB/FB2/HTML only)
---@field typeset? table ReaderTypeset module (EPUB/FB2/HTML only)
---@field font? table ReaderFont module (EPUB/FB2/HTML only)
---@field userhyph? table ReaderUserHyph module (EPUB/FB2/HTML only)
---@field typography? table ReaderTypography module (EPUB/FB2/HTML only)
---@field rolling? table ReaderRolling module (EPUB/FB2/HTML only)
---@field pagemap? table ReaderPageMap module (EPUB/FB2/HTML only)
---
--- Dynamic plugin modules (registered at runtime)
---@field [string] any Allow access to dynamically registered plugin modules
local ReaderUI = {}

---Register a module with the ReaderUI
---@param name string Module name (will be prefixed with "reader")
---@param ui_module table Module instance to register
---@param always_active? boolean Whether module should be always active
---@return nil
function ReaderUI:registerModule(name, ui_module, always_active) end

---Register a post-initialization callback
---@param callback function Callback to execute after init
---@return nil
function ReaderUI:registerPostInitCallback(callback) end

---Register a post-reader-ready callback
---@param callback function Callback to execute after reader is ready
---@return nil
function ReaderUI:registerPostReaderReadyCallback(callback) end

---Initialize the ReaderUI
---@return nil
function ReaderUI:init() end

---Register key events for the reader
---@return nil
function ReaderUI:registerKeyEvents() end

---Set last directory for file browser navigation
---@param dir string Directory path
---@return nil
function ReaderUI:setLastDirForFileBrowser(dir) end

---Get last directory file path
---@param to_file_browser boolean Whether going to file browser
---@return string|nil File path or nil
function ReaderUI:getLastDirFile(to_file_browser) end

---Show file manager interface
---@param file? string Initial file to show
---@param selected_files? table Selected files list
---@return nil
function ReaderUI:showFileManager(file, selected_files) end

---Handle showing reader event
---@return nil
function ReaderUI:onShowingReader() end

---Handle setup show reader event
---@return nil
function ReaderUI:onSetupShowReader() end

---Show reader with document
---@param file string Document file path
---@param provider? table Document provider
---@param seamless? boolean Whether to show seamlessly
---@param is_provider_forced? boolean Whether provider is forced
---@return nil
function ReaderUI:showReader(file, provider, seamless, is_provider_forced) end

---Extend document provider
---@param file string Document file path
---@param provider table Document provider
---@param is_provider_forced boolean Whether provider is forced
---@return table Extended provider
function ReaderUI:extendProvider(file, provider, is_provider_forced) end

---Show reader coroutine
---@param file string Document file path
---@param provider table Document provider
---@param seamless boolean Whether to show seamlessly
---@return nil
function ReaderUI:showReaderCoroutine(file, provider, seamless) end

---Actually show the reader
---@param file string Document file path
---@param provider table Document provider
---@param seamless boolean Whether to show seamlessly
---@return nil
function ReaderUI:doShowReader(file, provider, seamless) end

---Unlock document with password
---@param document table Document instance
---@param try_again? boolean Whether this is a retry attempt
---@return nil
function ReaderUI:unlockDocumentWithPassword(document, try_again) end

---Handle verify password event
---@param document table Document instance
---@return nil
function ReaderUI:onVerifyPassword(document) end

---Close dialog
---@return nil
function ReaderUI:closeDialog() end

---Handle screen resize event
---@param dimen table New dimensions
---@return nil
function ReaderUI:onScreenResize(dimen) end

---Save settings to disk
---@return nil
function ReaderUI:saveSettings() end

---Handle flush settings event
---@param show_notification? boolean Whether to show notification
---@return nil
function ReaderUI:onFlushSettings(show_notification) end

---Close the document
---@return nil
function ReaderUI:closeDocument() end

---Handle close event
---@param full_refresh? boolean Whether to do full refresh
---@return nil
function ReaderUI:onClose(full_refresh) end

---Handle close widget event
---@return nil
function ReaderUI:onCloseWidget() end

---Deal with document loading failure
---@return nil
function ReaderUI:dealWithLoadDocumentFailure() end

---Handle home button event
---@return boolean Event handled
function ReaderUI:onHome() end

---Handle reload event
---@return nil
function ReaderUI:onReload() end

---Reload the document
---@param after_close_callback? function Callback after close
---@param seamless? boolean Whether to reload seamlessly
---@return nil
function ReaderUI:reloadDocument(after_close_callback, seamless) end

---Switch to a different document
---@param new_file string New document file path
---@param seamless? boolean Whether to switch seamlessly
---@return nil
function ReaderUI:switchDocument(new_file, seamless) end

---Handle open last document event
---@return nil
function ReaderUI:onOpenLastDoc() end

---Get current page number
---@return number Current page number
function ReaderUI:getCurrentPage() end

return ReaderUI
