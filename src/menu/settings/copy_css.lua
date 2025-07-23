local ConfirmBox = require('ui/widget/confirmbox')
local DataStorage = require('datastorage')
local UIManager = require('ui/uimanager')
local lfs = require('libs/libkoreader-lfs')
local Notification = require('shared/utils/notification')
local _ = require('gettext')

-- **Copy CSS Settings** - Handles copying the plugin's CSS file to the
-- styletweaks directory for use with KOReader's styletweaks functionality.
local CopyCss = {}

---Get the menu item for CSS copying functionality
---@param plugin table Plugin instance with path property
---@return table Menu item configuration
function CopyCss.getMenuItem(plugin)
    return {
        text = _('Copy miniflux.css'),
        keep_menu_open = true,
        callback = function()
            CopyCss.copyCssToStyletweaks(plugin)
        end,
    }
end

---Copy CSS file to styletweaks directory
---@param plugin table Plugin instance with path property
---@return nil
function CopyCss.copyCssToStyletweaks(plugin)
    -- Source CSS file in plugin's assets folder
    local source_css = plugin.path .. '/assets/reader.css'

    -- Destination in styletweaks directory
    local styletweaks_dir = DataStorage:getDataDir() .. '/styletweaks'
    local dest_css = styletweaks_dir .. '/miniflux.css'

    -- Create styletweaks directory if it doesn't exist
    local styletweaks_created = false
    if lfs.attributes(styletweaks_dir, 'mode') ~= 'directory' then
        local success = lfs.mkdir(styletweaks_dir)
        if success then
            styletweaks_created = true
        else
            Notification:error(_('Failed to create styletweaks directory'))
            return
        end
    end

    -- Check if source file exists
    if lfs.attributes(source_css, 'mode') ~= 'file' then
        Notification:error(_('Source CSS file not found'))
        return
    end

    -- If we created the styletweaks directory, inform the user
    if styletweaks_created then
        Notification:info(_('Created styletweaks directory'))
    end

    -- Check if destination file already exists
    if lfs.attributes(dest_css, 'mode') == 'file' then
        UIManager:show(ConfirmBox:new({
            text = _('miniflux.css already exists in styletweaks. Do you want to overwrite it?'),
            ok_text = _('Overwrite'),
            ok_callback = function()
                CopyCss._performCSSCopy(source_css, dest_css)
            end,
            cancel_text = _('Cancel'),
        }))
    else
        -- File doesn't exist, proceed with copy
        CopyCss._performCSSCopy(source_css, dest_css)
    end
end

---Perform the actual CSS file copy operation
---@param source_css string Path to source CSS file
---@param dest_css string Path to destination CSS file
---@return nil
function CopyCss._performCSSCopy(source_css, dest_css)
    -- Copy the CSS file
    local source_file = io.open(source_css, 'rb')
    if not source_file then
        Notification:error(_('Could not open source CSS file'))
        return
    end

    local dest_file = io.open(dest_css, 'wb')
    if not dest_file then
        source_file:close()
        Notification:error(_('Could not create destination CSS file'))
        return
    end

    -- Copy content
    local content = source_file:read('*all')
    dest_file:write(content)

    source_file:close()
    dest_file:close()

    Notification:success(_('miniflux.css successfully copied to styletweaks'))
end

return CopyCss
