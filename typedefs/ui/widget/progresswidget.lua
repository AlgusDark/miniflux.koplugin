---@meta
---@module 'ui/widget/progresswidget'

-- ProgressWidget - A widget for displaying progress of long-running operations
--
-- ProgressWidget provides a visual progress indicator with:
-- - Percentage-based progress tracking
-- - Customizable title and descriptive text
-- - Responsive sizing for different screen sizes
-- - Integration with KOReader's UI widget system
--
-- Commonly used for file downloads, data processing, and other operations
-- that require user feedback about completion status.
---@class ProgressWidget
---@field new fun(self: ProgressWidget, options: table): ProgressWidget Create new progress widget
---@field setPercentage fun(self: ProgressWidget, percentage: number): nil Update progress percentage
---@field setText fun(self: ProgressWidget, text: string): nil Update descriptive text
local ProgressWidget = {}

return ProgressWidget