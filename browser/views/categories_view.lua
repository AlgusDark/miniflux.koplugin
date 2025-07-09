--[[--
Categories View for Miniflux Browser

Complete React-style component for categories display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.categories_view
--]]

local ViewUtils = require("browser/views/view_utils")
local _ = require("gettext")

local CategoriesView = {}

---@alias CategoriesViewConfig {repositories: MinifluxRepositories, settings: MinifluxSettings, page_state?: number, onSelectItem: function}

---Complete categories view component (React-style) - returns view data for rendering
---@param config CategoriesViewConfig
---@return table|nil View data for browser rendering, or nil on error
function CategoriesView.show(config)
    -- Fetch data with API-level dialog management
    local categories, err = config.repositories.category:getAll({
        dialogs = {
            loading = { text = _("Fetching categories...") },
            error = { text = _("Failed to fetch categories"), timeout = 5 }
        }
    })

    if err then
        return nil -- Error dialog already shown by API system
    end
    ---@cast categories -nil

    -- Generate menu items using internal builder
    local menu_items = CategoriesView.buildItems({
        categories = categories,
        onSelectItem = config.onSelectItem
    })

    local hide_read = config.settings.hide_read_entries
    local subtitle = ViewUtils.buildSubtitle({
        count = #categories,
        hide_read = hide_read,
        item_type = "categories"
    })

    -- Build title with status indicator using ViewUtils
    local title = ViewUtils.addStatusIndicator(_("Categories"), config.settings)

    -- Return view data for browser to render
    return {
        title = title,
        items = menu_items,
        page_state = config.page_state,
        subtitle = subtitle
    }
end

---Build categories menu items (internal helper)
---@param config {categories: table[], onSelectItem: function}
---@return table[] Menu items for categories view
function CategoriesView.buildItems(config)
    local categories = config.categories or {}
    local onSelectItem = config.onSelectItem

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
                onSelectItem(category.id)
            end
        })
    end

    -- Sort by unread priority
    ViewUtils.sortByUnreadPriority(menu_items)

    return menu_items
end

return CategoriesView
