local Error = require('utils/error')
local _ = require('gettext')

-- **TimeUtils** - Time utilities for Miniflux Plugin
--
-- This utility module provides time-related functions including timestamp
-- conversion and date parsing for RSS entries and navigation.
local TimeUtils = {}

---Convert ISO-8601 timestamp to Unix timestamp
---@param iso_string string ISO-8601 formatted timestamp string
---@return number|nil result, Error|nil error
function TimeUtils.iso8601_to_unix(iso_string)
    local Y, M, D, h, m, sec, sign, tzh, tzm =
        iso_string:match('(%d+)%-(%d+)%-(%d+)T' .. '(%d+):(%d+):(%d+)' .. '([%+%-])(%d%d):(%d%d)$')

    if not Y then
        return nil, Error.new(_('Invalid ISO-8601 timestamp format'))
    end

    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    tzh, tzm = tonumber(tzh), tonumber(tzm)

    local y = Y
    local mo = M
    if mo <= 2 then
        y = y - 1
        mo = mo + 12
    end

    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (mo - 3) + 2) / 5) + D - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468

    local utc_secs = days * 86400 + h * 3600 + m * 60 + sec

    local offs = tzh * 3600 + tzm * 60
    if sign == '+' then
        utc_secs = utc_secs - offs
    else
        utc_secs = utc_secs + offs
    end

    return utc_secs, nil
end

return TimeUtils
