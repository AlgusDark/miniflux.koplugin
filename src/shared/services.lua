local Services = {}

-- Import all service classes
local EntryService = require('features/entries/services/entry_service')
local QueueService = require('features/sync/services/queue_service')

---Build all services with proper dependency order
---@param miniflux Miniflux Plugin instance containing settings, api, and domain modules
---@return table Services container with entry and queue services
function Services.build(miniflux)
    local services = {}

    -- Phase 1: Business services (use domain modules)
    services.entry = EntryService:new({
        settings = miniflux.settings,
        feeds = miniflux.feeds,
        categories = miniflux.categories,
        entries = miniflux.entries,
        miniflux_api = miniflux.api,
        miniflux_plugin = miniflux,
    })

    -- Phase 2: Services dependent on other services
    services.queue = QueueService:new({
        entry_service = services.entry,
        miniflux_api = miniflux.api,
    })

    return services
end

return Services
