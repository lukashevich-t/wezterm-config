local wezterm = require('wezterm')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')

---@alias Event.RightStatusOptions { date_format?: string }

---Setup options for the right status bar
local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
    {
        name = 'date_format',
        type = 'string',
        default = '%a %H:%M:%S',
    },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local attr = Cells.attr

local M = {}

---@type table<string, Cells.SegmentColors>
-- stylua: ignore
local colors = {
   date      = { fg = '#fab387', bg = 'rgba(0, 0, 0, 0.4)' },
   battery   = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   separator = { fg = '#74c7ec', bg = 'rgba(0, 0, 0, 0.4)' }
}

local cells = Cells:new()

cells
    :add_segment('date_text', '', colors.date, attr(attr.intensity('Bold')))
    :add_segment('separator', ' | ', colors.separator)
    :add_segment('battery_text', '', colors.battery, attr(attr.intensity('Bold')))

---@return string
local function battery_info()
    local charge = ''

    for _, b in ipairs(wezterm.battery_info()) do
        charge = string.format('%.0f%%', b.state_of_charge * 100)
    end

    return charge
end

---@param opts? Event.RightStatusOptions Default: {date_format = '%a %H:%M:%S'}
M.setup = function(opts)
    local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

    if err then
        wezterm.log_error(err)
    end

    wezterm.on('update-right-status', function(window, _pane)
        cells
            :update_segment_text('date_text', wezterm.strftime(valid_opts.date_format))
            :update_segment_text('battery_text', battery_info())

        window:set_right_status(
            wezterm.format(cells:render({ 'date_text', 'separator', 'battery_text' }))
        )
    end)
end

return M
