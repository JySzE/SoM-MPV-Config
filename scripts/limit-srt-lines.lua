local MAX_LINES = 2

local IGNORE_CODECS = {
    ass = true,
    ssa = true,
    hdmv_pgs_subtitle = true,
    dvd_subtitle = true,
}

local function is_ignored_codec(track)
    local codec = track and track.codec
    return codec ~= nil and IGNORE_CODECS[codec] == true
end

local function flatten_lines(text)
    local lines = {}
    for l in text:gmatch("[^\r\n]+") do
        l = l:gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" then lines[#lines + 1] = l end
    end
    if #lines == 0 then return nil end
    if #lines > MAX_LINES then
        local merged, rest = {}, {}
        for i = 1, MAX_LINES - 1 do merged[i] = lines[i] end
        for i = math.max(MAX_LINES, 1), #lines do rest[#rest + 1] = lines[i] end
        merged[MAX_LINES] = table.concat(rest, " ")
        lines = merged
    end
    return table.concat(lines, "\n")
end

local osd_active = false

local FILL_COLOR, FILL_ALPHA       = "F2F2F2", "00"
local OUTLINE_COLOR, OUTLINE_ALPHA = "000000", "00"
local SHADOW_COLOR, SHADOW_ALPHA   = "000000", "73"

local function build_style_tags(osd_w, osd_h, ml, mt, mr, mb)
    local video_h = osd_h - mt - mb
    local scale = video_h / 720

    local font       = mp.get_property("sub-font", "Gandhi Sans")
    local font_size  = mp.get_property_number("sub-font-size", 48) * scale
    local bold       = mp.get_property_bool("sub-bold", true) and "\\b1" or "\\b0"
    local italic     = mp.get_property_bool("sub-italic", false) and "\\i1" or "\\i0"
    local bord       = mp.get_property_number("sub-outline-size", 2.4) * scale
    local shad       = mp.get_property_number("sub-shadow-offset", 1) * scale
    local blur       = mp.get_property_number("sub-blur", 0)
    local spacing    = mp.get_property_number("sub-spacing", 0) * scale
    local margin_x   = mp.get_property_number("sub-margin-x", 80) * scale
    local margin_y   = mp.get_property_number("sub-margin-y", 50) * scale

    local align_x = mp.get_property("sub-align-x", "center")
    local align_y = mp.get_property("sub-align-y", "bottom")
    local col = ({ left = 0, center = 1, right = 2 })[align_x] or 1
    local row = ({ bottom = 1, center = 4, top = 7 })[align_y] or 1
    local an = row + col

    local pos_x
    if align_x == "left" then pos_x = margin_x
    elseif align_x == "right" then pos_x = osd_w - margin_x
    else pos_x = osd_w / 2 end

    local pos_y
    if align_y == "top" then pos_y = margin_y
    elseif align_y == "center" then pos_y = osd_h / 2
    else pos_y = osd_h - margin_y end

    return string.format(
        "{\\pos(%d,%d)\\an%d\\fn%s\\fs%.1f%s%s\\bord%.2f\\shad%.2f\\blur%.2f\\fsp%.2f" ..
        "\\c&H%s&\\1a&H%s&\\3c&H%s&\\3a&H%s&\\4c&H%s&\\4a&H%s&}",
        pos_x, pos_y, an, font, font_size, bold, italic, bord, shad, blur, spacing,
        FILL_COLOR, FILL_ALPHA,
        OUTLINE_COLOR, OUTLINE_ALPHA,
        SHADOW_COLOR, SHADOW_ALPHA
    )
end

local function render_osd_text(_, text)
    local w, h = mp.get_osd_size()
    if not w or w == 0 then w, h = 1280, 720 end
    local ml, mt, mr, mb = mp.get_osd_margins()
    ml, mt, mr, mb = ml or 0, mt or 0, mr or 0, mb or 0
    if not text or text == "" then
        mp.set_osd_ass(w, h, "")
        return
    end
    local flattened = flatten_lines(text:gsub("\\N", "\n"))
    if not flattened then
        mp.set_osd_ass(w, h, "")
        return
    end
    local tags = build_style_tags(w, h, ml, mt, mr, mb)
    mp.set_osd_ass(w, h, tags .. flattened:gsub("\n", "\\N"))
end

local function set_osd_mode(enabled)
    if enabled == osd_active then return end
    osd_active = enabled
    if enabled then
        mp.set_property("sub-visibility", "no")
        mp.observe_property("sub-text", "string", render_osd_text)
    else
        mp.unobserve_property(render_osd_text)
        local w, h = mp.get_osd_size()
        if w and w > 0 then mp.set_osd_ass(w, h, "") end
        mp.set_property("sub-visibility", "yes")
    end
end

local function update_mode()
    local track_list = mp.get_property_native("track-list")
    if not track_list then return end
    local sid = mp.get_property_number("sid")
    local active
    for _, track in ipairs(track_list) do
        if track.type == "sub" and track.id == sid then active = track break end
    end
    if active and not is_ignored_codec(active) then
        set_osd_mode(true)
    else
        set_osd_mode(false)
    end
end

mp.observe_property("track-list", "native", update_mode)
mp.observe_property("sid", "native", update_mode)

mp.register_event("end-file", function()
    set_osd_mode(false)
end)

mp.register_event("shutdown", function()
    set_osd_mode(false)
end)
