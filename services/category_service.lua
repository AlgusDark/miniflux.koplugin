local _ = require("gettext")
local T = require("ffi/util").template
local Notification = require("utils/notification")

-- **Category Service** - Handles category workflows and orchestration.
--
-- Coordinates between the Category repository and infrastructure services
-- to provide high-level category operations including notifications and
-- cache management.
---@class CategoryService
---@field settings MinifluxSettings Settings instance
---@field category_repository CategoryRepository Category repository instance
local CategoryService = {}

---Create a new CategoryService instance
---@param deps table Dependencies containing category_repository, settings
---@return CategoryService
function CategoryService:new(deps)
    local instance = {
        settings = deps.settings,
        category_repository = deps.category_repository,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Mark all entries in a category as read
---@param category_id number The category ID
---@return boolean success
function CategoryService:markAsRead(category_id)
    if not category_id or type(category_id) ~= "number" or category_id <= 0 then
        Notification:error(_("Invalid category ID"))
        return false
    end
    
    -- Show progress notification
    local progress_message = _("Marking category as read...")
    local success_message = _("Category marked as read")
    local error_message = _("Failed to mark category as read")
    
    -- Call API with dialog management
    local result, err = self.category_repository:markAsRead(category_id, {
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
        -- Invalidate category cache so next navigation shows correct counts
        self.category_repository:invalidateCache()
        return true
    end
end

return CategoryService