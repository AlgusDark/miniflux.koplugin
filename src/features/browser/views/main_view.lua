--[[--
Main View for Miniflux Browser

Complete React-style component for main screen display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.main_view
--]]

local _ = require('gettext')
local ViewUtils = require('features/browser/views/view_utils')
local EntryCollections = require('domains/utils/entry_collections')

local MainView = {}

---@alias MainViewConfig {miniflux: Miniflux, settings: MinifluxSettings, onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function, onSelectLocal: function}

---Complete main view component (React-style) - returns view data for browser rendering
---@param config MainViewConfig
---@return table|nil View data for browser rendering, or nil on error
function MainView.show(config)
    -- Check network connectivity
    local NetworkMgr = require('ui/network/manager')
    local is_online = NetworkMgr:isOnline()

    -- Always get local entries count
    local local_entries = EntryCollections.getLocalEntries()
    local local_count = #local_entries

    local counts = nil
    if is_online then
        -- Try to load online data if connected using loader pattern
        local _error_msg
        counts, _error_msg = MainView.loadData(config.miniflux)
        if not counts then
            -- Fall back to offline mode instead of showing error
            is_online = false
        end
    end

    -- Generate menu items using internal builder
    local main_items = MainView.buildItems({
        counts = counts, -- Will be nil if offline
        local_count = local_count,
        is_online = is_online,
        callbacks = {
            onSelectUnread = config.onSelectUnread,
            onSelectFeeds = config.onSelectFeeds,
            onSelectCategories = config.onSelectCategories,
            onSelectLocal = config.onSelectLocal,
        },
    })

    -- Build clean title (status shown in subtitle now)
    local title = _('Miniflux')

    -- Build filter mode subtitle
    local filter_subtitle = ViewUtils.buildFilterModeSubtitle(config.settings)

    -- Return view data for browser to render
    return {
        title = title,
        items = main_items,
        page_state = nil,
        subtitle = filter_subtitle,
        is_root = true, -- Signals browser to clear navigation history
    }
end

---Load initial data needed for main screen using domain loader pattern
---@param miniflux Miniflux Plugin instance with domain modules
---@return table|nil result, string|nil error
function MainView.loadData(miniflux)
    local UIManager = require('ui/uimanager')
    local InfoMessage = require('ui/widget/infomessage')
    local loading_notification = InfoMessage:new({
        text = _('Loading...'),
    })
    UIManager:show(loading_notification)

    -- Get unread count from entries domain
    local unread_count, unread_err = miniflux.entries:getUnreadCount()
    if unread_err then
        UIManager:close(loading_notification)
        return nil, unread_err.message
    end
    ---@cast unread_count -nil

    -- Get feeds count from feeds domain
    local feeds_count, feeds_err = miniflux.feeds:getFeedCount()
    if feeds_err then
        UIManager:close(loading_notification)
        return nil, feeds_err.message
    end
    ---@cast feeds_count -nil

    -- Get categories count from categories domain
    local categories_count, categories_err = miniflux.categories:getCategoryCount()
    if categories_err then
        UIManager:close(loading_notification)
        return nil, categories_err.message
    end
    ---@cast categories_count -nil

    UIManager:close(loading_notification)

    return {
        unread_count = unread_count or 0,
        feeds_count = feeds_count or 0,
        categories_count = categories_count or 0,
    }
end

---Build main menu items (internal helper)
---@param config {counts?: table, local_count: number, is_online: boolean, callbacks: {onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function, onSelectLocal: function}}
---@return table[] Menu items for main screen
function MainView.buildItems(config)
    local counts = config.counts
    local local_count = config.local_count
    local is_online = config.is_online
    local callbacks = config.callbacks

    local items = {}

    if is_online and counts then
        -- Online: Show all online options
        table.insert(items, {
            text = _('Unread'),
            mandatory = tostring(counts.unread_count or 0),
            callback = callbacks.onSelectUnread,
        })
        table.insert(items, {
            text = _('Feeds'),
            mandatory = tostring(counts.feeds_count or 0),
            callback = callbacks.onSelectFeeds,
        })
        table.insert(items, {
            text = _('Categories'),
            mandatory = tostring(counts.categories_count or 0),
            callback = callbacks.onSelectCategories,
        })
    end

    -- Always show Local option if local entries exist
    if local_count > 0 then
        table.insert(items, {
            text = _('Local'),
            mandatory = tostring(local_count),
            callback = callbacks.onSelectLocal,
        })
    end

    -- If offline and no local entries, show helpful message
    if not is_online and local_count == 0 then
        table.insert(items, {
            text = _('No offline content available'),
            mandatory = _('Connect to internet'),
            action_type = 'no_action',
        })
    end

    return items
end

return MainView
