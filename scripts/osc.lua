-- Version 1.0
-- 11/02/2026

mp.set_property("osc", "no")
if mp.get_script_name() ~= "osc" then
	local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/]osc%.lua)$")
	if script_path then
		mp.add_timeout(0.05, function()
			mp.commandv("load-script", script_path)
		end)
		return
	end
end
local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

local original_window_title = mp.get_property("title") or "${media-title}"
mp.set_property("title", "${?media-title:" .. original_window_title .. "}${!media-title:SoM MPV}")

local user_opts = {
	showwindowed = true,
	showfullscreen = true,
	idlescreen = true,
	scalewindowed = 1,
	scalefullscreen = 1,
	scaleforcedwindow = 2,
	vidscale = true,
	valign = 0.8,
	halign = 0,
	barmargin = 0,
	boxalpha = 80,
	hidetimeout = 500,
	fadeduration = 200,
	deadzonesize = 0.5,
	minmousemove = 0,
	iamaprogrammer = false,
	layout = "bottombar",
	seekbarstyle = "bar",
	seekbarhandlesize = 0.6,
	seekrangestyle = "inverted",
	seekrangeseparate = true,
	seekrangealpha = 200,
	seekbarkeyframes = true,
	scrollcontrols = true,
	title = "${media-title}",
	tooltipborder = 1,
	timetotal = false,
	remaining_playtime = true,
	timems = false,
	tcspace = 100,
	visibility = "auto",
	boxmaxchars = 80,
	boxvideo = false,
	windowcontrols = "auto",
	windowcontrols_alignment = "right",
	greenandgrumpy = false,
	livemarkers = true,
	chapters_osd = true,
	playlist_osd = true,
	chapter_fmt = "Chapter: %s",
	unicodeminus = false,
}

opt.read_options(user_opts, "osc", function(list) update_options(list) end)

local osc_param = {
	playresy = 0,
	playresx = 0,
	display_aspect = 1,
	unscaled_y = 0,
	areas = {},
	video_margins = {
		l = 0, r = 0, t = 0, b = 0,
	},
}

local osc_styles = {
	bigButtons = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs50\\fnmpv-osd-symbols}",
	smallButtonsL = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs19\\fnmpv-osd-symbols}",
	smallButtonsLlabel = "{\\fscx105\\fscy105\\fnSegoe UI}",
	smallButtonsR = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs30\\fnmpv-osd-symbols}",
	topButtons = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs12\\fnmpv-osd-symbols}",

	elementHover = "{\\1c&H21B6F2}",
	elementDown = "{\\1c&H21B6F2\\3c&H21B6F2\\3a&H70\\bord1.2\\blur1.8}",
	timecodes = "{\\blur0\\bord0\\1c&HEDE7E3\\3c&HEDE7E3\\fnSegoe UI\\fs20}",
	vidtitle = "{\\blur0\\bord0\\1c&HEDE7E3\\3c&HEDE7E3\\fnSegoe UI\\fs12\\q2}",
	box = "{\\rDefault\\blur0\\bord0\\1c&H171411\\3c&H171411}",

	topButtonsBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs18\\fnmpv-osd-symbols}",
	smallButtonsBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs22\\fnmpv-osd-symbols}",
	timecodesBar = "{\\blur0\\bord0\\1c&HEDE7E3\\3c&HEDE7E3\\fnSegoe UI\\fs22}",
	seekbarGold = "{\\blur0\\bord0\\1c&H21B6F2\\3c&H21B6F2}",
	seekbarNibbles = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF}",
	volumeTrack = "{\\blur0\\bord0\\1c&H6B6258\\3c&H6B6258}",
	timePosBar = "{\\blur0\\bord".. user_opts.tooltipborder .."\\1c&HEDE7E3\\3c&HH171411\\fnSegoe UI\\fs27}",
	vidtitleBar = "{\\blur0\\bord0\\1c&HEDE7E3\\3c&H171411\\fnSegoe UI\\fs17\\q2}",

	wcButtons = "{\\1c&HFFFFFF\\4c&H171411\\fs22\\fnmpv-osd-symbols}",
}

local function create_osd_overlay(...)
	if not mp.create_osd_overlay then return end
	return mp.create_osd_overlay(...)
end

local state = {
	showtime,
	osc_visible = false,
	anistart,
	anitype,
	animation,
	mouse_down_counter = 0,
	active_element = nil,
	active_event_source = nil,
	rightTC_trem = not user_opts.timetotal,
	tc_ms = user_opts.timems,
	mp_screen_sizeX, mp_screen_sizeY,
	initREQ = false,
	marginsREQ = false,
	last_mouseX, last_mouseY,
	mouse_in_window = false,
	message_text,
	message_hide_timer,
	fullscreen = false,
	tick_timer = nil,
	tick_last_time = 0,
	hide_timer = nil,
	cache_state = nil,
	idle = false,
	enabled = true,
	input_enabled = true,
	showhide_enabled = false,
	windowcontrols_buttons = false,
	dmx_cache = 0,
	using_video_margins = false,
	border = true,
	title_bar = true,
	maximized = false,
	osd = create_osd_overlay("ass-events"),
	chapter_list = {},
}

local thumbfast = {
	width = 0,
	height = 0,
	disabled = false
}

local window_control_box_width = 80
local tick_delay = 0.03

local is_december = os.date("*t").month == 12

function kill_animation()
	state.anistart = nil
	state.animation = nil
	state.anitype =  nil
end

function set_osd(res_x, res_y, text, z)
	if state.osd.res_x == res_x and
		state.osd.res_y == res_y and
		state.osd.data == text then
		return
	end
	state.osd.res_x = res_x
	state.osd.res_y = res_y
	state.osd.data = text
	state.osd.z = z
	state.osd:update()
end

set_osd = state.osd and set_osd or mp.set_osd_ass

local margins_opts = {
	{"l", "video-margin-ratio-left"},
	{"r", "video-margin-ratio-right"},
	{"t", "video-margin-ratio-top"},
	{"b", "video-margin-ratio-bottom"},
}

function get_virt_scale_factor()
	local w, h = mp.get_osd_size()
	if w <= 0 or h <= 0 then
		return 0, 0
	end
	return osc_param.playresx / w, osc_param.playresy / h
end

function get_virt_mouse_pos()
	if state.mouse_in_window then
		local sx, sy = get_virt_scale_factor()
		local x, y = mp.get_mouse_pos()
		return x * sx, y * sy
	else
		return -1, -1
	end
end

function set_virt_mouse_area(x0, y0, x1, y1, name)
	local sx, sy = get_virt_scale_factor()
	mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
end

function scale_value(x0, x1, y0, y1, val)
	local m = (y1 - y0) / (x1 - x0)
	local b = y0 - (m * x0)
	return (m * val) + b
end

function get_hitbox_coords(x, y, an, w, h)

	local alignments = {
		[1] = function () return x, y-h, x+w, y end,
		[2] = function () return x-(w/2), y-h, x+(w/2), y end,
		[3] = function () return x-w, y-h, x, y end,

		[4] = function () return x, y-(h/2), x+w, y+(h/2) end,
		[5] = function () return x-(w/2), y-(h/2), x+(w/2), y+(h/2) end,
		[6] = function () return x-w, y-(h/2), x, y+(h/2) end,

		[7] = function () return x, y, x+w, y+h end,
		[8] = function () return x-(w/2), y, x+(w/2), y+h end,
		[9] = function () return x-w, y, x, y+h end,
	}

	return alignments[an]()
end

function get_hitbox_coords_geo(geometry)
	return get_hitbox_coords(geometry.x, geometry.y, geometry.an,
		geometry.w, geometry.h)
end

function get_element_hitbox(element)
	return element.hitbox.x1, element.hitbox.y1,
		element.hitbox.x2, element.hitbox.y2
end

function mouse_hit(element)
	return mouse_hit_coords(get_element_hitbox(element))
end

function mouse_hit_coords(bX1, bY1, bX2, bY2)
	local mX, mY = get_virt_mouse_pos()
	return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

function limit_range(min, max, val)
	if val > max then
		val = max
	elseif val < min then
		val = min
	end
	return val
end

function get_slider_ele_pos_for(element, val)

	local ele_pos = scale_value(
		element.slider.min.value, element.slider.max.value,
		element.slider.min.ele_pos, element.slider.max.ele_pos,
		val)

	return limit_range(
		element.slider.min.ele_pos, element.slider.max.ele_pos,
		ele_pos)
end

function get_slider_value_at(element, glob_pos)

	local val = scale_value(
		element.slider.min.glob_pos, element.slider.max.glob_pos,
		element.slider.min.value, element.slider.max.value,
		glob_pos)

	return limit_range(
		element.slider.min.value, element.slider.max.value,
		val)
end

function get_slider_value(element)
	return get_slider_value_at(element, get_virt_mouse_pos())
end

function countone(val)
	if not (user_opts.iamaprogrammer) then
		val = val + 1
	end
	return val
end

function get_align(align, frame, obj, margin)
	return (frame / 2) + (((frame / 2) - margin - (obj / 2)) * align)
end

function mult_alpha(alphaA, alphaB)
	return 255 - (((1-(alphaA/255)) * (1-(alphaB/255))) * 255)
end

function add_area(name, x1, y1, x2, y2)
	if (osc_param.areas[name] == nil) then
		osc_param.areas[name] = {}
	end
	table.insert(osc_param.areas[name], {x1=x1, y1=y1, x2=x2, y2=y2})
end

function ass_append_alpha(ass, alpha, modifier)
	local ar = {}

	for ai, av in pairs(alpha) do
		av = mult_alpha(av, modifier)
		if state.animation then
			av = mult_alpha(av, state.animation)
		end
		ar[ai] = av
	end

	ass:append(string.format("{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}",
				ar[1], ar[2], ar[3], ar[4]))
end

local c = 0.551915024494

function hexagon_cw(ass, x0, y0, x1, y1, r1, r2)
	if r2 == nil then
		r2 = r1
	end
	ass:move_to(x0 + r1, y0)
	if x0 ~= x1 then
		ass:line_to(x1 - r2, y0)
	end
	ass:line_to(x1, y0 + r2)
	if x0 ~= x1 then
		ass:line_to(x1 - r2, y1)
	end
	ass:line_to(x0 + r1, y1)
	ass:line_to(x0, y0 + r1)
end

function hexagon_ccw(ass, x0, y0, x1, y1, r1, r2)
	if r2 == nil then
		r2 = r1
	end
	ass:move_to(x0 + r1, y0)
	ass:line_to(x0, y0 + r1)
	ass:line_to(x0 + r1, y1)
	if x0 ~= x1 then
		ass:line_to(x1 - r2, y1)
	end
	ass:line_to(x1, y0 + r2)
	if x0 ~= x1 then
		ass:line_to(x1 - r2, y0)
	end
end

function round_rect_cw(ass, x0, y0, x1, y1, r1, r2)
	if r2 == nil then
		r2 = r1
	end
	local c1 = c * r1
	local c2 = c * r2
	ass:move_to(x0 + r1, y0)
	ass:line_to(x1 - r2, y0)
	if r2 > 0 then
		ass:bezier_curve(x1 - r2 + c2, y0, x1, y0 + r2 - c2, x1, y0 + r2)
	end
	ass:line_to(x1, y1 - r2)
	if r2 > 0 then
		ass:bezier_curve(x1, y1 - r2 + c2, x1 - r2 + c2, y1, x1 - r2, y1)
	end
	ass:line_to(x0 + r1, y1)
	if r1 > 0 then
		ass:bezier_curve(x0 + r1 - c1, y1, x0, y1 - r1 + c1, x0, y1 - r1)
	end
	ass:line_to(x0, y0 + r1)
	if r1 > 0 then
		ass:bezier_curve(x0, y0 + r1 - c1, x0 + r1 - c1, y0, x0 + r1, y0)
	end
end

function round_rect_ccw(ass, x0, y0, x1, y1, r1, r2)
	if r2 == nil then
		r2 = r1
	end
	local c1 = c * r1
	local c2 = c * r2
	ass:move_to(x0 + r1, y0)
	if r1 > 0 then
		ass:bezier_curve(x0 + r1 - c1, y0, x0, y0 + r1 - c1, x0, y0 + r1)
	end
	ass:line_to(x0, y1 - r1)
	if r1 > 0 then
		ass:bezier_curve(x0, y1 - r1 + c1, x0 + r1 - c1, y1, x0 + r1, y1)
	end
	ass:line_to(x1 - r2, y1)
	if r2 > 0 then
		ass:bezier_curve(x1 - r2 + c2, y1, x1, y1 - r2 + c2, x1, y1 - r2)
	end
	ass:line_to(x1, y0 + r2)
	if r2 > 0 then
		ass:bezier_curve(x1, y0 + r2 - c2, x1 - r2 + c2, y0, x1 - r2, y0)
	end
