--[[--
Display Settings Module

This module handles UI display preferences like hiding read entries, including images,
and other visual configuration options.

@module koplugin.miniflux.settings.display_settings
--]]--

local BaseSettings = require("settings/base_settings")
local Enums = require("settings/enums")

---@class DisplaySettings : BaseSettings
---@field settings LuaSettings The injected settings storage instance
local DisplaySettings = {}
setmetatable(DisplaySettings, {__index = BaseSettings})

---Create a new display settings instance
---@param o? table Optional initialization table
---@return DisplaySettings
function DisplaySettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Get hide read entries setting
---@return boolean Whether to hide read entries
function DisplaySettings:getHideReadEntries()
    return self:get("hide_read_entries", Enums.DEFAULTS.hide_read_entries)
end

---Set hide read entries setting
---@param hide boolean Whether to hide read entries
---@return boolean True if successfully set
function DisplaySettings:setHideReadEntries(hide)
    local function isValidBoolean(val)
        return type(val) == "boolean"
    end
    
    return self:setWithValidation(
        "hide_read_entries", 
        hide, 
        isValidBoolean, 
        Enums.DEFAULTS.hide_read_entries
    )
end

---Toggle hide read entries setting
---@return boolean The new value after toggle
function DisplaySettings:toggleHideReadEntries()
    return self:toggle("hide_read_entries", Enums.DEFAULTS.hide_read_entries)
end

---Get include images setting
---@return boolean Whether to include images when downloading
function DisplaySettings:getIncludeImages()
    return self:get("include_images", Enums.DEFAULTS.include_images)
end

---Set include images setting
---@param include boolean Whether to include images when downloading
---@return boolean True if successfully set
function DisplaySettings:setIncludeImages(include)
    local function isValidBoolean(val)
        return type(val) == "boolean"
    end
    
    return self:setWithValidation(
        "include_images", 
        include, 
        isValidBoolean, 
        Enums.DEFAULTS.include_images
    )
end

---Toggle include images setting
---@return boolean The new value after toggle
function DisplaySettings:toggleIncludeImages()
    return self:toggle("include_images", Enums.DEFAULTS.include_images)
end

---Get auto mark read setting
---@return boolean Whether to auto mark entries as read when opened
function DisplaySettings:getAutoMarkRead()
    return self:get("auto_mark_read", Enums.DEFAULTS.auto_mark_read)
end

---Set auto mark read setting
---@param auto_mark boolean Whether to auto mark entries as read when opened
---@return boolean True if successfully set
function DisplaySettings:setAutoMarkRead(auto_mark)
    local function isValidBoolean(val)
        return type(val) == "boolean"
    end
    
    return self:setWithValidation(
        "auto_mark_read", 
        auto_mark, 
        isValidBoolean, 
        Enums.DEFAULTS.auto_mark_read
    )
end

---Toggle auto mark read setting
---@return boolean The new value after toggle
function DisplaySettings:toggleAutoMarkRead()
    return self:toggle("auto_mark_read", Enums.DEFAULTS.auto_mark_read)
end

---Get entry font size setting
---@return number Entry font size
function DisplaySettings:getEntryFontSize()
    return self:get("entry_font_size", Enums.DEFAULTS.entry_font_size)
end

---Set entry font size with validation
---@param size number The font size
---@return boolean True if successfully set
function DisplaySettings:setEntryFontSize(size)
    local function isValidFontSize(sz)
        return type(sz) == "number" and sz >= 8 and sz <= 32
    end
    
    -- Convert to number if it's a string
    if type(size) == "string" then
        size = tonumber(size)
    end
    
    return self:setWithValidation(
        "entry_font_size", 
        size, 
        isValidFontSize, 
        Enums.DEFAULTS.entry_font_size
    )
end

---Get download images setting (legacy support)
---@return boolean Whether to download images
function DisplaySettings:getDownloadImages()
    return self:get("download_images", Enums.DEFAULTS.download_images)
end

---Set download images setting (legacy support)
---@param download boolean Whether to download images
---@return boolean True if successfully set
function DisplaySettings:setDownloadImages(download)
    local function isValidBoolean(val)
        return type(val) == "boolean"
    end
    
    return self:setWithValidation(
        "download_images", 
        download, 
        isValidBoolean, 
        Enums.DEFAULTS.download_images
    )
end

---Get all display settings as a table
---@return table<string, any> Map of display settings
function DisplaySettings:getAllDisplaySettings()
    return {
        hide_read_entries = self:getHideReadEntries(),
        include_images = self:getIncludeImages(),
        auto_mark_read = self:getAutoMarkRead(),
        entry_font_size = self:getEntryFontSize(),
        download_images = self:getDownloadImages()
    }
end

---Set all display settings at once
---@param settings table<string, any> Map of display settings
---@return boolean True if all settings were set successfully
function DisplaySettings:setAllDisplaySettings(settings)
    local success = true
    
    if settings.hide_read_entries ~= nil then
        success = success and self:setHideReadEntries(settings.hide_read_entries)
    end
    
    if settings.include_images ~= nil then
        success = success and self:setIncludeImages(settings.include_images)
    end
    
    if settings.auto_mark_read ~= nil then
        success = success and self:setAutoMarkRead(settings.auto_mark_read)
    end
    
    if settings.entry_font_size then
        success = success and self:setEntryFontSize(settings.entry_font_size)
    end
    
    if settings.download_images ~= nil then
        success = success and self:setDownloadImages(settings.download_images)
    end
    
    return success
end

---Reset display settings to defaults
---@return boolean True if successfully reset
function DisplaySettings:resetToDefaults()
    local success = true
    success = success and self:setHideReadEntries(Enums.DEFAULTS.hide_read_entries)
    success = success and self:setIncludeImages(Enums.DEFAULTS.include_images)
    success = success and self:setAutoMarkRead(Enums.DEFAULTS.auto_mark_read)
    success = success and self:setEntryFontSize(Enums.DEFAULTS.entry_font_size)
    success = success and self:setDownloadImages(Enums.DEFAULTS.download_images)
    return success
end

return DisplaySettings 