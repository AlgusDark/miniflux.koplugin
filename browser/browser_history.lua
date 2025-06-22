--[[--
Browser History - Simple Navigation History Management

Manages browser navigation history stack for back/forward navigation.
Uses simple data objects instead of complex command patterns.

@module miniflux.browser.browser_history
--]]

---@class HistoryParams
---@field type ViewType View type
---@field page_info? PageInfo Page information for restoration
---@field feed_id? number Feed ID (for feed entries)
---@field category_id? number Category ID (for category entries)

---@class BrowserHistory
---@field stack HistoryParams[] Navigation history stack
local BrowserHistory = {}
BrowserHistory.__index = BrowserHistory

---Create new browser history instance
---@return BrowserHistory
function BrowserHistory:new()
    local obj = setmetatable({}, BrowserHistory)
    obj.stack = {}
    return obj
end

-- =============================================================================
-- HISTORY MANAGEMENT
-- =============================================================================

---Push navigation state to history
---@param params HistoryParams State to save for back navigation
function BrowserHistory:push(params)
    if not params or not params.type then
        return
    end

    -- Create a copy to avoid reference issues
    local history_entry = {
        type = params.type,
        page_info = params.page_info,
        feed_id = params.feed_id,
        category_id = params.category_id,
    }

    table.insert(self.stack, history_entry)
end

---Go back to previous state
---@return HistoryParams|nil params Restored parameters or nil if no history
function BrowserHistory:goBack()
    if #self.stack == 0 then
        return nil
    end

    return table.remove(self.stack)
end

---Clear all history
function BrowserHistory:clear()
    self.stack = {}
end

---Check if history is available
---@return boolean has_history True if can go back
function BrowserHistory:canGoBack()
    return #self.stack > 0
end

---Get current history depth
---@return number depth Number of items in history
function BrowserHistory:getDepth()
    return #self.stack
end

---Peek at the most recent history entry without removing it
---@return HistoryParams|nil params Most recent history entry or nil if empty
function BrowserHistory:peek()
    if #self.stack == 0 then
        return nil
    end

    return self.stack[#self.stack]
end

return BrowserHistory
