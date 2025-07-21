local Services = {}

-- Import all service classes
local EntryService = require('services/entry_service')
local CollectionService = require('services/collection_service')
local QueueService = require('services/queue_service')

---Build all services with proper dependency order
---@param miniflux Miniflux Plugin instance containing settings, api, and data_repository
---@return table Services container with entry, collection, queue services
function Services.build(miniflux)
    local services = {}

    -- Phase 1: Business services (use repository pattern)
    services.entry = EntryService:new({
        settings = miniflux.settings,
        data_repository = miniflux.data_repository,
        miniflux_api = miniflux.api,
        miniflux_plugin = miniflux,
    })

    services.collection = CollectionService:new({
        settings = miniflux.settings,
        data_repository = miniflux.data_repository,
        miniflux_api = miniflux.api,
    })

    -- Phase 2: Services dependent on other services
    services.queue = QueueService:new({
        entry_service = services.entry,
        miniflux_api = miniflux.api,
    })

    return services
end

return Services