end

function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
	if hexagon then
		hexagon_cw(ass, x0, y0, x1, y1, r1, r2)
	else
		round_rect_cw(ass, x0, y0, x1, y1, r1, r2)
	end
end

function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
	if hexagon then
		hexagon_ccw(ass, x0, y0, x1, y1, r1, r2)
	else
		round_rect_ccw(ass, x0, y0, x1, y1, r1, r2)
	end
end

local nicetypes = {video = "Video", audio = "Audio", sub = "Subtitle"}

function update_tracklist()
	local tracktable = mp.get_property_native("track-list", {})

	tracks_osc = {}
	tracks_osc.video, tracks_osc.audio, tracks_osc.sub = {}, {}, {}
	tracks_mpv = {}
	tracks_mpv.video, tracks_mpv.audio, tracks_mpv.sub = {}, {}, {}
	for n = 1, #tracktable do
		if not (tracktable[n].type == "unknown") then
			local type = tracktable[n].type
			local mpv_id = tonumber(tracktable[n].id)

			table.insert(tracks_osc[type], tracktable[n])

			tracks_mpv[type][mpv_id] = tracktable[n]
			tracks_mpv[type][mpv_id].osc_id = #tracks_osc[type]
		end
	end
end

function get_tracklist(type)
	local msg = "Available " .. nicetypes[type] .. " Tracks: "
	if not tracks_osc or #tracks_osc[type] == 0 then
		msg = msg .. "none"
	else
		for n = 1, #tracks_osc[type] do
			local track = tracks_osc[type][n]
			local lang, title, selected = "unknown", "", "○"
			if not(track.lang == nil) then lang = track.lang end
			if not(track.title == nil) then title = track.title end
			if (track.id == tonumber(mp.get_property(type))) then
				selected = "●"
			end
			msg = msg.."\n"..selected.." "..n..": ["..lang.."] "..title
		end
	end
	return msg
end

function set_track(type, next)
	local current_track_osc = get_track(type)
	local new_track_osc = (current_track_osc + next) % (#tracks_osc[type] + 1)
	local new_track_mpv
	if new_track_osc == 0 then
		new_track_mpv = "no"
	else
		new_track_mpv = tracks_osc[type][new_track_osc].id
	end

	mp.commandv("set", type, new_track_mpv)

		if (new_track_osc == 0) then
		show_message(nicetypes[type] .. " Track: none")
	else
		show_message(nicetypes[type]  .. " Track: "
			.. new_track_osc .. "/" .. #tracks_osc[type]
			.. " [".. (tracks_osc[type][new_track_osc].lang or "unknown") .."] "
			.. (tracks_osc[type][new_track_osc].title or ""))
	end
end

function get_track(type)
	local track = mp.get_property(type)
	if track ~= "no" and track ~= nil then
		local tr = tracks_mpv[type][tonumber(track)]
		if tr then
			return tr.osc_id
		end
	end
	return 0
end

function window_controls_enabled()
	local val = user_opts.windowcontrols
	if val == "auto" then
		return not (state.border and state.title_bar)
	else
		return val ~= "no"
	end
end

function window_controls_alignment()
	return user_opts.windowcontrols_alignment
end

local elements = {}

function prepare_elements()

	local elements2 = {}
	for n, element in pairs(elements) do
		if not (element.layout == nil) and (element.visible) then
			table.insert(elements2, element)
		end
	end
	elements = elements2

	function elem_compare (a, b)
		return a.layout.layer < b.layout.layer
	end

	table.sort(elements, elem_compare)

	for _,element in pairs(elements) do

		local elem_geo = element.layout.geometry

		local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
		element.hitbox = {x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2}

		local style_ass = assdraw.ass_new()

		style_ass:append("{}")
		style_ass:new_event()
		style_ass:pos(elem_geo.x, elem_geo.y)
		style_ass:an(elem_geo.an)
		style_ass:append(element.layout.style)

		element.style_ass = style_ass

		local static_ass = assdraw.ass_new()

		if (element.type == "box") then
			static_ass:draw_start()
			ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
							element.layout.box.radius, element.layout.box.hexagon)
			static_ass:draw_stop()

		elseif (element.type == "slider") then

			local r1 = 0
			local r2 = 0
			local slider_lo = element.layout.slider
			local foV = slider_lo.border + slider_lo.gap

			if (slider_lo.stype ~= "bar") then
				r1 = elem_geo.h / 2
				if slider_lo.edge_knob then
					local knob_radius = (user_opts.seekbarhandlesize * (elem_geo.h - 2 * foV)) / 2
					element.slider.min.ele_pos = knob_radius
					element.slider.max.ele_pos = elem_geo.w - knob_radius
				else
					element.slider.min.ele_pos = elem_geo.h / 2
					element.slider.max.ele_pos = elem_geo.w - (elem_geo.h / 2)
				end
				if (slider_lo.stype == "diamond") then
					r2 = (elem_geo.h - 2 * slider_lo.border) / 2
				elseif (slider_lo.stype == "knob") then
					r2 = r1
				end
			else
				element.slider.min.ele_pos =
					slider_lo.border + slider_lo.gap
				element.slider.max.ele_pos =
					elem_geo.w - (slider_lo.border + slider_lo.gap)
			end

			element.slider.min.glob_pos =
				element.hitbox.x1 + element.slider.min.ele_pos
			element.slider.max.glob_pos =
				element.hitbox.x1 + element.slider.max.ele_pos

			static_ass:draw_start()

			ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h, r1, slider_lo.stype == "diamond")

			ass_draw_rr_h_ccw(static_ass, slider_lo.border, slider_lo.border,
								elem_geo.w - slider_lo.border, elem_geo.h - slider_lo.border,
								r2, slider_lo.stype == "diamond")

			if not (element.slider.markerF == nil) and (slider_lo.gap > 0) then
				local nibble_ass = assdraw.ass_new()
				nibble_ass:draw_start()
				local markers = element.slider.markerF()
				for _,marker in pairs(markers) do
					if (marker > element.slider.min.value) and
						(marker < element.slider.max.value) then

						local s = get_slider_ele_pos_for(element, marker)

						if (slider_lo.gap > 1) then

							local a = slider_lo.gap / 0.5

							if (slider_lo.nibbles_top) then
								nibble_ass:move_to(s - (a/2), slider_lo.border)
								nibble_ass:line_to(s + (a/2), slider_lo.border)
								nibble_ass:line_to(s, foV)
							end

							if (slider_lo.nibbles_bottom) then
								nibble_ass:move_to(s - (a/2),
									elem_geo.h - slider_lo.border)
								nibble_ass:line_to(s,
									elem_geo.h - foV)
								nibble_ass:line_to(s + (a/2),
									elem_geo.h - slider_lo.border)
							end

						else

							if (slider_lo.nibbles_top) then
								nibble_ass:rect_cw(s - 1, slider_lo.border,
									s + 1, slider_lo.border + slider_lo.gap);
							end

							if (slider_lo.nibbles_bottom) then
								nibble_ass:rect_cw(s - 1,
									elem_geo.h -slider_lo.border -slider_lo.gap,
									s + 1, elem_geo.h - slider_lo.border);
							end
						end
					end
				end
				nibble_ass:draw_stop()
				element.nibble_ass = nibble_ass
			end
		end

		element.static_ass = static_ass

		if not (element.enabled) then
			element.layout.alpha[1] = 136
			element.eventresponder = nil
		end
	end
end

function get_chapter(possec)
	local cl = state.chapter_list

	for n=#cl,1,-1 do
		if possec >= cl[n].time then
			return cl[n]
		end
	end
end

