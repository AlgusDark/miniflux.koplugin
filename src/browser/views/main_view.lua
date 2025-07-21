--[[--
Main View for Miniflux Browser

Complete React-style component for main screen display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.main_view
--]]

local _ = require('gettext')
local ViewUtils = require('browser/views/view_utils')
local EntryEntity = require('entities/entry_entity')

local MainView = {}

---@alias MainViewConfig {entry_service: EntryService, collection_service: CollectionService, settings: MinifluxSettings, onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function, onSelectLocal: function}

---Complete main view component (React-style) - returns view data for browser rendering
---@param config MainViewConfig
---@return table|nil View data for browser rendering, or nil on error
function MainView.show(config)
    -- Check network connectivity
    local NetworkMgr = require('ui/network/manager')
    local is_online = NetworkMgr:isOnline()

    -- Always get local entries count
    local local_entries = EntryEntity.getLocalEntries()
    local local_count = #local_entries

    local counts = nil
    if is_online then
        -- Try to load online data if connected
        local _error_msg
        counts, _error_msg = MainView.loadData({
            entry_service = config.entry_service,
            collection_service = config.collection_service,
        })
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

---Load initial data needed for main screen (internal helper)
---@param config {entry_service: EntryService, collection_service: CollectionService}
---@return table|nil result, string|nil error
function MainView.loadData(config)
    local entry_service = config.entry_service
    local collection_service = config.collection_service

    local Notification = require('utils/notification')
    local loading_notification = Notification:info(_('Loading...'))

    -- Get unread count
    local unread_count, unread_err = entry_service:getUnreadCount()
    if unread_err then
        loading_notification:close()
        return nil, unread_err.message
    end
    ---@cast unread_count -nil

    -- Get feeds count
    local feeds_count, feeds_err = collection_service:getFeedCount()
    if feeds_err then
        loading_notification:close()
        return nil, feeds_err.message
    end
    ---@cast feeds_count -nil

    -- Get categories count
    local categories_count, categories_err = collection_service:getCategoryCount()
    if categories_err then
        loading_notification:close()
        return nil, categories_err.message
    end
    ---@cast categories_count -nil

    loading_notification:close()

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
