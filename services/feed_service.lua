local _ = require("gettext")
local T = require("ffi/util").template
local Notification = require("utils/notification")

-- **Feed Service** - Handles feed workflows and orchestration.
--
-- Coordinates between the Feed repository and infrastructure services
-- to provide high-level feed operations including notifications and
-- cache management.
---@class FeedService
---@field settings MinifluxSettings Settings instance
---@field feed_repository FeedRepository Feed repository instance
---@field category_repository CategoryRepository Category repository for cross-invalidation
local FeedService = {}

---@class FeedServiceDeps
---@field feed_repository FeedRepository
---@field category_repository CategoryRepository  
---@field settings MinifluxSettings

---Create a new FeedService instance
---@param deps FeedServiceDeps Dependencies containing repositories and settings
---@return FeedService
function FeedService:new(deps)
    local instance = {
        settings = deps.settings,
        feed_repository = deps.feed_repository,
        category_repository = deps.category_repository,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Mark all entries in a feed as read
---@param feed_id number The feed ID
---@return boolean success
function FeedService:markAsRead(feed_id)
    if not feed_id or type(feed_id) ~= "number" or feed_id <= 0 then
        Notification:error(_("Invalid feed ID"))
        return false
    end
    
    -- Show progress notification
    local progress_message = _("Marking feed as read...")
    local success_message = _("Feed marked as read")
    local error_message = _("Failed to mark feed as read")
    
    -- Call API with dialog management
    local result, err = self.feed_repository:markAsRead(feed_id, {
        dialogs = {
            loading = { text = progress_message },
            success = { text = success_message },
            error = { text = error_message }
        }
    })
    
    if err then
        -- Error dialog already shown by API system
        return false
    else
        -- Invalidate both feed and category caches so next navigation shows correct counts
        self.feed_repository:invalidateCache()
        self.category_repository:invalidateCache()
        return true
    end
end

return FeedService