---@meta
---@module 'apps/filemanager/filemanager'

---FileManager handles file browsing and management operations
---@class FileManager : InputContainer
---@field name string Widget name
---@field title string Window title ("KOReader")
---@field active_widgets table[] Array of always active widgets
---@field root_path string Current root directory path
---@field clipboard string|nil Single file operation clipboard
---@field selected_files table|nil Selected files for group operations
---@field mv_bin string Path to mv binary
---@field cp_bin string Path to cp binary
---@field show_parent table Parent widget reference
---@field title_bar table Title bar widget
---@field file_chooser table File chooser widget
---@field focused_file string|nil Currently focused file
---@field file_dialog table|nil File operation dialog
---@field layout string File chooser layout mode
---@field file_dialog_added_buttons table|nil Additional dialog buttons
---@field cutfile boolean|nil Whether file is cut (for move operations)
---@field dimen table Widget dimensions
---@field tearing_down boolean|nil Whether widget is being torn down
---@field dithered boolean|nil Dithering state
---
--- Core FileManager modules (always present)
---@field screenshot table Screenshoter module
---@field menu table FileManagerMenu module
---@field history table FileManagerHistory module
---@field bookinfo table FileManagerBookInfo module
---@field collections table FileManagerCollection module
---@field filesearcher table FileManagerFileSearcher module
---@field folder_shortcuts table FileManagerShortcuts module
---@field languagesupport table LanguageSupport module
---@field dictionary table ReaderDictionary module
---@field wikipedia table ReaderWikipedia module
---@field devicestatus table ReaderDeviceStatus module
---@field devicelistener table DeviceListener module
---@field networklistener table NetworkListener module
---
--- Dynamic plugin modules (registered at runtime)
---@field [string] any Allow access to dynamically registered plugin modules
local FileManager = {}

---Register a module with the FileManager
---@param name string Module name (will be prefixed with "filemanager")
---@param ui_module table Module instance to register
---@param always_active? boolean Whether module should be always active
---@return nil
function FileManager:registerModule(name, ui_module, always_active) end

---Set rotation mode
---@return nil
function FileManager:setRotationMode() end

---Handle set rotation mode event
---@param mode string Rotation mode
---@return nil
function FileManager:onSetRotationMode(mode) end

---Initialize gesture listener
---@return nil
function FileManager:initGesListener() end

---Handle set dimensions event
---@param dimen table New dimensions
---@return nil
function FileManager:onSetDimensions(dimen) end

---Update title bar path display
---@param path string Directory path
---@return nil
function FileManager:updateTitleBarPath(path) end

---Setup the layout
---@return nil
function FileManager:setupLayout() end

---Register key events
---@return nil
function FileManager:registerKeyEvents() end

---Initialize the FileManager
---@return nil
function FileManager:init() end

---Handle swipe gesture on FileManager
---@param ges table Gesture data
---@return boolean Event handled
function FileManager:onSwipeFM(ges) end

---Add buttons to file dialog
---@param row_id string Row identifier
---@param row_func function Row function
---@return nil
function FileManager:addFileDialogButtons(row_id, row_func) end

---Remove buttons from file dialog
---@param row_id string Row identifier
---@return nil
function FileManager:removeFileDialogButtons(row_id) end

---Handle show plus menu event
---@return nil
function FileManager:onShowPlusMenu() end

---Toggle select mode
---@param do_refresh? boolean Whether to refresh display
---@return nil
function FileManager:onToggleSelectMode(do_refresh) end

---Handle plus button tap
---@return nil
function FileManager:tapPlus() end

---Reinitialize with new path
---@param path string New directory path
---@param focused_file? string File to focus on
---@return nil
function FileManager:reinit(path, focused_file) end

---Handle close event
---@return nil
function FileManager:onClose() end

---Handle flush settings event
---@return nil
function FileManager:onFlushSettings() end

---Handle close widget event
---@return nil
function FileManager:onCloseWidget() end

---Handle showing reader event
---@return nil
function FileManager:onShowingReader() end