function render_elements(master_ass)
	state.forced_title = nil
	local se, ae = state.slider_element, elements[state.active_element]
	if user_opts.chapter_fmt ~= "no" and se and (ae == se or (not ae and mouse_hit(se))) then
		local dur = mp.get_property_number("duration", 0)
		if dur > 0 then
			local possec = get_slider_value(se) * dur / 100
			local ch = get_chapter(possec)
			if ch and ch.title and ch.title ~= "" then
				state.forced_title = string.format(user_opts.chapter_fmt, ch.title)
			end
		end
	end

	for n=1, #elements do
		local element = elements[n]

		local style_ass = assdraw.ass_new()
		style_ass:merge(element.style_ass)
		ass_append_alpha(style_ass, element.layout.alpha, 0)

		if element.type == "button" and element.eventresponder
			and (element.eventresponder["mbtn_left_up"]
				or element.eventresponder["mbtn_left_down"])
			and mouse_hit(element) then
			style_ass:append(osc_styles.elementHover)
		end

		if element.eventresponder and (state.active_element == n) then

			if not (element.eventresponder.render == nil) then
				element.eventresponder.render(element)
			end

			if mouse_hit(element) then
				if (element.styledown) then
					style_ass:append(osc_styles.elementDown)
				end

				if (element.softrepeat) and (state.mouse_down_counter >= 15
					and state.mouse_down_counter % 5 == 0) then

					element.eventresponder[state.active_event_source.."_down"](element)
				end
				state.mouse_down_counter = state.mouse_down_counter + 1
			end

		end

		local elem_ass = assdraw.ass_new()

		elem_ass:merge(style_ass)

		if not (element.type == "button") then
			elem_ass:merge(element.static_ass)
		end

		if (element.type == "slider") then

			local slider_lo = element.layout.slider
			local elem_geo = element.layout.geometry
			local s_min = element.slider.min.value
			local s_max = element.slider.max.value

			local foH, xp
			local pos = element.slider.posF()
			local foV = slider_lo.border + slider_lo.gap
			local innerH = elem_geo.h - (2 * foV)
			local seekRanges = element.slider.seekRangesF()
			local seekRangeLineHeight = innerH / 5

			if slider_lo.stype ~= "bar" then
				foH = elem_geo.h / 2
			else
				foH = slider_lo.border + slider_lo.gap
			end

			if pos then
				xp = get_slider_ele_pos_for(element, pos)

				if slider_lo.stype ~= "bar" then
					if slider_lo.fill_track then
						elem_ass:rect_cw(0, foH - 1.5, xp, foH + 1.5)
					end
					local r = (user_opts.seekbarhandlesize * innerH) / 2
					ass_draw_rr_h_cw(elem_ass, xp - r, foH - r,
									xp + r, foH + r,
									r, slider_lo.stype == "diamond")
				else
					local h = 0
					if seekRanges and user_opts.seekrangeseparate and slider_lo.rtype ~= "inverted" then
						h = seekRangeLineHeight
					end
					elem_ass:rect_cw(foH, foV, xp, elem_geo.h - foV - h)

					if seekRanges and not user_opts.seekrangeseparate and slider_lo.rtype ~= "inverted" then
						for _,range in pairs(seekRanges) do
							if range["start"] < pos then
								local pstart = get_slider_ele_pos_for(element, range["start"])
								local pend = xp

								if pos > range["end"] then
									pend = get_slider_ele_pos_for(element, range["end"])
								end
								elem_ass:rect_ccw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
							end
						end
					end
				end

				if slider_lo.rtype == "slider" then
					ass_draw_rr_h_cw(elem_ass, foH - innerH / 6, foH - innerH / 6,
									xp, foH + innerH / 6,
									innerH / 6, slider_lo.stype == "diamond", 0)
					ass_draw_rr_h_cw(elem_ass, xp, foH - innerH / 15,
									elem_geo.w - foH + innerH / 15, foH + innerH / 15,
									0, slider_lo.stype == "diamond", innerH / 15)
					for _,range in pairs(seekRanges or {}) do
						local pstart = get_slider_ele_pos_for(element, range["start"])
						local pend = get_slider_ele_pos_for(element, range["end"])
						ass_draw_rr_h_ccw(elem_ass, pstart, foH - innerH / 21,
											pend, foH + innerH / 21,
											innerH / 21, slider_lo.stype == "diamond")
					end
				end
			end

			if seekRanges then
				if slider_lo.rtype ~= "inverted" then
					elem_ass:draw_stop()
					elem_ass:merge(element.style_ass)
					ass_append_alpha(elem_ass, element.layout.alpha, user_opts.seekrangealpha)
					elem_ass:merge(element.static_ass)
				end

				for _,range in pairs(seekRanges) do
					local pstart = get_slider_ele_pos_for(element, range["start"])
					local pend = get_slider_ele_pos_for(element, range["end"])

					if slider_lo.rtype == "slider" then
						ass_draw_rr_h_cw(elem_ass, pstart, foH - innerH / 21,
										pend, foH + innerH / 21,
										innerH / 21, slider_lo.stype == "diamond")
					elseif slider_lo.rtype == "line" then
						if slider_lo.stype == "bar" then
							elem_ass:rect_cw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
						else
							ass_draw_rr_h_cw(elem_ass, pstart - innerH / 8, foH - innerH / 8,
											pend + innerH / 8, foH + innerH / 8,
											innerH / 8, slider_lo.stype == "diamond")
						end
					elseif slider_lo.rtype == "bar" then
						if slider_lo.stype ~= "bar" then
							ass_draw_rr_h_cw(elem_ass, pstart - innerH / 2, foV,
											pend + innerH / 2, foV + innerH,
											innerH / 2, slider_lo.stype == "diamond")
						elseif range["end"] >= (pos or 0) then
							elem_ass:rect_cw(pstart, foV, pend, elem_geo.h - foV)
						else
							elem_ass:rect_cw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
						end
					elseif slider_lo.rtype == "inverted" then
						if slider_lo.stype ~= "bar" then
							ass_draw_rr_h_ccw(elem_ass, pstart, (elem_geo.h / 2) - 1, pend,
												(elem_geo.h / 2) + 1,
												1, slider_lo.stype == "diamond")
						else
							elem_ass:rect_ccw(pstart, (elem_geo.h / 2) - 1, pend, (elem_geo.h / 2) + 1)
						end
					end
				end
			end

			elem_ass:draw_stop()

			if element.nibble_ass then
				elem_ass:merge(element.style_ass)
				ass_append_alpha(elem_ass, element.layout.alpha, 0)
				elem_ass:append(osc_styles.seekbarNibbles)
				elem_ass:merge(element.nibble_ass)
			end

			if not (element.slider.tooltipF == nil) then

				if mouse_hit(element) then
					local sliderpos = get_slider_value(element)
					local tooltiplabel = element.slider.tooltipF(sliderpos)

					local an = slider_lo.tooltip_an

					local ty

					if (an == 2) then
						ty = element.hitbox.y1 - slider_lo.border
					else
						ty = element.hitbox.y1 + elem_geo.h/2 - (slider_lo.tooltip_y_offset or 0)
					end

					local tx = get_virt_mouse_pos()
					local thumb_tx = tx
					if (slider_lo.adjust_tooltip) then
						if (an == 2) then
							if (sliderpos < (s_min + 3)) then
								an = an - 1
							elseif (sliderpos > (s_max - 3)) then
								an = an + 1
							end
						elseif (sliderpos > (s_max+s_min)/2) then
							an = an + 1
							tx = tx - 5
						else
							an = an - 1
							tx = tx + 10
						end
					end

					elem_ass:new_event()
					elem_ass:pos(tx, ty)
					elem_ass:an(an)
					elem_ass:append(slider_lo.tooltip_style)
					ass_append_alpha(elem_ass, slider_lo.alpha, 0)
					elem_ass:append(tooltiplabel)

					if not thumbfast.disabled and thumbfast.width ~= 0 and thumbfast.height ~= 0 then
						local osd_w = mp.get_property_number("osd-width")
						if osd_w then
							local r_w, r_h = get_virt_scale_factor()

							local tooltip_font_size = (user_opts.layout == "box" or user_opts.layout == "slimbox") and 2 or 12
							local thumb_ty = user_opts.layout ~= "topbar" and element.hitbox.y1 - 8 or element.hitbox.y2 + tooltip_font_size + 8

							local thumb_pad = 2
							local thumb_margin_x = 20 / r_w
							local thumb_margin_y = (4 + user_opts.tooltipborder) / r_h + thumb_pad
							local thumb_x = math.min(osd_w - thumbfast.width - thumb_margin_x, math.max(thumb_margin_x, thumb_tx / r_w - thumbfast.width / 2))
							local thumb_y = user_opts.layout ~= "topbar" and thumb_ty / r_h - thumbfast.height - tooltip_font_size / r_h - thumb_margin_y or thumb_ty / r_h + thumb_margin_y

							thumb_x = math.floor(thumb_x + 0.5)
							thumb_y = math.floor(thumb_y + 3 / r_h)

							elem_ass:new_event()
							elem_ass:pos(thumb_x * r_w, thumb_y * r_h)
							elem_ass:an(7)
							elem_ass:append(osc_styles.timePosBar .. "{\\1c&H21B6F2}")
							elem_ass:append("{\\1a&H20&}")
							elem_ass:draw_start()
							elem_ass:rect_cw(-thumb_pad * r_w, -thumb_pad * r_h, (thumbfast.width + thumb_pad) * r_w, (thumbfast.height + thumb_pad) * r_h)
							elem_ass:draw_stop()

							mp.commandv("script-message-to", "thumbfast", "thumb",
								mp.get_property_number("duration", 0) * (sliderpos / 100),
								thumb_x,
								thumb_y
							)
						end
					end
				else
					if thumbfast.width ~= 0 and thumbfast.height ~= 0 then
						mp.commandv("script-message-to", "thumbfast", "clear")
					end
				end
			end

		elseif (element.type == "button") then

			local buttontext
			if type(element.content) == "function" then
				buttontext = element.content()
			elseif not (element.content == nil) then
				buttontext = element.content
			end

			local maxchars = element.layout.button.maxchars
			if not (maxchars == nil) and (#buttontext > maxchars) then
				local max_ratio = 1.25
				local limit = math.max(0, math.floor(maxchars * max_ratio) - 3)
				if (#buttontext > limit) then
					while (#buttontext > limit) do
						buttontext = buttontext:gsub(".[\128-\191]*$", "")
					end
					buttontext = buttontext .. "..."
				end
				buttontext = string.format("{\\fscx%f}",
					(maxchars/#buttontext)*100) .. buttontext
			end

			elem_ass:append(buttontext)
		end

		master_ass:merge(elem_ass)
	end
end

function limited_list(prop, pos)
	local proplist = mp.get_property_native(prop, {})
	local count = #proplist
	if count == 0 then
		return count, proplist
	end

	local fs = tonumber(mp.get_property('options/osd-font-size'))
	local max = math.ceil(osc_param.unscaled_y*0.75 / fs)
	if max % 2 == 0 then
		max = max - 1
	end
	local delta = math.ceil(max / 2) - 1
	local begi = math.max(math.min(pos - delta, count - max + 1), 1)
	local endi = math.min(begi + max - 1, count)

	local reslist = {}
	for i=begi, endi do
		local item = proplist[i]
		item.current = (i == pos) and true or nil
		table.insert(reslist, item)
	end
	return count, reslist
end

function get_playlist()
	local pos = mp.get_property_number('playlist-pos', 0) + 1
	local count, limlist = limited_list('playlist', pos)
	if count == 0 then
		return 'Empty playlist.'
	end

	local message = string.format('Playlist [%d/%d]:\n', pos, count)
	for i, v in ipairs(limlist) do
		local _, filename = utils.split_path(v.filename)
		local title = filename
		message = string.format('%s %s %s\n', message,
			(v.current and '●' or '○'), title)
	end
	return message
end

function get_chapterlist()
	local pos = mp.get_property_number('chapter', 0) + 1
	local count, limlist = limited_list('chapter-list', pos)
	if count == 0 then
		return 'No chapters.'
	end

	local message = string.format('Chapters [%d/%d]:\n', pos, count)
	for i, v in ipairs(limlist) do
		local time = mp.format_time(v.time)
		local title = v.title
		if title == nil then
			title = string.format('Chapter %02d', i)
		end
		message = string.format('%s[%s] %s %s\n', message, time,
			(v.current and '●' or '○'), title)
	end
	return message
end

function show_message(text, duration)

	duration = tonumber(duration) or
		(tonumber(mp.get_property("options/osd-duration")) or 1500) / 1000

	text = string.sub(text, 0, 4000)

	text = string.gsub(text, "\n", "\\N")

	state.message_text = text

	if not state.message_hide_timer then
		state.message_hide_timer = mp.add_timeout(0, request_tick)
	end
	state.message_hide_timer:kill()
	state.message_hide_timer.timeout = duration
	state.message_hide_timer:resume()
	request_tick()
end

function render_message(ass)
	if state.message_hide_timer and state.message_hide_timer:is_enabled() and
		state.message_text
	then
		local _, lines = string.gsub(state.message_text, "\\N", "")

		local fontsize = tonumber(mp.get_property("options/osd-font-size"))
		local outline = tonumber(mp.get_property("options/osd-border-size"))
		local maxlines = math.ceil(osc_param.unscaled_y*0.75 / fontsize)
		local counterscale = osc_param.playresy / osc_param.unscaled_y

		fontsize = fontsize * counterscale / math.max(0.65 + math.min(lines/maxlines, 1), 1)
		outline = outline * counterscale / math.max(0.75 + math.min(lines/maxlines, 1)/2, 1)

		local style = "{\\bord" .. outline .. "\\fs" .. fontsize .. "}"

		ass:new_event()
		ass:append(style .. state.message_text)
	else
		state.message_text = nil
	end
end

function new_element(name, type)
	elements[name] = {}
	elements[name].type = type

	elements[name].eventresponder = {}
	elements[name].visible = true
	elements[name].enabled = true
	elements[name].softrepeat = false
	elements[name].styledown = (type == "button")
	elements[name].state = {}

	if (type == "slider") then
		elements[name].slider = {min = {value = 0}, max = {value = 100}}
	end

	return elements[name]
end

function add_layout(name)
	if not (elements[name] == nil) then
		elements[name].layout = {}

		elements[name].layout.layer = 50
		elements[name].layout.alpha = {[1] = 0, [2] = 255, [3] = 255, [4] = 255}

		if (elements[name].type == "button") then
			elements[name].layout.button = {
				maxchars = nil,
			}
		elseif (elements[name].type == "slider") then
			elements[name].layout.slider = {
				border = 1,
				gap = 1,
				nibbles_top = true,
				nibbles_bottom = true,
				stype = "slider",
				adjust_tooltip = true,
				tooltip_style = "",
				tooltip_an = 2,
				alpha = {[1] = 0, [2] = 255, [3] = 88, [4] = 255},
			}
		elseif (elements[name].type == "box") then
			elements[name].layout.box = {radius = 0, hexagon = false}
		end

		return elements[name].layout
	else
		msg.error("Can't add_layout to element \""..name.."\", doesn't exist.")
	end
end

function window_controls(topbar)
	local wc_scale = state.idle and 0.5 or 1
	local wc_geo = {
		x = 0,
		y = (30 + user_opts.barmargin) * wc_scale,
		an = 1,
		w = osc_param.playresx,
		h = 30 * wc_scale,
	}

	local alignment = window_controls_alignment()
	local controlbox_w = window_control_box_width * wc_scale

	local controlbox_left = wc_geo.w - controlbox_w
	local titlebox_left = wc_geo.x
	local titlebox_right = wc_geo.w - controlbox_w

	if alignment == "left" then
		controlbox_left = wc_geo.x
		titlebox_left = wc_geo.x + controlbox_w
		titlebox_right = wc_geo.w
	end

	add_area("window-controls",
			get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an,
								controlbox_w, wc_geo.h))

	local lo, ne

	local button_y = wc_geo.y - (wc_geo.h / 2)
	local first_geo =
		{x = controlbox_left + 5 * wc_scale, y = button_y, an = 4, w = 25 * wc_scale, h = 25 * wc_scale}
	local second_geo =
		{x = controlbox_left + 30 * wc_scale, y = button_y, an = 4, w = 25 * wc_scale, h = 25 * wc_scale}
	local third_geo =
		{x = controlbox_left + 55 * wc_scale, y = button_y, an = 4, w = 25 * wc_scale, h = 25 * wc_scale}

	local wc_style = state.idle
		and osc_styles.wcButtons:gsub("\\fs22", "\\fs11")
		or osc_styles.wcButtons

	ne = new_element("close", "button")
	ne.content = "\238\132\149"
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("quit") end
	lo = add_layout("close")
	lo.geometry = alignment == "left" and first_geo or third_geo
	lo.style = wc_style

	ne = new_element("minimize", "button")
	ne.content = "\238\132\146"
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("cycle", "window-minimized") end
	lo = add_layout("minimize")
	lo.geometry = alignment == "left" and second_geo or first_geo
	lo.style = wc_style

	ne = new_element("maximize", "button")
	if state.maximized or state.fullscreen then
		ne.content = "\238\132\148"
	else
		ne.content = "\238\132\147"
	end
	ne.eventresponder["mbtn_left_up"] =
		function ()
			if state.fullscreen then
				mp.commandv("cycle", "fullscreen")
			else
				mp.commandv("cycle", "window-maximized")
			end
		end
	lo = add_layout("maximize")
	lo.geometry = alignment == "left" and third_geo or second_geo
	lo.style = wc_style
	for _, name in ipairs({"close", "minimize", "maximize"}) do elements[name].layout.alpha[3] = 0 end

	local sh_area_y0, sh_area_y1
	sh_area_y0 = user_opts.barmargin
	sh_area_y1 = wc_geo.y + get_align(1 - (2 * user_opts.deadzonesize),
										osc_param.playresy - wc_geo.y, 0, 0)
	add_area("showhide_wc", wc_geo.x, sh_area_y0, wc_geo.w, sh_area_y1)

	if topbar then
		return
	else
		osc_param.video_margins.t = wc_geo.h / osc_param.playresy
	end

	add_area("window-controls-title",
			titlebox_left, 0, titlebox_right, wc_geo.h)
end

local layouts = {}

layouts["box"] = function ()

	local osc_geo = {
		w = 550,
		h = 138,
		r = 10,
		p = 15,
	}

	if (osc_param.playresx < (osc_geo.w + (2 * osc_geo.p))) then
		osc_param.playresy = (osc_geo.w+(2*osc_geo.p))/osc_param.display_aspect
		osc_param.playresx = osc_param.playresy * osc_param.display_aspect
	end

	local posX = math.floor(get_align(user_opts.halign, osc_param.playresx,
		osc_geo.w, 0))
	local posY = math.floor(get_align(user_opts.valign, osc_param.playresy,
		osc_geo.h, 0))

	local pos_offsetX = (osc_geo.w - (2*osc_geo.p)) / 2
	local pos_offsetY = (osc_geo.h - (2*osc_geo.p)) / 2

	osc_param.areas = {}

	add_area("input", get_hitbox_coords(posX, posY, 5, osc_geo.w, osc_geo.h))

	local sh_area_y0, sh_area_y1
	if user_opts.valign > 0 then
		sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
			posY - (osc_geo.h / 2), 0, 0)
		sh_area_y1 = osc_param.playresy
	else
		sh_area_y0 = 0
		sh_area_y1 = (posY + (osc_geo.h / 2)) +
			get_align(1 - (2*user_opts.deadzonesize),
			osc_param.playresy - (posY + (osc_geo.h / 2)), 0, 0)
	end
	add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

	local osc_w, osc_h, osc_r, osc_p =
		osc_geo.w, osc_geo.h, osc_geo.r, osc_geo.p

	local lo

	new_element("bgbox", "box")
	lo = add_layout("bgbox")

	lo.geometry = {x = posX, y = posY, an = 5, w = osc_w, h = osc_h}
	lo.layer = 10
	lo.style = osc_styles.box
	lo.alpha[1] = user_opts.boxalpha
	lo.alpha[3] = user_opts.boxalpha
	lo.box.radius = osc_r

	local titlerowY = posY - pos_offsetY - 10

	lo = add_layout("title")
	lo.geometry = {x = posX, y = titlerowY, an = 8, w = 496, h = 12}
	lo.style = osc_styles.vidtitle
	lo.button.maxchars = user_opts.boxmaxchars

	lo = add_layout("pl_prev")
	lo.geometry =
		{x = (posX - pos_offsetX), y = titlerowY, an = 7, w = 12, h = 12}
	lo.style = osc_styles.topButtons

	lo = add_layout("pl_next")
	lo.geometry =
		{x = (posX + pos_offsetX), y = titlerowY, an = 9, w = 12, h = 12}
	lo.style = osc_styles.topButtons

	local bigbtnrowY = posY - pos_offsetY + 35
	local bigbtndist = 60

	lo = add_layout("playpause")
	lo.geometry =
		{x = posX, y = bigbtnrowY, an = 5, w = 40, h = 40}
	lo.style = osc_styles.bigButtons

	lo = add_layout("skipback")
	lo.geometry =
		{x = posX - bigbtndist, y = bigbtnrowY, an = 5, w = 40, h = 40}
	lo.style = osc_styles.bigButtons

	lo = add_layout("skipfrwd")
	lo.geometry =
		{x = posX + bigbtndist, y = bigbtnrowY, an = 5, w = 40, h = 40}
	lo.style = osc_styles.bigButtons

	lo = add_layout("ch_prev")
	lo.geometry =
		{x = posX - (bigbtndist * 2), y = bigbtnrowY, an = 5, w = 40, h = 40}
	lo.style = osc_styles.bigButtons

	lo = add_layout("ch_next")
	lo.geometry =
		{x = posX + (bigbtndist * 2), y = bigbtnrowY, an = 5, w = 40, h = 40}
	lo.style = osc_styles.bigButtons

	lo = add_layout("cy_audio")
	lo.geometry =
		{x = posX - pos_offsetX, y = bigbtnrowY, an = 1, w = 70, h = 18}
	lo.style = osc_styles.smallButtonsL

	lo = add_layout("cy_sub")
	lo.geometry =
		{x = posX - pos_offsetX, y = bigbtnrowY, an = 7, w = 70, h = 18}
	lo.style = osc_styles.smallButtonsL

	lo = add_layout("tog_fs")
	lo.geometry =
		{x = posX+pos_offsetX - 25, y = bigbtnrowY, an = 4, w = 25, h = 25}
	lo.style = osc_styles.smallButtonsR

	lo = add_layout("volume")
	lo.geometry =
		{x = posX+pos_offsetX - (25 * 2) - osc_geo.p,
		y = bigbtnrowY, an = 4, w = 25, h = 25}
	lo.style = osc_styles.smallButtonsR

	lo = add_layout("seekbar")
	lo.geometry =
		{x = posX, y = posY+pos_offsetY-22, an = 2, w = pos_offsetX*2, h = 15}
	lo.style = osc_styles.timecodes
	lo.slider.tooltip_style = osc_styles.vidtitle
	lo.slider.stype = user_opts["seekbarstyle"]
	lo.slider.rtype = user_opts["seekrangestyle"]

	local bottomrowY = posY + pos_offsetY - 5

	lo = add_layout("tc_left")
	lo.geometry =
		{x = posX - pos_offsetX, y = bottomrowY, an = 4, w = 110, h = 18}
	lo.style = osc_styles.timecodes

	lo = add_layout("tc_right")
	lo.geometry =
		{x = posX + pos_offsetX, y = bottomrowY, an = 6, w = 110, h = 18}
	lo.style = osc_styles.timecodes

	lo = add_layout("cache")
	lo.geometry =
		{x = posX, y = bottomrowY, an = 5, w = 110, h = 18}
	lo.style = osc_styles.timecodes

end

layouts["slimbox"] = function ()

	local osc_geo = {
		w = 660,
		h = 70,
		r = 10,
	}

	if (osc_param.playresx < (osc_geo.w)) then
		osc_param.playresy = (osc_geo.w)/osc_param.display_aspect
		osc_param.playresx = osc_param.playresy * osc_param.display_aspect
	end

	local posX = math.floor(get_align(user_opts.halign, osc_param.playresx,
		osc_geo.w, 0))
	local posY = math.floor(get_align(user_opts.valign, osc_param.playresy,
		osc_geo.h, 0))

	osc_param.areas = {}

	add_area("input", get_hitbox_coords(posX, posY, 5, osc_geo.w, osc_geo.h))

	local sh_area_y0, sh_area_y1
	if user_opts.valign > 0 then
		sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
			posY - (osc_geo.h / 2), 0, 0)
		sh_area_y1 = osc_param.playresy
	else
		sh_area_y0 = 0
		sh_area_y1 = (posY + (osc_geo.h / 2)) +
			get_align(1 - (2*user_opts.deadzonesize),
			osc_param.playresy - (posY + (osc_geo.h / 2)), 0, 0)
	end
	add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

	local lo

	local tc_w, ele_h, inner_w = 100, 20, osc_geo.w - 100

	local styles = {
		box = "{\\rDefault\\blur0\\bord1\\1c&HH171411\\3c&HFFFFFF}",
		timecodes = "{\\1c&HFFFFFF\\3c&HH171411\\fs20\\bord2\\blur1}",
		tooltip = "{\\1c&HFFFFFF\\3c&HH171411\\fs12\\bord1\\blur0.5}",
	}

	new_element("bgbox", "box")
	lo = add_layout("bgbox")

	lo.geometry = {x = posX, y = posY - 1, an = 2, w = inner_w, h = ele_h}
	lo.layer = 10
	lo.style = osc_styles.box
	lo.alpha[1] = user_opts.boxalpha
	lo.alpha[3] = 0
	if not (user_opts["seekbarstyle"] == "bar") then
		lo.box.radius = osc_geo.r
		lo.box.hexagon = user_opts["seekbarstyle"] == "diamond"
	end

	lo = add_layout("seekbar")
	lo.geometry =
		{x = posX, y = posY - 1, an = 2, w = inner_w, h = ele_h}
	lo.style = osc_styles.timecodes
	lo.slider.border = 0
	lo.slider.gap = 1.5
	lo.slider.tooltip_style = styles.tooltip
	lo.slider.stype = user_opts["seekbarstyle"]
	lo.slider.rtype = user_opts["seekrangestyle"]
	lo.slider.adjust_tooltip = false

	lo = add_layout("tc_left")
	lo.geometry =
		{x = posX - (inner_w/2) + osc_geo.r, y = posY + 1,
		an = 7, w = tc_w, h = ele_h}
	lo.style = styles.timecodes
	lo.alpha[3] = user_opts.boxalpha

	lo = add_layout("tc_right")
	lo.geometry =
		{x = posX + (inner_w/2) - osc_geo.r, y = posY + 1,
		an = 9, w = tc_w, h = ele_h}
	lo.style = styles.timecodes
	lo.alpha[3] = user_opts.boxalpha

	lo = add_layout("cache")
	lo.geometry =
		{x = posX, y = posY + 1,
		an = 8, w = tc_w, h = ele_h}
	lo.style = styles.timecodes
	lo.alpha[3] = user_opts.boxalpha

end

function bar_layout(direction)
	local osc_geo = {
		x = -2,
		y,
		an = (direction < 0) and 7 or 1,
		w,
		h = 46,
	}

	local padX = 8
	local padY = 3
	local itemGap = 4
	local groupGap = 6
	local buttonW = 24
	local volumeW = 72
	local tcScale = (user_opts.tcspace >= 50 and user_opts.tcspace <= 200)
		and user_opts.tcspace / 100 or 1
	local tcW = (state.tc_ms and 132 or 96) * tcScale
	local tsW = 60
	local volGap = 16
	local volIconGap = 16
	local tcTextW = (state.tc_ms and 96 or 67) * tcScale
	local volExtend = math.max(0, tcW - tcTextW - (volIconGap - groupGap))
	local minW = 5*buttonW + 2*tcW + 2*tsW + volumeW +
		2*padX + 6*itemGap + 4*groupGap + volGap + 240

	local padwc_l
	local padwc_r
	if direction < 0 or not window_controls_enabled() then
		padwc_l = 0
		padwc_r = 0
	elseif window_controls_alignment() == "left" then
		padwc_l = window_control_box_width
		padwc_r = 0
	else
		padwc_l = 0
		padwc_r = window_control_box_width
	end

	if ((osc_param.display_aspect > 0) and (osc_param.playresx < minW)) then
		osc_param.playresy = minW / osc_param.display_aspect
		osc_param.playresx = osc_param.playresy * osc_param.display_aspect
	end

	osc_geo.y = direction * (46 + user_opts.barmargin)
	osc_geo.w = osc_param.playresx + 4
	if direction < 0 then
		osc_geo.y = osc_geo.y + osc_param.playresy
	end

	local line1 = osc_geo.y - direction * (8 + padY)
	local line2 = osc_geo.y - direction * (29 + padY)
	local line1TextY = line1 - 1
	local line2TextY = line2 - 1

	osc_param.areas = {}

	add_area("input", get_hitbox_coords(osc_geo.x, osc_geo.y, osc_geo.an,
										osc_geo.w, osc_geo.h))

	local sh_area_y0, sh_area_y1
	if direction > 0 then
		sh_area_y0 = user_opts.barmargin
		sh_area_y1 = osc_geo.y + get_align(1 - (2 * user_opts.deadzonesize),
											osc_param.playresy - osc_geo.y, 0, 0)
	else
		sh_area_y0 = get_align(-1 + (2 * user_opts.deadzonesize), osc_geo.y, 0, 0)
		sh_area_y1 = osc_param.playresy - user_opts.barmargin
	end
	add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

	local lo, geo

	new_element("bgbox", "box")
	lo = add_layout("bgbox")

	lo.geometry = osc_geo
	lo.layer = 10
	lo.style = osc_styles.box
	lo.alpha[1] = user_opts.boxalpha
	lo.box.radius = 0

	geo = { x = osc_geo.x + padX, y = line1,
			an = 4, w = 18, h = 18 - padY }
	lo = add_layout("pl_prev")
	lo.geometry = { x = geo.x + 2, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo.style = osc_styles.topButtonsBar

	geo = { x = geo.x + geo.w + padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo = add_layout("pl_next")
	lo.geometry = { x = geo.x - 1, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo.style = osc_styles.topButtonsBar

	local t_l = geo.x + geo.w + padX

	geo = { x = osc_geo.x + osc_geo.w - padX, y = line1TextY,
		an = 6, w = 150, h = geo.h }
	lo = add_layout("cache")
	lo.geometry = geo
	lo.style = osc_styles.vidtitleBar

	local t_r = geo.x - geo.w - padX*2

	geo = { x = t_l, y = geo.y, an = 4,
			w = t_r - t_l, h = geo.h }
	lo = add_layout("title")
	lo.geometry = geo
	lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}",
		osc_styles.vidtitleBar,
		geo.x, geo.y-geo.h, geo.w, geo.y+geo.h)

	geo = { x = osc_geo.x + padX + padwc_l, y = line2, an = 4,
			w = buttonW, h = 34 - padY*2}
	lo = add_layout("playpause")
	lo.geometry = geo
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x + geo.w + itemGap, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo = add_layout("ch_prev")
	lo.geometry = geo
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x + geo.w + itemGap, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo = add_layout("ch_next")
	lo.geometry = geo
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x + geo.w + groupGap + tcW, y = geo.y, an = 6,
			w = tcW, h = geo.h }
	lo = add_layout("tc_left")
	lo.geometry = {x = geo.x, y = line2TextY, an = geo.an, w = geo.w, h = geo.h}
	lo.style = osc_styles.timecodesBar

	local sb_l = geo.x + groupGap

	geo = { x = osc_geo.x + osc_geo.w - buttonW - padX - padwc_r, y = geo.y, an = 4,
			w = buttonW, h = geo.h }
	lo = add_layout("tog_fs")
	lo.geometry = geo
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x - tsW - groupGap, y = geo.y, an = geo.an, w = tsW, h = geo.h }
	lo = add_layout("cy_sub")
	lo.geometry = {x = geo.x, y = line2TextY, an = geo.an, w = geo.w, h = geo.h}
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x - geo.w - itemGap, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
	lo = add_layout("cy_audio")
	lo.geometry = {x = geo.x, y = line2TextY, an = geo.an, w = geo.w, h = geo.h}
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x - volumeW - volGap, y = geo.y, an = geo.an, w = volumeW, h = 18 }
	geo.x = geo.x - volExtend
	geo.w = volumeW + volExtend
	new_element("volume_track", "box")
	local track = add_layout("volume_track")
	track.geometry = { x = geo.x, y = geo.y, an = geo.an, w = geo.w, h = 3 }
	track.layer = 18
	track.style = osc_styles.volumeTrack
	track.box.radius = 1.5

	lo = add_layout("volume_slider")
	lo.geometry = geo
	lo.style = osc_styles.seekbarGold
	lo.slider.border = 0
	lo.slider.gap = 1
	lo.slider.stype = "knob"
	lo.slider.rtype = "none"
	lo.slider.edge_knob = true
	lo.slider.fill_track = true

	geo = { x = geo.x - buttonW - itemGap, y = geo.y, an = geo.an, w = buttonW, h = 34 - padY*2 }
	lo = add_layout("volume")
	lo.geometry = {x = geo.x, y = line2 - 0, an = geo.an, w = geo.w, h = geo.h}
	lo.style = osc_styles.smallButtonsBar

	geo = { x = geo.x - groupGap - (tcW - volExtend), y = geo.y, an = geo.an,
		w = tcW - volExtend, h = geo.h }
	lo = add_layout("tc_right")
	lo.geometry = {x = geo.x, y = line2TextY, an = geo.an, w = geo.w, h = geo.h}
	lo.style = osc_styles.timecodesBar

	local sb_r = geo.x - groupGap

	geo = { x = sb_l, y = geo.y, an = geo.an,
			w = math.max(0, sb_r - sb_l), h = geo.h - 6 }
	new_element("bgbar1", "box")
	lo = add_layout("bgbar1")

	lo.geometry = geo
	lo.layer = 15
	lo.style = osc_styles.timecodesBar
	lo.alpha[1] =
		math.min(255, user_opts.boxalpha + (255 - user_opts.boxalpha)*0.8)
	if not (user_opts["seekbarstyle"] == "bar") then
		lo.box.radius = geo.h / 2
		lo.box.hexagon = user_opts["seekbarstyle"] == "diamond"
	end

	lo = add_layout("seekbar")
	lo.geometry = geo
	lo.style = osc_styles.seekbarGold
	lo.slider.border = 0
	lo.slider.gap = 2
	lo.slider.tooltip_style = osc_styles.timePosBar
	lo.slider.tooltip_an = 5
	lo.slider.tooltip_y_offset = 1
	lo.slider.stype = user_opts["seekbarstyle"]
	lo.slider.rtype = user_opts["seekrangestyle"]

	if direction < 0 then
		osc_param.video_margins.b = osc_geo.h / osc_param.playresy
	else
		osc_param.video_margins.t = osc_geo.h / osc_param.playresy
	end
