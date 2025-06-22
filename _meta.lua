---@class MinifluxMeta
---@field name string Plugin name identifier
---@field fullname string Localized display name
---@field description string Localized plugin description

local _ = require("gettext")

---@type MinifluxMeta
return {
    name = "miniflux",
    fullname = _("Miniflux"),
    description = _([[Read RSS entries from your Miniflux server.]]),
}

