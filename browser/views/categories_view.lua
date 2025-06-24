--[[--
Categories View for Miniflux Browser

Handles categories list view construction.

@module miniflux.browser.views.categories_view
--]]

local ViewUtils = require("browser/views/view_utils")
local _ = require("gettext")

local CategoriesView = {}

---Build categories menu items
---@param config {categories: table[], on_select_callback: function}
---@return table[] Menu items for categories view
function CategoriesView.buildItems(config)
    local categories = config.categories or {}
    local on_select_callback = config.on_select_callback

    local menu_items = {}

    for _, category in ipairs(categories) do
        local category_title = category.title or _("Untitled Category")
        local unread_count = category.total_unread or 0

        table.insert(menu_items, {
            text = category_title,
            mandatory = string.format("(%d)", unread_count),
            action_type = "category_entries",
            unread_count = unread_count,
            category_data = { id = category.id, title = category_title, unread_count = unread_count },
            callback = function()
                on_select_callback(category.id)
            end
        })
    end

    -- Sort by unread priority
    ViewUtils.sortByUnreadPriority(menu_items)

    return menu_items
end

return CategoriesView