end

layouts["bottombar"] = function()
	bar_layout(-1)
end

layouts["topbar"] = function()
	bar_layout(1)
end

function validate_user_opts()
	if layouts[user_opts.layout] == nil then
		msg.warn("Invalid setting \""..user_opts.layout.."\" for layout")
		user_opts.layout = "bottombar"
	end

	if user_opts.seekbarstyle ~= "bar" and
		user_opts.seekbarstyle ~= "diamond" and
		user_opts.seekbarstyle ~= "knob" then
		msg.warn("Invalid setting \"" .. user_opts.seekbarstyle
			.. "\" for seekbarstyle")
		user_opts.seekbarstyle = "bar"
	end

	if user_opts.seekrangestyle ~= "bar" and
		user_opts.seekrangestyle ~= "line" and
		user_opts.seekrangestyle ~= "slider" and
		user_opts.seekrangestyle ~= "inverted" and
		user_opts.seekrangestyle ~= "none" then
		msg.warn("Invalid setting \"" .. user_opts.seekrangestyle
			.. "\" for seekrangestyle")
		user_opts.seekrangestyle = "inverted"
	end

	if user_opts.seekrangestyle == "slider" and
		user_opts.seekbarstyle == "bar" then
		msg.warn("Using \"slider\" seekrangestyle together with \"bar\" seekbarstyle is not supported")
		user_opts.seekrangestyle = "inverted"
	end

	if user_opts.windowcontrols ~= "auto" and
		user_opts.windowcontrols ~= "yes" and
		user_opts.windowcontrols ~= "no" then
		msg.warn("windowcontrols cannot be \"" ..
				user_opts.windowcontrols .. "\". Ignoring.")
		user_opts.windowcontrols = "auto"
	end
	if user_opts.windowcontrols_alignment ~= "right" and
		user_opts.windowcontrols_alignment ~= "left" then
		msg.warn("windowcontrols_alignment cannot be \"" ..
				user_opts.windowcontrols_alignment .. "\". Ignoring.")
		user_opts.windowcontrols_alignment = "right"
	end