---Handle setup show reader event
---@return nil
function FileManager:onSetupShowReader() end

---Handle refresh event
---@return nil
function FileManager:onRefresh() end

---Handle home button event
---@return boolean Event handled
function FileManager:onHome() end

---Set home directory
---@param path string Home directory path
---@return nil
function FileManager:setHome(path) end

---Open a random file from directory
---@param dir string Directory path
---@param unopened_only? boolean Only unopened files
---@return nil
function FileManager:openRandomFile(dir, unopened_only) end

---Copy file to clipboard
---@param file string File path
---@return nil
function FileManager:copyFile(file) end

---Cut file to clipboard
---@param file string File path
---@return nil
function FileManager:cutFile(file) end

---Paste file from clipboard
---@param file string Destination path
---@return nil
function FileManager:pasteFileFromClipboard(file) end

---Show copy/move selected files dialog
---@param close_callback function Callback after close
---@return nil
function FileManager:showCopyMoveSelectedFilesDialog(close_callback) end

---Paste selected files
---@param overwrite boolean Whether to overwrite existing files
---@return nil
function FileManager:pasteSelectedFiles(overwrite) end

---Create a new folder
---@return nil
function FileManager:createFolder() end

---Show delete file confirmation dialog
---@param filepath string File path to delete
---@param post_delete_callback? function Callback after deletion
---@param pre_delete_callback? function Callback before deletion
---@return nil
function FileManager:showDeleteFileDialog(filepath, post_delete_callback, pre_delete_callback) end

---Delete a file
---@param file string File path
---@param is_file boolean Whether it's a file (vs directory)
---@return nil
function FileManager:deleteFile(file, is_file) end

---Delete selected files
---@return nil
function FileManager:deleteSelectedFiles() end

---Show rename file dialog
---@param file string File path
---@param is_file boolean Whether it's a file (vs directory)
---@return nil
function FileManager:showRenameFileDialog(file, is_file) end

---Rename a file
---@param file string Original file path
---@param basename string New basename
---@param is_file boolean Whether it's a file (vs directory)
---@return nil
function FileManager:renameFile(file, basename, is_file) end

---Show files in directory
---@param path string Directory path
---@param focused_file? string File to focus on
---@param selected_files? table Files to select
---@return nil
function FileManager:showFiles(path, focused_file, selected_files) end

---Move file from one location to another
---@param from string Source path
---@param to string Destination path
---@return nil
function FileManager:moveFile(from, to) end

---Copy file from one location to another
---@param from string Source path
---@param to string Destination path
---@return nil
function FileManager:copyFileFromTo(from, to) end

---Recursively copy directory
---@param from string Source path
---@param to string Destination path
---@return nil
function FileManager:copyRecursive(from, to) end

---Handle show folder menu event
---@return nil
function FileManager:onShowFolderMenu() end

---Show list of selected files
---@return nil
function FileManager:showSelectedFilesList() end

---Show open with dialog
---@param file string File path
---@return nil
function FileManager:showOpenWithDialog(file) end

---Open file with specified provider
---@param file string File path
---@param provider? table Document provider
---@param doc_caller_callback? function Document caller callback
---@param aux_caller_callback? function Auxiliary caller callback
---@return nil
function FileManager:openFile(file, provider, doc_caller_callback, aux_caller_callback) end

---Handle set display mode event
---@param mode string Display mode
---@return nil
function FileManager:onSetDisplayMode(mode) end

---Handle set sort by event
---@param mode string Sort mode
---@return nil
function FileManager:onSetSortBy(mode) end

---Handle set reverse sorting event
---@param toggle boolean Toggle state
---@return nil
function FileManager:onSetReverseSorting(toggle) end

---Handle set mixed sorting event
---@param toggle boolean Toggle state
---@return nil
function FileManager:onSetMixedSorting(toggle) end

---Open next or previous file in folder
---@param prev boolean Whether to go to previous (vs next)
---@return nil
function FileManager:onOpenNextOrPreviousFileInFolder(prev) end

return FileManager
