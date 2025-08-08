local _ = require('gettext')

---@class PluginMeta
---@field name string Plugin internal name
---@field fullname string Plugin display name
---@field description string Plugin description
---@field version string Plugin version (semantic versioning)
---@field author string Plugin author
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name

return {
    name = 'miniflux',
    fullname = _('Miniflux'),
    description = _([[Read RSS entries from your Miniflux server.]]),
    version = '0.0.9',
    author = 'Algus Dark',
    repo_owner = 'AlgusDark',
    repo_name = 'miniflux.koplugin',
}