end

function update_options(list)
	validate_user_opts()
	request_tick()
	visibility_mode(user_opts.visibility, true)
	update_duration_watch()
	request_init()
end

local UNICODE_MINUS = string.char(0xe2, 0x88, 0x92)

function osc_init()
	msg.debug("osc_init")

	local baseResY = 720
	local display_w, display_h, display_aspect = mp.get_osd_size()
	local scale = 1

	if (mp.get_property("video") == "no") then
		scale = user_opts.scaleforcedwindow
	elseif state.fullscreen then
		scale = user_opts.scalefullscreen
	else
		scale = user_opts.scalewindowed
	end

	if user_opts.vidscale then
		osc_param.unscaled_y = baseResY
	else
		osc_param.unscaled_y = display_h
	end
	osc_param.playresy = osc_param.unscaled_y / scale
	if (display_aspect > 0) then
		osc_param.display_aspect = display_aspect
	end
	osc_param.playresx = osc_param.playresy * osc_param.display_aspect

	state.active_element = nil

	osc_param.video_margins = {l = 0, r = 0, t = 0, b = 0}

	elements = {}

	local pl_count = mp.get_property_number("playlist-count", 0)
	local have_pl = (pl_count > 1)
	local pl_pos = mp.get_property_number("playlist-pos", 0) + 1
	local have_ch = (mp.get_property_number("chapters", 0) > 0)
	local loop = mp.get_property("loop-playlist", "no")

	local ne

	ne = new_element("title", "button")

	ne.content = function ()
		local title = state.forced_title or
						mp.command_native({"expand-text", user_opts.title})
		title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
		return not (title == "") and title or "mpv"
	end

	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("script-binding", "select/select-playlist") end

	ne.eventresponder["mbtn_right_up"] = function ()
		local title = mp.get_property_osd("filename")
		if (have_pl) then
			title = string.format("[%d/%d] %s", countone(pl_pos - 1),
									pl_count, title)
		end
		show_message(title)
	end

	ne = new_element("pl_prev", "button")

	ne.content = "\238\132\144"
	ne.enabled = (pl_pos > 1) or (loop ~= "no")
	ne.eventresponder["mbtn_left_up"] =
		function ()
			mp.commandv("playlist-prev", "weak")
			if user_opts.playlist_osd then
				show_message(get_playlist(), 3)
			end
		end
	ne.eventresponder["shift+mbtn_left_up"] =
		function () show_message(get_playlist(), 3) end
	ne.eventresponder["mbtn_right_up"] =
		function () show_message(get_playlist(), 3) end

	ne = new_element("pl_next", "button")

	ne.content = "\238\132\129"
	ne.enabled = (have_pl and (pl_pos < pl_count)) or (loop ~= "no")
	ne.eventresponder["mbtn_left_up"] =
		function ()
			mp.commandv("playlist-next", "weak")
			if user_opts.playlist_osd then
				show_message(get_playlist(), 3)
			end
		end
	ne.eventresponder["shift+mbtn_left_up"] =
		function () show_message(get_playlist(), 3) end
	ne.eventresponder["mbtn_right_up"] =
		function () show_message(get_playlist(), 3) end

	ne = new_element("playpause", "button")

	ne.content = function ()
		if mp.get_property("pause") == "yes" then
			return ("\238\132\129")
		else
			return ("\238\128\130")
		end
	end
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("cycle", "pause") end

	ne = new_element("skipback", "button")

	ne.softrepeat = true
	ne.content = "\238\128\132"
	ne.eventresponder["mbtn_left_down"] =
		function () mp.commandv("seek", -5, "relative", "keyframes") end
	ne.eventresponder["shift+mbtn_left_down"] =
		function () mp.commandv("frame-back-step") end
	ne.eventresponder["mbtn_right_down"] =
		function () mp.commandv("seek", -30, "relative", "keyframes") end

	ne = new_element("skipfrwd", "button")

	ne.softrepeat = true
	ne.content = "\238\128\133"
	ne.eventresponder["mbtn_left_down"] =
		function () mp.commandv("seek", 10, "relative", "keyframes") end
	ne.eventresponder["shift+mbtn_left_down"] =
		function () mp.commandv("frame-step") end
	ne.eventresponder["mbtn_right_down"] =
		function () mp.commandv("seek", 60, "relative", "keyframes") end

	ne = new_element("ch_prev", "button")

	ne.enabled = have_ch
	ne.content = "\238\132\132"
	ne.eventresponder["mbtn_left_up"] =
		function ()
			mp.commandv("add", "chapter", -1)
			if user_opts.chapters_osd then
				show_message(get_chapterlist(), 3)
			end
		end
	ne.eventresponder["shift+mbtn_left_up"] =
		function () show_message(get_chapterlist(), 3) end
	ne.eventresponder["mbtn_right_up"] =
		function () show_message(get_chapterlist(), 3) end

	ne = new_element("ch_next", "button")

	ne.enabled = have_ch
	ne.content = "\238\132\133"
	ne.eventresponder["mbtn_left_up"] =
		function ()
			mp.commandv("add", "chapter", 1)
			if user_opts.chapters_osd then
				show_message(get_chapterlist(), 3)
			end
		end
	ne.eventresponder["shift+mbtn_left_up"] =
		function () show_message(get_chapterlist(), 3) end
	ne.eventresponder["mbtn_right_up"] =
		function () show_message(get_chapterlist(), 3) end

	update_tracklist()

	ne = new_element("cy_audio", "button")

	ne.enabled = (#tracks_osc.audio > 0)
	ne.content = function ()
		local aid = "–"
		if not (get_track("audio") == 0) then
			aid = get_track("audio")
		end
		return ("\238\132\134" .. osc_styles.smallButtonsLlabel
			.. " " .. aid .. "/" .. #tracks_osc.audio)
	end
	ne.eventresponder["mbtn_left_up"] =
		function () set_track("audio", 1) end
	ne.eventresponder["mbtn_right_up"] =
		function () set_track("audio", -1) end
	ne.eventresponder["shift+mbtn_left_down"] =
		function () show_message(get_tracklist("audio"), 2) end

	if user_opts.scrollcontrols then
		ne.eventresponder["wheel_down_press"] =
			function () set_track("audio", 1) end
		ne.eventresponder["wheel_up_press"] =
			function () set_track("audio", -1) end
	end

	ne = new_element("cy_sub", "button")

	ne.enabled = (#tracks_osc.sub > 0)
	ne.content = function ()
		local sid = "–"
		if not (get_track("sub") == 0) then
			sid = get_track("sub")
		end
		return ("\238\132\135" .. osc_styles.smallButtonsLlabel
			.. " " .. sid .. "/" .. #tracks_osc.sub)
	end
	ne.eventresponder["mbtn_left_up"] =
		function () set_track("sub", 1) end
	ne.eventresponder["mbtn_right_up"] =
		function () set_track("sub", -1) end
	ne.eventresponder["shift+mbtn_left_down"] =
		function () show_message(get_tracklist("sub"), 2) end

	if user_opts.scrollcontrols then
		ne.eventresponder["wheel_down_press"] =
			function () set_track("sub", 1) end
		ne.eventresponder["wheel_up_press"] =
			function () set_track("sub", -1) end
	end

	ne = new_element("tog_fs", "button")
	ne.content = function ()
		if (state.fullscreen) then
			return ("\238\132\137")
		else
			return ("\238\132\136")
		end
	end
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("cycle", "fullscreen") end

	ne = new_element("seekbar", "slider")

	ne.enabled = not (mp.get_property("percent-pos") == nil)
	state.slider_element = ne.enabled and ne or nil
	ne.slider.markerF = function ()
		local duration = mp.get_property_number("duration", nil)
		if duration and duration > 0 then
			local chapters = mp.get_property_native("chapter-list", {})
			local markers = {}
			for n = 1, #chapters do
				markers[n] = (chapters[n].time / duration * 100)
			end
			return markers
		else
			return {}
		end
	end
	ne.slider.posF =
		function () return mp.get_property_number("percent-pos", nil) end
	ne.slider.tooltipF = function (pos)
		local duration = mp.get_property_number("duration", nil)
		if not ((duration == nil) or (pos == nil)) then
			local possec = duration * (pos / 100)
			return mp.format_time(possec)
		else
			return ""
		end
	end
	ne.slider.seekRangesF = function()
		if user_opts.seekrangestyle == "none" then
			return nil
		end
		local cache_state = state.cache_state
		if not cache_state then
			return nil
		end
		local duration = mp.get_property_number("duration", nil)
		if (duration == nil) or duration <= 0 then
			return nil
		end
		local ranges = cache_state["seekable-ranges"]
		if not ranges or #ranges == 0 then
			return nil
		end
		local nranges = {}
		for _, range in pairs(ranges) do
			nranges[#nranges + 1] = {
				["start"] = 100 * range["start"] / duration,
				["end"] = 100 * range["end"] / duration,
			}
		end
		return nranges
	end
	ne.eventresponder["mouse_move"] =
		function (element)
			local seekto = get_slider_value(element)
			if (element.state.lastseek == nil) or
				(not (element.state.lastseek == seekto)) then
					local flags = "absolute-percent"
					if not user_opts.seekbarkeyframes then
						flags = flags .. "+exact"
					end
					mp.commandv("seek", seekto, flags)
					element.state.lastseek = seekto
			end

		end
	ne.eventresponder["mbtn_left_down"] =
		function (element) mp.commandv("seek", get_slider_value(element),
			"absolute-percent", "exact") end
	ne.eventresponder["reset"] =
		function (element) element.state.lastseek = nil end

	if user_opts.scrollcontrols then
		ne.eventresponder["wheel_up_press"] =
			function () mp.commandv("osd-auto", "seek",  10) end
		ne.eventresponder["wheel_down_press"] =
			function () mp.commandv("osd-auto", "seek", -10) end
	end

	ne = new_element("tc_left", "button")

	ne.content = function ()
		if (state.tc_ms) then
			return (mp.get_property_osd("playback-time/full"))
		else
			return (mp.get_property_osd("playback-time"))
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		state.tc_ms = not state.tc_ms
		request_init()
	end

	ne = new_element("tc_right", "button")

	ne.visible = (mp.get_property_number("duration", 0) > 0)
	ne.content = function ()
		if (state.rightTC_trem) then
			local minus = user_opts.unicodeminus and UNICODE_MINUS or "-"
			local property = user_opts.remaining_playtime and "playtime-remaining"
															or "time-remaining"
			if state.tc_ms then
				return (minus..mp.get_property_osd(property .. "/full"))
			else
				return (minus..mp.get_property_osd(property))
			end
		else
			if state.tc_ms then
				return (mp.get_property_osd("duration/full"))
			else
				return (mp.get_property_osd("duration"))
			end
		end
	end
	ne.eventresponder["mbtn_left_up"] =
		function () state.rightTC_trem = not state.rightTC_trem end

	ne = new_element("cache", "button")

	ne.content = function ()
		local cache_state = state.cache_state
		if not (cache_state and cache_state["seekable-ranges"] and
			#cache_state["seekable-ranges"] > 0) then
			return ""
		end
		local dmx_cache = cache_state and cache_state["cache-duration"]
		local thresh = math.min(state.dmx_cache * 0.05, 5)
		if dmx_cache and math.abs(dmx_cache - state.dmx_cache) >= thresh then
			state.dmx_cache = dmx_cache
		else
			dmx_cache = state.dmx_cache
		end
		local min = math.floor(dmx_cache / 60)
		local sec = math.floor(dmx_cache % 60)
		return "Cache: " .. (min > 0 and
			string.format("%sm%02.0fs", min, sec) or
			string.format("%3.0fs", sec))
	end

	ne = new_element("volume", "button")

	ne.content = function()
		local volume = mp.get_property_number("volume", 0)
		local mute = mp.get_property_native("mute")
		local volicon = {"\238\132\139", "\238\132\140",
						"\238\132\141", "\238\132\142"}
		if volume == 0 or mute then
			return "\238\132\138"
		else
			return volicon[math.min(4,math.ceil(volume / (100/3)))]
		end
	end
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("osd-auto", "cycle", "mute") end

	if user_opts.scrollcontrols then
		ne.eventresponder["wheel_up_press"] =
			function () mp.commandv("osd-auto", "add", "volume", 5) end
		ne.eventresponder["wheel_down_press"] =
			function () mp.commandv("osd-auto", "add", "volume", -5) end
	end

	ne = new_element("volume_slider", "slider")
	ne.visible = user_opts.layout == "bottombar" or user_opts.layout == "topbar"
	ne.slider.min.value = 0
	ne.slider.max.value = 100
	ne.slider.posF = function()
		return math.min(100, math.max(0, mp.get_property_number("volume", 0)))
	end
	ne.slider.seekRangesF = function() return nil end
	local function set_slider_volume(element)
		local level = math.floor(get_slider_value(element) + 0.5)
		mp.commandv("osd-auto", "set", "volume", level)
		if mp.get_property_native("mute") then mp.set_property("mute", "no") end
	end
	ne.eventresponder["mbtn_left_down"] = set_slider_volume
	ne.eventresponder["mouse_move"] = set_slider_volume
	if user_opts.scrollcontrols then
		ne.eventresponder["wheel_up_press"] =
			function() mp.commandv("osd-auto", "add", "volume", 5) end
		ne.eventresponder["wheel_down_press"] =
			function() mp.commandv("osd-auto", "add", "volume", -5) end
	end

	layouts[user_opts.layout]()

	if window_controls_enabled() then
		window_controls(user_opts.layout == "topbar")
	end

	prepare_elements()

	update_margins()
end

function reset_margins()
	if state.using_video_margins then
		for _, opt in ipairs(margins_opts) do
			mp.set_property_number(opt[2], 0.0)
		end
		state.using_video_margins = false
	end
end

function update_margins()
	local margins = osc_param.video_margins

	if (not state.osc_visible) or (get_hidetimeout() >= 0) or
		(state.fullscreen and not user_opts.showfullscreen) or
		(not state.fullscreen and not user_opts.showwindowed)
	then
		margins = {l = 0, r = 0, t = 0, b = 0}
	end

	if user_opts.boxvideo then
		local margins_used = false

		if not state.using_video_margins then
			for _, opt in ipairs(margins_opts) do
				if mp.get_property_number(opt[2], 0.0) ~= 0.0 then
					margins_used = true
				end
			end
		end

		if not margins_used then
			for _, opt in ipairs(margins_opts) do
				local v = margins[opt[1]]
				if (v ~= 0) or state.using_video_margins then
					mp.set_property_number(opt[2], v)
					state.using_video_margins = true
				end
			end
		end
	else
		reset_margins()
	end

	if mp.del_property then
	mp.set_property_native("user-data/osc/margins", margins)
	elseif utils.shared_script_property_set then
	utils.shared_script_property_set("osc-margins",
		string.format("%f,%f,%f,%f", margins.l, margins.r, margins.t, margins.b))
	end
end

function shutdown()
	reset_margins()
	if mp.del_property then
	mp.del_property("user-data/osc")
	elseif utils.shared_script_property_set then
	utils.shared_script_property_set("osc-margins", nil)
	end
end

function show_osc()
	if not state.enabled then return end

	msg.trace("show_osc")
	state.showtime = mp.get_time()

	osc_visible(true)

	if (user_opts.fadeduration > 0) then
		state.anitype = nil
	end
end

function hide_osc()
	msg.trace("hide_osc")
	if thumbfast.width ~= 0 and thumbfast.height ~= 0 then
		mp.commandv("script-message-to", "thumbfast", "clear")
	end
	if not state.enabled then
		state.osc_visible = false
		render_wipe()
	elseif (user_opts.fadeduration > 0) then
		if not(state.osc_visible == false) then
			state.anitype = "out"
			request_tick()
		end
	else
		osc_visible(false)
	end
end

function osc_visible(visible)
	if state.osc_visible ~= visible then
		state.osc_visible = visible
		update_margins()
	end
	request_tick()
end

function pause_state(name, enabled)
	state.paused = enabled
	request_tick()
end

function cache_state(name, st)
	state.cache_state = st
	request_tick()
end

function request_tick()
	if state.tick_timer == nil then
		state.tick_timer = mp.add_timeout(0, tick)
	end

	if not state.tick_timer:is_enabled() then
		local now = mp.get_time()
		local timeout = tick_delay - (now - state.tick_last_time)
		if timeout < 0 then
			timeout = 0
		end
		state.tick_timer.timeout = timeout
		state.tick_timer:resume()
	end
end

function mouse_leave()
	if get_hidetimeout() >= 0 then
		hide_osc()
	end
	state.last_mouseX, state.last_mouseY = nil, nil
	state.mouse_in_window = false
end

function request_init()
	state.initREQ = true
	request_tick()
end

function request_init_resize()
	request_init()
	state.tick_timer:kill()
	state.tick_timer.timeout = 0
	state.tick_timer:resume()
end

function render_wipe()
	msg.trace("render_wipe()")
	if state.osd then
	state.osd.data = ""
	state.osd:remove()
	else
	set_osd(0, 0, "{}")
	end
end

function render()
	msg.trace("rendering")
	local current_screen_sizeX, current_screen_sizeY, aspect = mp.get_osd_size()
	local mouseX, mouseY = get_virt_mouse_pos()
	local now = mp.get_time()

	if not (state.mp_screen_sizeX == current_screen_sizeX
		and state.mp_screen_sizeY == current_screen_sizeY) then

		request_init_resize()

		state.mp_screen_sizeX = current_screen_sizeX
		state.mp_screen_sizeY = current_screen_sizeY
	end

	if state.active_element then
		request_tick()
	elseif state.initREQ then
		osc_init()
		state.initREQ = false

		if (state.last_mouseX == nil or state.last_mouseY == nil)
			and not (mouseX == nil or mouseY == nil) then

			state.last_mouseX, state.last_mouseY = mouseX, mouseY
		end
	end

	if not(state.anitype == nil) then

		if (state.anistart == nil) then
			state.anistart = now
		end

		if (now < state.anistart + (user_opts.fadeduration/1000)) then

			if (state.anitype == "in") then
				osc_visible(true)
				state.animation = scale_value(state.anistart,
					(state.anistart + (user_opts.fadeduration/1000)),
					255, 0, now)
			elseif (state.anitype == "out") then
				state.animation = scale_value(state.anistart,
					(state.anistart + (user_opts.fadeduration/1000)),
					0, 255, now)
			end

		else
			if (state.anitype == "out") then
				osc_visible(false)
			end
			kill_animation()
		end
	else
		kill_animation()
	end

	for k,cords in pairs(osc_param.areas["showhide"]) do
		set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "thumbfast-osc-showhide")
	end
	if osc_param.areas["showhide_wc"] then
		for k,cords in pairs(osc_param.areas["showhide_wc"]) do
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "thumbfast-osc-showhide_wc")
		end
	else
		set_virt_mouse_area(0, 0, 0, 0, "thumbfast-osc-showhide_wc")
	end
	do_enable_keybindings()

	local mouse_over_osc = false

	for _,cords in ipairs(osc_param.areas["input"]) do
		if state.osc_visible then
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "thumbfast-osc-input")
		end
		if state.osc_visible ~= state.input_enabled then
			if state.osc_visible then
				mp.enable_key_bindings("thumbfast-osc-input")
			else
				mp.disable_key_bindings("thumbfast-osc-input")
			end
			state.input_enabled = state.osc_visible
		end

		if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
			mouse_over_osc = true
		end
	end

	if osc_param.areas["window-controls"] then
		for _,cords in ipairs(osc_param.areas["window-controls"]) do
			if state.osc_visible then
				set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "thumbfast-osc-window-controls")
			end
			if state.osc_visible ~= state.windowcontrols_buttons then
				if state.osc_visible then
					mp.enable_key_bindings("thumbfast-osc-window-controls")
				else
					mp.disable_key_bindings("thumbfast-osc-window-controls")
				end
				state.windowcontrols_buttons = state.osc_visible
			end

			if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
				mouse_over_osc = true
			end
		end
	end

	if osc_param.areas["window-controls-title"] then
		for _,cords in ipairs(osc_param.areas["window-controls-title"]) do
			if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
				mouse_over_osc = true
			end
		end
	end

	if not (state.showtime == nil) and (get_hidetimeout() >= 0) then
		local timeout = state.showtime + (get_hidetimeout()/1000) - now
		if timeout <= 0 then
			if (state.active_element == nil) and not (mouse_over_osc) then
				hide_osc()
			end
		else
			if not state.hide_timer then
				state.hide_timer = mp.add_timeout(0, tick)
			end
			state.hide_timer.timeout = timeout
			state.hide_timer:kill()
			state.hide_timer:resume()
		end
	end

	local ass = assdraw.ass_new()

	render_message(ass)

	if state.osc_visible then
		render_elements(ass)
	end

	set_osd(osc_param.playresy * osc_param.display_aspect,
			osc_param.playresy, ass.text, 1000)
end

local function element_has_action(element, action)
	return element and element.eventresponder and
		element.eventresponder[action]
end

function process_event(source, what)
	local action = string.format("%s%s", source,
		what and ("_" .. what) or "")

	if what == "down" or what == "press" then

		for n = 1, #elements do

			if mouse_hit(elements[n]) and
				elements[n].eventresponder and
				(elements[n].eventresponder[source .. "_up"] or
					elements[n].eventresponder[action]) then

				if what == "down" then
					state.active_element = n
					state.active_event_source = source
				end
				if element_has_action(elements[n], action) then
					elements[n].eventresponder[action](elements[n])
				end

			end
		end

	elseif what == "up" then

		if elements[state.active_element] then
			local n = state.active_element

			if n == 0 then
			elseif element_has_action(elements[n], action) and
				mouse_hit(elements[n]) then

				elements[n].eventresponder[action](elements[n])
			end

			if element_has_action(elements[n], "reset") then
				elements[n].eventresponder["reset"](elements[n])
			end

		end
		state.active_element = nil
		state.mouse_down_counter = 0

	elseif source == "mouse_move" then

		state.mouse_in_window = true

		local mouseX, mouseY = get_virt_mouse_pos()
		if (user_opts.minmousemove == 0) or
			(not ((state.last_mouseX == nil) or (state.last_mouseY == nil)) and
				((math.abs(mouseX - state.last_mouseX) >= user_opts.minmousemove)
					or (math.abs(mouseY - state.last_mouseY) >= user_opts.minmousemove)
				)
			) then
			show_osc()
		end
		state.last_mouseX, state.last_mouseY = mouseX, mouseY

		local n = state.active_element
		if element_has_action(elements[n], action) then
			elements[n].eventresponder[action](elements[n])
		end
	end

	request_tick()
end

local logo_lines = {
	"{\\c&H1a1a1a&\\fscx90\\fscy90\\p4}m 500 250 b 500 388 388 500 250 500 b 112 500 0 388 0 250 b 0 112 112 0 250 0 b 388 0 500 112 500 250{\\p0}",
	"{\\c&H21B6F2&\\fscx90\\fscy90\\p4}m 500 250 b 500 388 388 500 250 500 b 112 500 0 388 0 250 b 0 112 112 0 250 0 b 388 0 500 112 500 250 m 479 250 b 479 123 376 21 250 21 b 124 21 21 123 21 250 b 21 377 124 479 250 479 b 376 479 479 377 479 250{\\p0}",
	"{\\c&H21B6F2&\\fscx90\\fscy90\\p4}m 373 163 b 367 167 359 169 350 170 b 349 170 349 171 350 172 b 373 195 388 228 388 263 b 388 292 378 319 362 340 b 362 340 362 341 362 341 b 369 348 373 354 378 360 b 399 333 412 299 412 263 b 412 225 398 190 375 163 b 374 163 374 163 373 163 l 373 163 m 125 235 b 122 238 118 240 112 240 b 110 240 108 240 106 239 b 105 247 104 255 104 263 b 104 276 106 289 109 301 b 109 302 109 301 110 301 b 111 300 113 299 114 299 b 120 298 127 297 132 293 b 132 293 132 293 132 292 b 129 283 128 273 128 263 b 128 254 129 245 131 237 b 132 230 128 232 125 235 l 125 235 m 204 381 b 197 387 190 392 181 396 b 181 396 181 396 181 396 b 204 409 230 417 258 417 b 280 417 301 412 319 404 b 321 404 321 403 320 402 b 313 397 305 391 298 387 b 298 386 298 386 298 386 b 285 391 272 393 258 393 b 239 393 221 388 204 381 b 204 381 204 381 204 381 l 204 381{\\p0}",
	"{\\c&HFFFFFF&\\fscx90\\fscy90\\p4}m 160 300 b 177 289 195 279 212 270 b 212 275 211 282 210 287 b 194 293 177 298 160 300 m 141 153 b 136 129 129 117 122 117 b 118 117 115 121 115 127 b 115 141 110 155 100 169 b 92 178 88 187 88 193 b 88 203 91 212 96 221 b 99 226 105 229 112 229 b 120 229 128 216 137 189 b 145 176 166 164 201 151 b 200 153 200 155 200 157 b 200 160 204 163 211 168 l 213 186 b 201 190 189 192 179 195 l 159 195 b 155 195 154 197 154 199 b 154 202 156 204 161 207 b 172 215 181 218 189 218 b 192 218 200 217 214 214 l 214 228 b 200 231 186 236 172 241 l 160 240 b 157 240 156 241 156 243 b 156 246 158 249 162 251 b 174 257 185 259 195 259 b 174 276 154 291 133 305 l 117 310 b 113 311 111 315 111 324 b 113 337 120 343 129 343 b 133 343 138 341 146 340 b 167 332 185 326 200 321 b 180 353 152 374 118 384 b 112 386 108 388 108 391 b 108 395 114 396 125 396 b 134 396 141 396 146 395 b 186 391 213 369 228 333 b 267 353 299 372 324 392 b 339 403 351 408 359 408 b 371 408 378 401 378 388 b 378 373 364 355 337 336 b 321 326 287 320 233 315 l 235 310 b 256 304 282 297 310 288 b 335 282 347 274 347 265 b 347 257 340 250 327 246 b 324 245 319 244 313 244 b 303 244 291 241 279 236 b 285 243 291 250 299 257 b 279 265 258 272 237 280 b 238 272 239 263 240 255 b 244 251 253 247 265 244 b 271 243 274 240 274 234 b 274 229 271 224 264 221 b 258 219 253 218 249 218 l 239 219 l 240 207 b 249 205 259 204 269 201 b 279 198 284 194 284 189 b 284 182 281 177 275 175 b 265 170 258 168 252 168 b 250 168 247 171 242 176 b 243 170 244 163 244 159 b 244 153 239 148 228 143 b 258 135 289 130 319 130 b 304 147 282 157 255 161 b 273 168 287 171 296 171 b 308 171 324 167 348 159 b 366 158 375 152 375 142 b 375 134 366 123 350 111 b 343 108 338 106 335 106 b 331 106 326 106 319 108 b 301 108 279 111 253 117 b 256 114 258 109 258 103 b 258 95 254 88 244 81 b 234 75 216 72 191 69 b 187 68 180 67 178 67 b 177 68 176 69 176 72 b 176 81 185 91 202 100 b 188 107 174 111 160 116 b 169 117 176 118 182 118 b 195 118 212 117 234 115 b 238 117 242 118 246 119 b 207 128 172 139 141 153 l 141 153{\\p0}",
}

local santa_hat_lines = {
	"{\\c&HC0C0C0&\\p6}m 500 -323 b 491 -322 481 -318 475 -311 465 -312 456 -319 446 -318 434 -314 427 -304 417 -297 410 -290 404 -282 395 -278 390 -274 387 -267 381 -265 377 -261 379 -254 384 -253 397 -244 409 -232 425 -228 437 -228 446 -218 457 -217 462 -216 466 -213 468 -209 471 -205 477 -203 482 -206 491 -211 499 -217 508 -222 532 -235 556 -249 576 -267 584 -272 584 -284 578 -290 569 -305 550 -312 533 -309 523 -310 515 -316 507 -321 505 -323 503 -323 500 -323{\\p0}",
	"{\\c&HE0E0E0&\\p6}m 315 -260 b 286 -258 259 -240 246 -215 235 -210 222 -215 211 -211 204 -188 177 -176 172 -151 170 -139 163 -128 154 -121 143 -103 141 -81 143 -60 139 -46 125 -34 129 -17 132 -1 134 16 142 30 145 56 161 80 181 96 196 114 210 133 231 144 266 153 303 138 328 115 373 79 401 28 423 -24 446 -73 465 -123 483 -174 487 -199 467 -225 442 -227 421 -232 402 -242 384 -254 364 -259 342 -250 322 -260 320 -260 317 -261 315 -260{\\p0}",
	"{\\c&H0000F0&\\p6}m 1151 -523 b 1016 -516 891 -458 769 -406 693 -369 624 -319 561 -262 526 -252 465 -235 479 -187 502 -147 551 -135 588 -111 1115 165 1379 232 1909 761 1926 800 1952 834 1987 858 2020 883 2053 912 2065 952 2088 1000 2146 962 2139 919 2162 836 2156 747 2143 662 2131 615 2116 567 2122 517 2120 410 2090 306 2089 199 2092 147 2071 99 2034 64 1987 5 1928 -41 1869 -86 1777 -157 1712 -256 1629 -337 1578 -389 1521 -436 1461 -476 1407 -509 1343 -507 1284 -515 1240 -519 1195 -521 1151 -523{\\p0}",
	"{\\c&H0000AA&\\p6}m 1657 248 b 1658 254 1659 261 1660 267 1669 276 1680 284 1689 293 1695 302 1700 311 1707 320 1716 325 1726 330 1735 335 1744 347 1752 360 1761 371 1753 352 1754 331 1753 311 1751 237 1751 163 1751 90 1752 64 1752 37 1767 14 1778 -3 1785 -24 1786 -45 1786 -60 1786 -77 1774 -87 1760 -96 1750 -78 1751 -65 1748 -37 1750 -8 1750 20 1734 78 1715 134 1699 192 1694 211 1689 231 1676 246 1671 251 1661 255 1657 248 m 1909 541 b 1914 542 1922 549 1917 539 1919 520 1921 502 1919 483 1918 458 1917 433 1915 407 1930 373 1942 338 1947 301 1952 270 1954 238 1951 207 1946 214 1947 229 1945 239 1939 278 1936 318 1924 356 1923 362 1913 382 1912 364 1906 301 1904 237 1891 175 1887 150 1892 126 1892 101 1892 68 1893 35 1888 2 1884 -9 1871 -20 1859 -14 1851 -6 1854 9 1854 20 1855 58 1864 95 1873 132 1883 179 1894 225 1899 273 1908 362 1910 451 1909 541{\\p0}",
	"{\\c&HF8F8F8&\\p6}m 626 -191 b 565 -155 486 -196 428 -151 387 -115 327 -101 304 -47 273 2 267 59 249 113 219 157 217 213 215 265 217 309 260 302 285 283 373 264 465 264 555 257 608 252 655 292 709 287 759 294 816 276 863 298 903 340 972 324 1012 367 1061 394 1125 382 1167 424 1213 462 1268 482 1322 506 1385 546 1427 610 1479 662 1510 690 1534 725 1566 752 1611 796 1664 830 1703 880 1740 918 1747 986 1805 1005 1863 991 1897 932 1916 880 1914 823 1945 777 1961 725 1979 673 1957 622 1938 575 1912 534 1862 515 1836 473 1790 417 1755 351 1697 305 1658 266 1633 216 1593 176 1574 138 1539 116 1497 110 1448 101 1402 77 1371 37 1346 -16 1295 15 1254 6 1211 -27 1170 -62 1121 -86 1072 -104 1027 -128 976 -133 914 -130 851 -137 794 -162 740 -181 679 -168 626 -191 m 2051 917 b 1971 932 1929 1017 1919 1091 1912 1149 1923 1214 1970 1254 2000 1279 2027 1314 2066 1325 2139 1338 2212 1295 2254 1238 2281 1203 2287 1158 2282 1116 2292 1061 2273 1006 2229 970 2206 941 2167 938 2138 918{\\p0}",
}

local function init_idle_window_controls(display_w, display_h)
	osc_param.playresx, osc_param.playresy = display_w, display_h
	osc_param.areas = {}
	elements = {}
	state.slider_element = nil
	if window_controls_enabled() then
		window_controls(true)
		prepare_elements()
	end
end

function tick()
	if state.marginsREQ == true then
		update_margins()
		state.marginsREQ = false
	end

	if (not state.enabled) then return end

	if (state.idle) then

		msg.trace("idle message")
		local osd_w, osd_h, display_aspect = mp.get_osd_size()
		if display_aspect == 0 then
			return
		end
		local display_h = 360
		local display_w = display_h * display_aspect

		if state.active_element then
			request_tick()
		elseif state.initREQ or not state.idle_wc_ready
			or state.mp_screen_sizeX ~= osd_w or state.mp_screen_sizeY ~= osd_h then
			init_idle_window_controls(display_w, display_h)
			state.mp_screen_sizeX, state.mp_screen_sizeY = osd_w, osd_h
			state.idle_wc_ready = true
			state.initREQ = false
		end
		local icon_x, icon_y = (display_w - 1800 / 32) / 2, 140
		local line_prefix = ("{\\rDefault\\an7\\1a&H00&\\bord0\\shad0\\pos(%f,%f)}"):format(icon_x, icon_y)

		local ass = assdraw.ass_new()
		if user_opts.idlescreen then
			for i, line in ipairs(logo_lines) do
				ass:new_event()
				ass:append(line_prefix .. line)
			end
		end

		if is_december and user_opts.idlescreen and not user_opts.greenandgrumpy then
			for i, line in ipairs(santa_hat_lines) do
				ass:new_event()
				ass:append(line_prefix .. line)
			end
		end

		if user_opts.idlescreen then
			ass:new_event()
			ass:pos(display_w / 2, icon_y + 65)
			ass:an(8)
			ass:append("Drop files or URLs to play here.")
		end
		mp.disable_key_bindings("thumbfast-osc-input")
		set_virt_mouse_area(0, 0, 0, 0, "thumbfast-osc-input")
		state.input_enabled = false
		if osc_param.areas["window-controls"] then
			for _, cords in ipairs(osc_param.areas["window-controls"]) do
				set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "thumbfast-osc-window-controls")
			end
			mp.enable_key_bindings("thumbfast-osc-window-controls")
			state.windowcontrols_buttons = true
			render_elements(ass)
		else
			set_virt_mouse_area(0, 0, 0, 0, "thumbfast-osc-window-controls")
			mp.disable_key_bindings("thumbfast-osc-window-controls")
			state.windowcontrols_buttons = false
		end
		set_osd(display_w, display_h, ass.text, -1000)

		if state.showhide_enabled then
			mp.disable_key_bindings("thumbfast-osc-showhide")
			mp.disable_key_bindings("thumbfast-osc-showhide_wc")
			state.showhide_enabled = false
		end

	elseif (state.fullscreen and user_opts.showfullscreen)
		or (not state.fullscreen and user_opts.showwindowed) then

		render()
	else
		render_wipe()
	end

	state.tick_last_time = mp.get_time()

	if state.anitype ~= nil then
		if not state.idle and
			(not state.anistart or
			mp.get_time() < 1 + state.anistart + user_opts.fadeduration/1000)
		then
			request_tick()
		else
			kill_animation()
		end
	end
