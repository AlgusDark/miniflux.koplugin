--[[--
Main View for Miniflux Browser

Complete React-style component for main screen display.
Handles data fetching, menu building, and UI rendering.

@module miniflux.browser.views.main_view
--]]

local _ = require("gettext")
local ViewUtils = require("browser/views/view_utils")
local EntryEntity = require("entities/entry_entity")
local Debugger = require("utils/debugger")

local MainView = {}

---@alias MainViewConfig {repositories: MinifluxRepositories, settings: MinifluxSettings, onSelectUnread: function, onSelectFeeds: function, onSelectCategories: function, onSelectLocal: function}

---Complete main view component (React-style) - returns view data for browser rendering
---@param config MainViewConfig
---@return table|nil View data for browser rendering, or nil on error
function MainView.show(config)
    Debugger.enter("MainView.show")
    
    -- Check network connectivity
    local NetworkMgr = require("ui/network/manager")
    local is_online = NetworkMgr:isConnected()
    Debugger.debug("Network status: " .. tostring(is_online))
    
    -- Always get local entries count
    local local_entries = EntryEntity.getLocalEntries()
    local local_count = #local_entries
    Debugger.debug("Local entries count: " .. local_count)
    
    local counts = nil
    if is_online then
        Debugger.debug("Loading online data...")
        -- Try to load online data if connected
        local error_msg
        counts, error_msg = MainView.loadData({ repositories = config.repositories })
        if not counts then
            Debugger.warn("Online data failed, falling back to offline mode: " .. tostring(error_msg))
            -- Fall back to offline mode instead of showing error
            is_online = false
        else
            Debugger.debug("Online data loaded successfully")
        end
    else
        Debugger.debug("Offline mode - skipping online data load")
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
        }
    })

    -- Build clean title (status shown in subtitle now)
    local title = _("Miniflux")
    
    -- Build filter mode subtitle
    local filter_subtitle = ViewUtils.buildFilterModeSubtitle(config.settings)

    -- Return view data for browser to render
    return {
        title = title,
        items = main_items,
        page_state = nil,
        subtitle = filter_subtitle,
        is_root = true -- Signals browser to clear navigation history
    }
end

---Load initial data needed for main screen (internal helper)
---@param config {repositories: MinifluxRepositories}
---@return table|nil result, string|nil error
function MainView.loadData(config)
    Debugger.enter("MainView.loadData")
    local repositories = config.repositories

    local Notification = require("utils/notification")
    local loading_notification = Notification:info(_("Loading..."))

    -- Get unread count
    Debugger.debug("Getting unread count...")
    local unread_count, unread_err = repositories.entry:getUnreadCount()
    if unread_err then
        Debugger.error("Unread count failed: " .. tostring(unread_err.message))
        loading_notification:close()
        return nil, unread_err.message
    end
    Debugger.debug("Unread count: " .. tostring(unread_count))
    ---@cast unread_count -nil

    -- Get feeds count
    Debugger.debug("Getting feeds count...")
    local feeds_count, feeds_err = repositories.feed:getCount()
    if feeds_err then
        Debugger.error("Feeds count failed: " .. tostring(feeds_err.message))
        loading_notification:close()
        return nil, feeds_err.message
    end
    Debugger.debug("Feeds count: " .. tostring(feeds_count))
    ---@cast feeds_count -nil

    -- Get categories count
    Debugger.debug("Getting categories count...")
    local categories_count, categories_err = repositories.category:getCount()
    if categories_err then
        Debugger.error("Categories count failed: " .. tostring(categories_err.message))
        loading_notification:close()
        return nil, categories_err.message
    end
    Debugger.debug("Categories count: " .. tostring(categories_count))
    ---@cast categories_count -nil

    loading_notification:close()

    Debugger.exit("MainView.loadData", "success")
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

    if is_online then
        -- Online: Show all online options
        table.insert(items, {
            text = _("Unread"),
            mandatory = tostring(counts.unread_count or 0),
            callback = callbacks.onSelectUnread
        })
        table.insert(items, {
            text = _("Feeds"),
            mandatory = tostring(counts.feeds_count or 0),
            callback = callbacks.onSelectFeeds
        })
        table.insert(items, {
            text = _("Categories"),
            mandatory = tostring(counts.categories_count or 0),
            callback = callbacks.onSelectCategories
        })
    end

    -- Always show Local option if local entries exist
    if local_count > 0 then
        table.insert(items, {
            text = _("Local"),
            mandatory = tostring(local_count),
            callback = callbacks.onSelectLocal
        })
    end

    -- If offline and no local entries, show helpful message
    if not is_online and local_count == 0 then
        table.insert(items, {
            text = _("No offline content available"),
            mandatory = _("Connect to internet"),
            action_type = "no_action"
        })
    end

    return items
end

return MainView
