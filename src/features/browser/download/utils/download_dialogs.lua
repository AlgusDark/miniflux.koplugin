local UIManager = require('ui/uimanager')
local ButtonDialog = require('ui/widget/buttondialog')
local _ = require('gettext')
local T = require('ffi/util').template

-- **Download Dialog Utilities** - UI dialogs specific to download workflows
-- Handles cancellation dialogs for single entry and batch download operations
local DownloadDialogs = {}

---Show cancellation choice dialog with context-aware options
---@param context "during_images" | "after_images"
---@return string|nil User choice based on context (nil if dialog fails)
function DownloadDialogs.showCancellationDialog(context)
    local user_choice = nil
    local choice_dialog = nil --[[@type ButtonDialog]]

    -- Context-specific dialog configuration
    local dialog_config = {}

    if context == 'during_images' then
        dialog_config = {
            title = _('Image download was cancelled.\\nWhat would you like to do?'),
            buttons = {
                {
                    text = _('Cancel entry creation'),
                    choice = 'cancel_entry',
                },
                {
                    text = _('Continue without images'),
                    choice = 'continue_without_images',
                },
                {
                    text = _('Resume downloading'),
                    choice = 'resume_downloading',
                },
            },
        }
    else -- "after_images"
        dialog_config = {
            title = _(
                'Entry creation was interrupted.\\nImages have been downloaded successfully.\\n\\nWhat would you like to do?'
            ),
            buttons = {
                {
                    text = _('Cancel entry creation'),
                    choice = 'cancel_entry',
                },
                {
                    text = _('Continue with entry creation'),
                    choice = 'continue_creation',
                },
            },
        }
    end

    -- Build button table for ButtonDialog
    local dialog_buttons = { {} }
    for _, btn in ipairs(dialog_config.buttons) do
        table.insert(dialog_buttons[1], {
            text = btn.text,
            callback = function()
                user_choice = btn.choice
                UIManager:close(choice_dialog)
            end,
        })
    end

    -- Create dialog with context-specific configuration
    choice_dialog = ButtonDialog:new({
        title = dialog_config.title,
        title_align = 'center',
        dismissable = false,
        buttons = dialog_buttons,
        -- Handle tap outside dialog - behave like "Cancel entry creation"
        -- tap_close_callback = function()
        --     user_choice = "cancel_entry"
        -- end,
    })

    UIManager:show(choice_dialog)

    -- Use proper modal dialog pattern
    repeat
        UIManager:handleInput()
    until user_choice ~= nil

    return user_choice
end

---Show batch cancellation choice dialog with stateful options
---@param context "during_entry_images" | "during_batch"
---@param batch_state table Batch state containing skip_images_for_all, current_entry_index, total_entries
---@return string|nil User choice based on context and state (nil if dialog fails)
function DownloadDialogs.showBatchCancellationDialog(context, batch_state)
    local user_choice = nil
    local choice_dialog = nil --[[@type ButtonDialog]]

    -- Extract state information
    local skip_images_for_all = batch_state.skip_images_for_all or false
    local current_entry_index = batch_state.current_entry_index or 1
    local total_entries = batch_state.total_entries or 1
    local current_entry_title = batch_state.current_entry_title or _('Current Entry')

    -- Context-specific dialog configuration
    local dialog_config = {}

    if context == 'during_entry_images' then
        -- User cancelled during image download for a specific entry
        local title = total_entries == 1
                and T(
                    _('Image download was cancelled for:\\n%1\\n\\nWhat would you like to do?'),
                    current_entry_title
                )
            or T(
                _(
                    'Image download was cancelled for entry %1/%2:\\n%3\\n\\nWhat would you like to do?'
                ),
                current_entry_index,
                total_entries,
                current_entry_title
            )

        local buttons = {
            {
                text = _('Cancel entry creation'),
                choice = 'cancel_current_entry',
            },
            {
                text = _('Cancel all entries creation'),
                choice = 'cancel_all_entries',
            },
            {
                text = _('Continue without images'),
                choice = 'skip_images_current',
            },
            {
                text = _('Resume downloading'),
                choice = 'resume_downloading',
            },
        }

        -- Add stateful image option based on current batch state
        if skip_images_for_all then
            -- User previously chose to skip images for all, now offer to include them
            table.insert(buttons, 3, {
                text = _('Include images for all entries'),
                choice = 'include_images_all',
            })
        else
            -- User hasn't disabled images globally, offer to skip for all remaining
            table.insert(buttons, 3, {
                text = _('Skip images for all entries'),
                choice = 'skip_images_all',
            })
        end

        dialog_config = {
            title = title,
            buttons = buttons,
        }
    else -- "during_batch"
        -- User cancelled during batch progress (between entries)
        local title = total_entries == 1
                and T(_('Batch download was cancelled.\\n\\nWhat would you like to do?'))
            or T(
                _(
                    'Batch download was cancelled.\\nProgress: %1/%2 entries completed.\\n\\nWhat would you like to do?'
                ),
                current_entry_index - 1,
                total_entries
            )

        local buttons = {
            {
                text = _('Cancel all entries creation'),
                choice = 'cancel_all_entries',
            },
            {
                text = _('Resume downloading'),
                choice = 'resume_downloading',
            },
        }

        -- Add stateful image option for remaining entries
        if skip_images_for_all then
            table.insert(buttons, 2, {
                text = _('Include images for remaining entries'),
                choice = 'include_images_all',
            })
        else
            table.insert(buttons, 2, {
                text = _('Skip images for remaining entries'),
                choice = 'skip_images_all',
            })
        end

        dialog_config = {
            title = title,
            buttons = buttons,
        }
    end

    -- Build button grid for ButtonDialog (2 buttons per row for better layout)
    local dialog_buttons = {}

    -- Split buttons into rows of 2 for grid layout
    for i = 1, #dialog_config.buttons, 2 do
        local row = {}

        -- Add first button of the row
        table.insert(row, {
            text = dialog_config.buttons[i].text,
            callback = function()
                user_choice = dialog_config.buttons[i].choice
                UIManager:close(choice_dialog)
            end,
        })

        -- Add second button if it exists
        if dialog_config.buttons[i + 1] then
            table.insert(row, {
                text = dialog_config.buttons[i + 1].text,
                callback = function()
                    user_choice = dialog_config.buttons[i + 1].choice
                    UIManager:close(choice_dialog)
                end,
            })
        end

        table.insert(dialog_buttons, row)
    end

    -- Create dialog with context-specific configuration
    choice_dialog = ButtonDialog:new({
        title = dialog_config.title,
        title_align = 'center',
        dismissable = false,
        buttons = dialog_buttons,
    })

    UIManager:show(choice_dialog)

    -- Use proper modal dialog pattern
    repeat
        UIManager:handleInput()
    until user_choice ~= nil

    return user_choice
end

return DownloadDialogs