end

function do_enable_keybindings()
	if state.enabled then
		if not state.showhide_enabled then
			mp.enable_key_bindings("thumbfast-osc-showhide", "allow-vo-dragging+allow-hide-cursor")
			mp.enable_key_bindings("thumbfast-osc-showhide_wc", "allow-vo-dragging+allow-hide-cursor")
		end
		state.showhide_enabled = true
	end
end

function enable_osc(enable)
	state.enabled = enable
	if enable then
		do_enable_keybindings()
	else
		hide_osc()
		if state.showhide_enabled then
			mp.disable_key_bindings("thumbfast-osc-showhide")
			mp.disable_key_bindings("thumbfast-osc-showhide_wc")
		end
		state.showhide_enabled = false
	end
end

function on_duration() request_init() end

local duration_watched = false
function update_duration_watch()
	local want_watch = user_opts.livemarkers and
						(mp.get_property_number("chapters", 0) or 0) > 0 and
						true or false

	if (want_watch ~= duration_watched) then
		if want_watch then
			mp.observe_property("duration", nil, on_duration)
		else
			mp.unobserve_property(on_duration)
		end
		duration_watched = want_watch
	end
end

validate_user_opts()
update_duration_watch()

mp.register_event("shutdown", shutdown)
mp.register_event("start-file", request_init)
mp.observe_property("track-list", nil, request_init)
mp.observe_property("playlist", nil, request_init)
mp.observe_property("chapter-list", "native", function(_, list)
	list = list or {}
	table.sort(list, function(a, b) return a.time < b.time end)
	state.chapter_list = list
	update_duration_watch()
	request_init()
end)

