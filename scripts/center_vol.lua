-- Version 1.1
-- 10/29/26

-- Ctrl+vol up or down

local mp = require "mp"

local center_gain_db = 0.0
local step_db = 1.0

local max_db = 15.0
local min_db = -15.0

local function update_center_volume(delta)
    center_gain_db = center_gain_db + delta

    if center_gain_db > max_db then
        center_gain_db = max_db
    elseif center_gain_db < min_db then
        center_gain_db = min_db
    end

    local mult = 10 ^ (center_gain_db / 20)

    local filter_str = string.format(
        "@cvol:lavfi=[pan=stereo|c0=c0+%.3f*c2|c1=c1+%.3f*c2]",
        mult, mult
    )

    mp.commandv("af", "set", filter_str)
    
    mp.osd_message(string.format("Center Channel Boost: %.1f dB", center_gain_db))
end

mp.add_key_binding("Ctrl+WHEEL_UP", "center_vol_up", function()
    update_center_volume(step_db)
end, { repeatable = true })

mp.add_key_binding("Ctrl+WHEEL_DOWN", "center_vol_down", function()
    update_center_volume(-step_db)
end, { repeatable = true })