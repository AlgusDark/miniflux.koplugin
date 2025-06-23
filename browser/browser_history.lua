--[[--
Browser History - Navigation History Management

Manages browser navigation history stack for back/forward navigation.

@module browser.browser_history
--]]

---@class HistoryState
---@field location string Location identifier for restoration
---@field params table Parameters for restoration
---@field page_info? PageInfo Page information for restoration

---@class PageInfo
---@field page number Current page number
---@field perpage number Items per page

---@class BrowserHistory
---@field stack HistoryState[] Navigation history stack
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
---@param state HistoryState State to save for back navigation
function BrowserHistory:push(state)
    if not state then
        return
    end

    table.insert(self.stack, state)
end

---Go back to previous state
---@return HistoryState|nil state Restored state or nil if no history
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
---@return HistoryState|nil state Most recent state or nil if empty
function BrowserHistory:peek()
    if #self.stack == 0 then
        return nil
    end

    return self.stack[#self.stack]
end

return BrowserHistory