mp.register_script_message("osc-message", show_message)
mp.register_script_message("osc-chapterlist", function(dur)
	show_message(get_chapterlist(), dur)
end)
mp.register_script_message("osc-playlist", function(dur)
	show_message(get_playlist(), dur)
end)
mp.register_script_message("osc-tracklist", function(dur)
	local msg = {}
	for k,v in pairs(nicetypes) do
		table.insert(msg, get_tracklist(k))
	end
	show_message(table.concat(msg, '\n\n'), dur)
end)

mp.observe_property("fullscreen", "bool",
	function(name, val)
		state.fullscreen = val
		state.marginsREQ = true
		request_init_resize()
	end
)
mp.observe_property("border", "bool",
	function(name, val)
		state.border = val
		request_init_resize()
	end
)
mp.observe_property("title-bar", "bool",
	function(name, val)
		state.title_bar = val
		request_init_resize()
	end
)
mp.observe_property("window-maximized", "bool",
	function(name, val)
		state.maximized = val
		request_init_resize()
	end
)
mp.observe_property("idle-active", "bool",
	function(name, val)
		state.idle = val
		state.active_element = nil
		state.idle_wc_ready = false
		request_init()
	end
)
mp.observe_property("pause", "bool", pause_state)
mp.observe_property("demuxer-cache-state", "native", cache_state)
mp.observe_property("vo-configured", "bool", function(name, val)
	request_tick()
end)
mp.observe_property("playback-time", "number", function(name, val)
	request_tick()
end)
mp.observe_property("osd-dimensions", "native", function(name, val)
	request_init_resize()
end)

