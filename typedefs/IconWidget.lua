--[[--
EmmyLua type definitions for IconWidget

@meta koplugin.miniflux.typedefs.IconWidget
--]]

---@class IconWidgetOptions : ImageWidgetOptions
---@field icon? string Icon filename (without path or extension)
---@field width? number Icon width (default: scaled icon size)
---@field height? number Icon height (default: scaled icon size)
---@field alpha? boolean Whether to keep alpha channel (default: false)
---@field is_icon? boolean Whether this is an icon (default: true, avoids dithering)

---@class IconWidget : ImageWidget
---@field icon string Icon filename
---@field width number Icon width
---@field height number Icon height
---@field alpha boolean Whether alpha channel is preserved
---@field is_icon boolean Whether this is treated as an icon
---@field file string Path to the icon file
---@field extend fun(self: IconWidget, o: IconWidgetOptions): IconWidget Extend IconWidget class
---@field new fun(self: IconWidget, o: IconWidgetOptions): IconWidget Create new IconWidget
---@field init fun(self: IconWidget): nil Initialize icon widget (resolves icon path)

---@class ImageWidgetOptions
---@field file? string Image file path
---@field image? table Image data
---@field width? number Image width
---@field height? number Image height

---@class ImageWidget
---@field file string Image file path
---@field width number Image width
---@field height number Image height
