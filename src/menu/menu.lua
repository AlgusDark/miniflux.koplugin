local _ = require('gettext')

-- Import settings components
local ServerConfig = require('menu/settings/server_config')
local Entries = require('menu/settings/entries')
local SortOrder = require('menu/settings/sort_order')
local SortDirection = require('menu/settings/sort_direction')
local IncludeImages = require('menu/settings/include_images')
local MarkAsReadOnOpen = require('menu/settings/mark_as_read_on_open')
local CopyCss = require('menu/settings/copy_css')
local TestConnection = require('menu/settings/test_connection')
local ProxyImageDownloader = require('menu/settings/proxy_image_downloader')
local UpdateSettings = require('menu/settings/update_settings')
local ExportLogs = require('menu/settings/export_logs')

local Menu = {}

---Build the main menu structure for the Miniflux plugin
---@param plugin Miniflux The main plugin instance
---@return table menu_structure KOReader submenu structure
function Menu.build(plugin)
    return {
        text = _('Miniflux'),
        sub_item_table = {
            -- === BROWSER OPTIONS ===
            {
                text = _('Read entries'),
                help_text = _('Browse RSS entries'),
                callback = function()
                    local browser = plugin:createBrowser()
                    browser:open()
                end,
            },
            {
                text = _('Sync status changes'),
                help_text = _('Sync pending changes (entries, feeds, categories)'),
                callback = function()
                    if plugin.queue_service then
                        -- Use KOReader's standard network handling (same as translate)
                        local NetworkMgr = require('ui/network/manager')
                        NetworkMgr:runWhenOnline(function()
                            -- Show sync dialog after ensuring online connectivity
                            plugin.queue_service:processAllQueues()
                        end)
                    end
                end,
            },

            -- === SETTINGS SUBMENU ===
            {
                text = _('Settings'),
                separator = true,
                sub_item_table = {
                    -- === CONNECTION SETTINGS ===
                    ServerConfig.getMenuItem(plugin.settings),
                    TestConnection.getMenuItem(plugin.api),

                    -- === DISPLAY SETTINGS ===
                    Entries.getMenuItem(plugin.settings),
                    SortOrder.getMenuItem(plugin.settings),
                    SortDirection.getMenuItem(plugin.settings),
                    IncludeImages.getMenuItem(plugin.settings),
                    MarkAsReadOnOpen.getMenuItem(plugin.settings),
                    ProxyImageDownloader.getMenuItem(plugin.settings),
                    CopyCss.getMenuItem(plugin),

                    -- === UPDATE SETTINGS ===
                    UpdateSettings.getMenuItem(plugin),

                    -- === DEBUG ===
                    ExportLogs.getMenuItem(),
                },
            },
        },
    }
end

return Menu
