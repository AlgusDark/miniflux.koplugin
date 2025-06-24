--[[--
Navigation Context Manager

This module manages the global navigation context for entry browsing.
It tracks what the user is currently browsing (feed, category, or global)
and provides this context for navigation between entries.

@module miniflux.browser.utils.navigation_context
--]]

local NavigationContext = {}

-- Global navigation context state
local _current_context = {
    type = nil,        -- "feed", "category", or "global"
    feed_id = nil,     -- Current feed ID if browsing a feed
    category_id = nil, -- Current category ID if browsing a category
    entry_id = nil,    -- Currently viewed entry ID
    timestamp = nil,   -- When context was set (for debugging)
}

---Set navigation context for entry browsing
---@param entry_id number The entry ID being opened
---@param context? {type: "feed"|"category", id: number} Navigation context (nil = global)
---@return nil
function NavigationContext.setContext(entry_id, context)
    if not context then
        -- Global context (unread entries)
        _current_context = {
            type = "global",
            feed_id = nil,
            category_id = nil,
            entry_id = entry_id,
            timestamp = os.time(),
        }
    elseif context.type == "feed" then
        -- Feed-specific context
        _current_context = {
            type = "feed",
            feed_id = context.id,
            category_id = nil,
            entry_id = entry_id,
            timestamp = os.time(),
        }
    elseif context.type == "category" then
        -- Category-specific context
        _current_context = {
            type = "category",
            feed_id = nil,
            category_id = context.id,
            entry_id = entry_id,
            timestamp = os.time(),
        }
    else
        -- Fallback to global context for unknown types
        _current_context = {
            type = "global",
            feed_id = nil,
            category_id = nil,
            entry_id = entry_id,
            timestamp = os.time(),
        }
    end
end

---Update the current entry ID without changing the browsing context
---@param entry_id number The new entry ID being viewed
---@return nil
function NavigationContext.updateCurrentEntry(entry_id)
    _current_context.entry_id = entry_id
    _current_context.timestamp = os.time()
end

---Get the current navigation context
---@return {type: string?, feed_id: number?, category_id: number?, entry_id: number?, timestamp: number?} Current context
function NavigationContext.getCurrentContext()
    -- Return a copy to prevent external modification
    return {
        type = _current_context.type,
        feed_id = _current_context.feed_id,
        category_id = _current_context.category_id,
        entry_id = _current_context.entry_id,
        timestamp = _current_context.timestamp,
    }
end

---Get API options based on current navigation context
---@param base_options ApiOptions Base API options from settings
---@return ApiOptions Context-aware options with feed_id/category_id filters
function NavigationContext.getContextAwareOptions(base_options)
    local options = {}

    -- Copy base options
    for k, v in pairs(base_options) do
        options[k] = v
    end

    -- Add context-aware filtering based on current browsing context
    if _current_context.type == "feed" and _current_context.feed_id then
        options.feed_id = _current_context.feed_id
    elseif _current_context.type == "category" and _current_context.category_id then
        options.category_id = _current_context.category_id
    end
    -- For "global" type, no additional filtering (browse all entries)

    return options
end

---Check if we have a valid navigation context
---@return boolean True if context is set and valid
function NavigationContext.hasValidContext()
    return _current_context.type ~= nil and _current_context.entry_id ~= nil
end

---Clear the navigation context (useful for cleanup or testing)
---@return nil
function NavigationContext.clear()
    _current_context = {
        type = nil,
        feed_id = nil,
        category_id = nil,
        entry_id = nil,
        timestamp = nil,
    }
end

---Get a human-readable description of the current context (for debugging)
---@return string Context description
function NavigationContext.getContextDescription()
    local context = _current_context
    if not context.type then
        return "No navigation context set"
    end

    local desc = "Context: " .. context.type
    if context.feed_id then
        desc = desc .. " (feed " .. context.feed_id .. ")"
    elseif context.category_id then
        desc = desc .. " (category " .. context.category_id .. ")"
    end
    if context.entry_id then
        desc = desc .. ", current entry: " .. context.entry_id
    end
    return desc
end

return NavigationContext
