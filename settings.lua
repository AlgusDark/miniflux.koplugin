--[[--
Settings Manager for Miniflux Plugin

This module manages plugin settings and provides a centralized way to access configuration.

@module koplugin.miniflux.settings
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local MinifluxSettings = {}

function MinifluxSettings:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/miniflux.lua"
    self.settings = LuaSettings:open(self.settings_file)
    
    -- Set defaults
    self.defaults = {
        server_address = "",
        api_token = "",
        limit = 100,
        order = "published_at",
        direction = "desc",
        hide_read_entries = true,  -- Show only unread entries by default
        auto_mark_read = false,
        download_images = false,
        include_images = true,  -- Whether to download images when saving entries
        entry_font_size = 14,
        debug_logging = false
    }
    
    -- Load defaults for any missing settings
    self:loadDefaults()
end

function MinifluxSettings:get(key)
    local value = self.settings:readSetting(key)
    if value == nil then
        return self.defaults[key]
    end
    return value
end

function MinifluxSettings:set(key, value)
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function MinifluxSettings:toggle(key)
    local current_value = self:get(key)
    local new_value = not current_value
    self:set(key, new_value)
    return new_value
end

function MinifluxSettings:loadDefaults()
    -- Set defaults only if values don't exist
    for key, default_value in pairs(self.defaults) do
        if self.settings:readSetting(key) == nil then
            self.settings:saveSetting(key, default_value)
            logger.info("Setting default for", key, ":", default_value)
        end
    end
    
    self:save()
end

function MinifluxSettings:save()
    self.settings:flush()
    logger.info("Settings saved to:", self.settings_file)
end

function MinifluxSettings:getServerAddress()
    return self:get("server_address")
end

function MinifluxSettings:setServerAddress(address)
    self:set("server_address", address)
end

function MinifluxSettings:getApiToken()
    return self:get("api_token")
end

function MinifluxSettings:setApiToken(token)
    self:set("api_token", token)
end

function MinifluxSettings:getLimit()
    return self:get("limit")
end

function MinifluxSettings:setLimit(limit)
    self:set("limit", tonumber(limit) or 100)
end

function MinifluxSettings:getOrder()
    return self:get("order")
end

function MinifluxSettings:setOrder(order)
    local valid_orders = {
        "id", "status", "published_at", "category_title", "category_id"
    }
    
    for _, valid_order in ipairs(valid_orders) do
        if order == valid_order then
            self:set("order", order)
            return
        end
    end
    
    logger.warn("Invalid order specified:", order, "- using default")
    self:set("order", "published_at")
end

function MinifluxSettings:getDirection()
    return self:get("direction")
end

function MinifluxSettings:setDirection(direction)
    if direction == "asc" or direction == "desc" then
        self:set("direction", direction)
    else
        logger.warn("Invalid direction specified:", direction, "- using default")
        self:set("direction", "desc")
    end
end

function MinifluxSettings:getHideReadEntries()
    return self:get("hide_read_entries")
end

function MinifluxSettings:setHideReadEntries(hide)
    self:set("hide_read_entries", hide)
end

function MinifluxSettings:toggleHideReadEntries()
    return self:toggle("hide_read_entries")
end

function MinifluxSettings:getAutoMarkRead()
    return self:get("auto_mark_read")
end

function MinifluxSettings:setAutoMarkRead(auto_mark)
    self:set("auto_mark_read", auto_mark)
end

function MinifluxSettings:getIncludeImages()
    return self:get("include_images")
end

function MinifluxSettings:setIncludeImages(include)
    self:set("include_images", include)
end

function MinifluxSettings:toggleIncludeImages()
    return self:toggle("include_images")
end

function MinifluxSettings:isConfigured()
    local server = self:getServerAddress()
    local token = self:getApiToken()
    return server ~= "" and token ~= ""
end

function MinifluxSettings:export()
    return {
        server_address = self:getServerAddress(),
        api_token = self:getApiToken(),
        limit = self:getLimit(),
        order = self:getOrder(),
        direction = self:getDirection(),
        hide_read_entries = self:getHideReadEntries(),
        auto_mark_read = self:getAutoMarkRead()
    }
end

function MinifluxSettings:reset()
    logger.info("Resetting all Miniflux settings to defaults")
    self.settings:clear()
    self:loadDefaults()
end

function MinifluxSettings:getDebugLogging()
    return self:get("debug_logging")
end

function MinifluxSettings:setDebugLogging(debug)
    self:set("debug_logging", debug)
end

-- Initialize on module load
MinifluxSettings:init()

return MinifluxSettings 