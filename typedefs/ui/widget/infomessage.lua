---@meta

---@class FontFace
---@field orig_font string
---@field realname string
---@field size number
---@field orig_size number
---@field ftsize any
---@field hash string

---@class MovableContainer
---@field dimen table

---@class InfoMessageOptions
---@field modal? boolean
---@field face? FontFace
---@field monospace_font? boolean
---@field text? string
---@field timeout? number -- in seconds
---@field width? number -- The width of the InfoMessage. Keep it nil to use default value.
---@field height? number -- The height of the InfoMessage. If this field is set, a scrollbar may be shown.
---@field force_one_line? boolean -- Attempt to show text in one single line. This setting and height are not to be used conjointly.
---@field image? any -- The image shows at the left of the InfoMessage. Image data will be freed by InfoMessage, caller should not manage its lifecycle
---@field image_width? number -- The image width if image is used. Keep it nil to use original width.
---@field image_height? number -- The image height if image is used. Keep it nil to use original height.
---@field show_icon? boolean -- Whether the icon should be shown. If it is false, self.image will be ignored.
---@field icon? string
---@field alpha? boolean -- if image or icon have an alpha channel (default to true for icons, false for images)
---@field dismissable? boolean
---@field dismiss_callback? function
---@field alignment? string -- Passed to TextBoxWidget
---@field lang? string
---@field para_direction_rtl? boolean
---@field auto_para_direction? boolean
---@field no_refresh_on_close? boolean -- Don't call setDirty when closing the widget
---@field show_delay? number -- Only have it painted after this delay (dismissing still works before it's shown)
---@field flush_events_on_show? boolean -- Set to true when it might be displayed after some processing, to avoid accidental dismissal
---@field unmovable? boolean

---@class InfoMessage : InputContainer
---@field _timeout_func function|nil -- Internal timeout function reference
---@field movable MovableContainer -- The movable container that wraps the content
---@field invisible boolean|nil -- Internal visibility state during delayed show
---@field _delayed_show_action function|nil -- Internal scheduled action for delayed show
---@field _initial_orig_font string|nil -- Backup of original font for size adjustments
---@field _initial_orig_size number|nil -- Backup of original size for adjustments
local InfoMessage = {}

---@param opts? InfoMessageOptions Configuration options for InfoMessage
---@return InfoMessage
function InfoMessage:new(opts) end

---Initialize the InfoMessage widget
function InfoMessage:init() end

---Called when the widget is closed
function InfoMessage:onCloseWidget() end

---Called when the widget is shown
---@return boolean
function InfoMessage:onShow() end

---Get the visible area of the widget
---@return table|nil
function InfoMessage:getVisibleArea() end

---Paint the widget to the buffer
---@param bb any
---@param x number
---@param y number
function InfoMessage:paintTo(bb, x, y) end

---Handle tap close event
---@return boolean|nil
function InfoMessage:onTapClose() end

---Handle any key pressed event (alias to onTapClose)
---@return boolean|nil
function InfoMessage:onAnyKeyPressed() end

return InfoMessage
