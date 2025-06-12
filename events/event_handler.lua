--[[--
Event Handler Module

This module handles dispatcher action registration and event processing
for the Miniflux plugin, following the single responsibility principle.

@module koplugin.miniflux.events.event_handler
--]]--

local Dispatcher = require("dispatcher")
local _ = require("gettext")

---@class EventHandler
local EventHandler = {}

---Create a new event handler
---@return EventHandler
function EventHandler:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

---Register all dispatcher actions for the plugin
---@return nil
function EventHandler:registerDispatcherActions()
    Dispatcher:registerAction("miniflux_read_entries", {
        category = "none",
        event = "ReadMinifluxEntries",
        title = _("Read Miniflux entries"),
        general = true,
    })
end

---Handle the read entries dispatcher event
---@param plugin_instance table The main plugin instance
---@return nil
function EventHandler:onReadMinifluxEntries(plugin_instance)
    if plugin_instance.browser_launcher then
        plugin_instance.browser_launcher:showMainScreen()
    end
end

---Initialize event handling for the plugin
---@param plugin_instance table The main plugin instance
---@return nil
function EventHandler:initializeEvents(plugin_instance)
    -- Register dispatcher actions
    self:registerDispatcherActions()
    
    -- Set up event handlers on the plugin instance
    plugin_instance.onReadMinifluxEntries = function()
        self:onReadMinifluxEntries(plugin_instance)
    end
end

return EventHandler 