mp.set_key_bindings({
	{"mouse_move",              function(e) process_event("mouse_move", nil) end},
	{"mouse_leave",             mouse_leave},
}, "thumbfast-osc-showhide", "force")
mp.set_key_bindings({
	{"mouse_move",              function(e) process_event("mouse_move", nil) end},
	{"mouse_leave",             mouse_leave},
}, "thumbfast-osc-showhide_wc", "force")
do_enable_keybindings()

mp.set_key_bindings({
	{"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
							function(e) process_event("mbtn_left", "down")  end},
	{"shift+mbtn_left",     function(e) process_event("shift+mbtn_left", "up") end,
							function(e) process_event("shift+mbtn_left", "down")  end},
	{"mbtn_right",          function(e) process_event("mbtn_right", "up") end,
							function(e) process_event("mbtn_right", "down")  end},
	{"mbtn_mid",            function(e) process_event("shift+mbtn_left", "up") end,
							function(e) process_event("shift+mbtn_left", "down")  end},
	{"wheel_up",            function(e) process_event("wheel_up", "press") end},
	{"wheel_down",          function(e) process_event("wheel_down", "press") end},
	{"mbtn_left_dbl",       "ignore"},
	{"shift+mbtn_left_dbl", "ignore"},
	{"mbtn_right_dbl",      "ignore"},
}, "thumbfast-osc-input", "force")
mp.enable_key_bindings("thumbfast-osc-input")

mp.set_key_bindings({
	{"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
							function(e) process_event("mbtn_left", "down")  end},
	{"mouse_move",          function()
		if state.idle then
			state.mouse_in_window = true
			request_tick()
		else
			process_event("mouse_move", nil)
		end
	end},
	{"mouse_leave",         function()
		if state.idle then
			state.mouse_in_window = false
			request_tick()
		else
			mouse_leave()
		end
	end},
}, "thumbfast-osc-window-controls", "force")
mp.enable_key_bindings("thumbfast-osc-window-controls")

function get_hidetimeout()
	if user_opts.visibility == "always" then
		return -1
	end
	return user_opts.hidetimeout
end

function always_on(val)
	if state.enabled then
		if val then
			show_osc()
		else
			hide_osc()
		end
	end
end

function visibility_mode(mode, no_osd)
	if mode == "cycle" then
		if not state.enabled then
			mode = "auto"
		elseif user_opts.visibility ~= "always" then
			mode = "always"
		else
			mode = "never"
		end
	end

	if mode == "auto" then
		always_on(false)
		enable_osc(true)
	elseif mode == "always" then
		enable_osc(true)
		always_on(true)
	elseif mode == "never" then
		enable_osc(false)
	else
		msg.warn("Ignoring unknown visibility mode '" .. mode .. "'")
		return
	end

	user_opts.visibility = mode
	if mp.del_property then
	mp.set_property_native("user-data/osc/visibility", mode)
	elseif utils.shared_script_property_set then
	utils.shared_script_property_set("osc-visibility", mode)
	end

	if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
		mp.osd_message("OSC visibility: " .. mode)
	end

	mp.disable_key_bindings("thumbfast-osc-input")
	mp.disable_key_bindings("thumbfast-osc-window-controls")
	state.input_enabled = false

	update_margins()
	request_tick()
end

function idlescreen_visibility(mode, no_osd)
	if mode == "cycle" then
		if user_opts.idlescreen then
			mode = "no"
		else
			mode = "yes"
		end
	end

	if mode == "yes" then
		user_opts.idlescreen = true
	else
		user_opts.idlescreen = false
	end

	if mp.del_property then
	mp.set_property_native("user-data/osc/idlescreen", user_opts.idlescreen)
	elseif utils.shared_script_property_set then
	utils.shared_script_property_set("osc-idlescreen", mode)
	end

	if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
		mp.osd_message("OSC logo visibility: " .. tostring(mode))
	end

	request_tick()
end

visibility_mode(user_opts.visibility, true)
mp.register_script_message("osc-visibility", visibility_mode)
mp.add_key_binding(nil, "visibility", function() visibility_mode("cycle") end)

mp.register_script_message("osc-idlescreen", idlescreen_visibility)

mp.register_script_message("thumbfast-info", function(json)
	local data = utils.parse_json(json)
	if type(data) ~= "table" or not data.width or not data.height then
		msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
	else
		thumbfast = data
	end
end)

set_virt_mouse_area(0, 0, 0, 0, "thumbfast-osc-input")
set_virt_mouse_area(0, 0, 0, 0, "thumbfast-osc-window-controls")
