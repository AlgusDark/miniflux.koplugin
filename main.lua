--[[--
Miniflux Plugin for KOReader

This plugin provides integration with Miniflux RSS reader.
This main file acts as a coordinator, delegating to specialized modules.

@module koplugin.miniflux
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

-- Import specialized modules
local PluginInitializer = require("initialization/plugin_initializer")
local MenuManager = require("menu/menu_manager")
local EventHandler = require("events/event_handler")

---@class Miniflux : WidgetContainer
---@field name string Plugin name identifier
---@field is_doc_only boolean Whether plugin is document-only
---@field initializer PluginInitializer Plugin initialization manager
---@field menu_manager MenuManager Menu construction manager
---@field event_handler EventHandler Event handling manager
---@field download_dir string Full path to download directory
---@field settings SettingsManager Settings manager instance
---@field api MinifluxAPI API client instance
---@field settings_dialogs SettingsDialogs Settings UI dialogs instance
---@field browser_launcher BrowserLauncher Browser launcher instance
local Miniflux = WidgetContainer:extend({
    name = "miniflux",
    is_doc_only = false,
})

---Initialize the plugin by delegating to specialized modules
---@return nil
function Miniflux:init()
    logger.info("Initializing Miniflux plugin")
    
    -- Create specialized managers
    self.initializer = PluginInitializer:new()
    self.menu_manager = MenuManager:new()
    self.event_handler = EventHandler:new()
    
    -- Initialize plugin components
    local init_success = self.initializer:initializePlugin(self)
    if not init_success then
        logger.err("Failed to initialize Miniflux plugin")
        return
    end
    
    -- Set up event handling
    self.event_handler:initializeEvents(self)
    
    -- Register with KOReader menu system
    self.ui.menu:registerToMainMenu(self)
    
    logger.info("Miniflux plugin initialization complete")
end

---Add Miniflux items to the main menu (called by KOReader)
---@param menu_items table The main menu items table
---@return nil
function Miniflux:addToMainMenu(menu_items)
    self.menu_manager:addToMainMenu(menu_items, self)
end

---Handle dispatcher events (method required by KOReader)
---@return nil
function Miniflux:onDispatcherRegisterActions()
    -- Delegate to event handler
    self.event_handler:registerDispatcherActions()
end

return Miniflux
