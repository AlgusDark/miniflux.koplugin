---@meta
---@module 'ui/widget/container/inputcontainer'

---@class TouchZone
---@field id string Zone identifier
---@field ges string Gesture type (e.g., "tap", "swipe")
---@field screen_zone {ratio_x: number, ratio_y: number, ratio_w: number, ratio_h: number} Screen zone ratios
---@field handler function Gesture handler function
---@field overrides? string[] List of zone IDs this zone overrides
---@field rate? number Gesture rate

---@class KeySequence
---@field [number] string[] Key sequence patterns
---@field event? string Event name to emit
---@field args? any Arguments for the event
---@field is_inactive? boolean Whether sequence is inactive

---@class InputContainerOptions : WidgetContainerOptions
---@field vertical_align? "top"|"center" Vertical alignment (default: "top")
---@field key_events? table<string, KeySequence> Key event mappings
---@field ges_events? table Gesture event mappings
---@field stop_events_propagation? boolean Whether to stop event propagation

---@class InputContainer : WidgetContainer
---@field vertical_align "top"|"center" Vertical alignment
---@field key_events table<string, KeySequence> Key event mappings
---@field ges_events table Gesture event mappings
---@field stop_events_propagation boolean Whether to stop event propagation
---@field touch_zone_dg table Touch zone dependency graph
---@field _zones table Touch zones by ID
---@field _ordered_touch_zones table[] Ordered touch zones
---@field input_dialog table Current input dialog
---@field extend fun(self: InputContainer, o: InputContainerOptions): InputContainer Extend InputContainer class
---@field new fun(self: InputContainer, o: InputContainerOptions): InputContainer Create new InputContainer
---@field _init fun(self: InputContainer): nil Initialize instance-specific properties
---@field paintTo fun(self: InputContainer, bb: table, x: number, y: number): nil Paint container to buffer
---@field registerTouchZones fun(self: InputContainer, zones: TouchZone[]): nil Register touch zones
---@field unRegisterTouchZones fun(self: InputContainer, zones: TouchZone[]): nil Unregister touch zones
---@field checkRegisterTouchZone fun(self: InputContainer, id: string): boolean Check if touch zone is registered
---@field updateTouchZonesOnScreenResize fun(self: InputContainer, new_screen_dimen: table): nil Update touch zones for screen resize
---@field onKeyPress fun(self: InputContainer, key: table): boolean Handle key press
---@field onKeyRepeat fun(self: InputContainer, key: table): boolean Handle key repeat
---@field onGesture fun(self: InputContainer, ev: table): boolean Handle gesture
---@field setIgnoreTouchInput fun(self: InputContainer, state: boolean): boolean Set touch input ignore state
---@field onIgnoreTouchInput fun(self: InputContainer, toggle: boolean): boolean Handle ignore touch input event
---@field onInput fun(self: InputContainer, input: table, ignore_first_hold_release?: boolean): nil Handle input dialog
---@field closeInputDialog fun(self: InputContainer): nil Close input dialog
---@field onPhysicalKeyboardDisconnected fun(self: InputContainer): nil Handle keyboard disconnection
---@field isGestureAlwaysActive fun(self: InputContainer, ges: string, multiswipe_directions: table): boolean Check if gesture is always active
local InputContainer = {}

return InputContainer
