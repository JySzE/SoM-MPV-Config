-- Version 1.2
-- 10/28/26
-- by [SoM] Nikosan

-- Ctrl+g: open/close the export menu. Mark start/end from inside the menu.

local mp = require 'mp'
local utils = require 'mp.utils'
local input = require 'mp.input'

local is_windows_os = package.config:sub(1, 1) == '\\'
local exec_dir = mp.command_native({'expand-path', '~~/exec'})

local function executable_path(name)
	local bundled = utils.join_path(exec_dir, name)
	local bundled_info = utils.file_info(bundled)
	if bundled_info and bundled_info.is_file then return bundled end
	local separator = is_windows_os and ';' or ':'
	for dir in (os.getenv('PATH') or ''):gmatch('[^' .. separator .. ']+') do
		dir = dir:match('^%s*(.-)%s*$')
		if dir:sub(1, 1) == '"' and dir:sub(-1) == '"' then
			dir = dir:sub(2, -2)
		end
		if dir ~= '' then
			local candidate = utils.join_path(dir, name)
			local info = utils.file_info(candidate)
			if info and info.is_file then return candidate end
		end
	end
	return bundled
end

local cfg = {
	ffmpeg = executable_path(is_windows_os and 'ffmpeg.exe' or 'ffmpeg'),
	default_width = '',
	default_fps = '',
	default_speed = 1,
	output_dir = '',
}

local function trim(s)
	return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function strip_quotes(s)
	s = trim(s)
	if s:sub(1, 1) == '"' and s:sub(-1) == '"' then
		return s:sub(2, -2)
	end
	return s
end

local function source_limits()
	local w = mp.get_property_number('video-dec-params/w')
		or mp.get_property_number('video-params/w')
	local h = mp.get_property_number('video-dec-params/h')
		or mp.get_property_number('video-params/h')
	if not w or not h or w <= 0 or h <= 0 then
		return nil, 'Source video dimensions are unavailable.'
	end
	local source_w, source_h = w, h

	local rotation = mp.get_property_number('video-dec-params/rotate')
		or mp.get_property_number('video-params/rotate') or 0
	if math.floor((rotation % 360) / 90 + 0.5) % 2 == 1 then
		w, h = h, w
	end
	local max_width = w
	if max_width < 1 then return nil, 'Source aspect ratio is invalid.' end

	local function valid_rate(n)
		if type(n) == 'number' and n > 0 and n == n and n < math.huge then
			return n
		end
	end
	local src_fps = valid_rate(mp.get_property_number('current-tracks/video/demux-fps'))
		or valid_rate(mp.get_property_number('container-fps'))
		or valid_rate(mp.get_property_number('estimated-vf-fps'))
	return {max_width = max_width, fps = src_fps, source_w = source_w, source_h = source_h}
end

local function format_fps(n)
	return n and string.format('%.3f', n):gsub('0+$', ''):gsub('%.$', '') or 'Unknown'
end

local function numeric_width(s, limits)
	if s == '' then return '' end
	local n = tonumber(s)
	if not n or n ~= math.floor(n) or n < 1 then
		return nil, 'Width must be a positive whole number.'
	end
	if limits and n > limits.max_width then
		return nil, 'Width cannot exceed the source maximum of ' .. limits.max_width .. ' px.'
	end
	return tostring(n)
end

local function numeric_fps(s, limits)
	if s == '' then return '' end
	local n = tonumber(s)
	if not n or n ~= n or n <= 0 or n == math.huge then
		return nil, 'FPS must be a positive number.'
	end
	if limits then
		if not limits.fps then
			return nil, 'Source FPS is unknown; leave FPS at Original.'
		end
		if n > limits.fps + 0.0001 then
			return nil, 'FPS cannot exceed the source rate of ' .. format_fps(limits.fps) .. '.'
		end
	end
	return s
end

local function numeric_speed(s)
	if s == '' then return 1 end
	local n = tonumber(s)
	if not n or n ~= n or n < 0.25 or n > 4 then
		return nil, 'Speed must be between 0.25x and 4x.'
	end
	return n
end

local export_format = 'webp'

local function filename_value(s)
	s = trim(s)
	local ext = export_format == 'gif' and '.gif' or '.webp'
	if s:lower():sub(-#ext) == ext then s = trim(s:sub(1, -#ext - 1)) end
	if s == '' then return '' end
	if #s - select(2, s:gsub('[\128-\191]', '')) > 160 then
		return nil, 'Filename cannot exceed 160 characters.'
	end

	if is_windows_os then
		if s:find('[<>:"/\\|%?%*%c]') or s:match('[%. ]$') then
			return nil, 'Invalid Windows filename.'
		end

		local root = (s:match('^([^%.]+)') or s):upper()
		if root == 'CON' or root == 'PRN' or root == 'AUX' or root == 'NUL'
			or root:match('^COM[1-9]$') or root:match('^LPT[1-9]$') then
			return nil, 'Reserved Windows filename.'
		end
	elseif s:find('[/%c]') then
		return nil, 'Invalid filename.'
	end

	return s
end

local width, fps = numeric_width(trim(cfg.default_width)), numeric_fps(trim(cfg.default_fps))
local speed = numeric_speed(trim(cfg.default_speed)) or 1
if not width then width = '' end
if not fps then fps = '' end
local directory_override = strip_quotes(cfg.output_dir)
local name_override = ''
local subtitles_enabled = false
local caption_text, caption_enabled = '', false
local caption_start_mark, caption_end_mark, caption_mark_source = nil, nil, nil
local start_mark, end_mark, mark_source = nil, nil, nil
local menu_open, editing, menu_index = false, false, 1
local advanced_open = false
local lossless_export = false
local job = nil
local active_temp_work = nil
local active_export_request = nil
local temp_work_counter = 0
local overlay = mp.create_osd_overlay('ass-events')
overlay.res_x, overlay.res_y = 1280, 960

local logo_vectors = {
	{'21B6F2', [[m 500 250 b 500 388 388 500 250 500 b 112 500 0 388 0 250 b 0 112 112 0 250 0 b 388 0 500 112 500 250 m 479 250 b 479 123 376 21 250 21 b 124 21 21 123 21 250 b 21 377 124 479 250 479 b 376 479 479 377 479 250]]},
	{'21B6F2', [[m 373 163 b 367 167 359 169 350 170 b 349 170 349 171 350 172 b 373 195 388 228 388 263 b 388 292 378 319 362 340 b 362 340 362 341 362 341 b 369 348 373 354 378 360 b 399 333 412 299 412 263 b 412 225 398 190 375 163 b 374 163 374 163 373 163 l 373 163 m 125 235 b 122 238 118 240 112 240 b 110 240 108 240 106 239 b 105 247 104 255 104 263 b 104 276 106 289 109 301 b 109 302 109 301 110 301 b 111 300 113 299 114 299 b 120 298 127 297 132 293 b 132 293 132 293 132 292 b 129 283 128 273 128 263 b 128 254 129 245 131 237 b 132 230 128 232 125 235 l 125 235 m 204 381 b 197 387 190 392 181 396 b 181 396 181 396 181 396 b 204 409 230 417 258 417 b 280 417 301 412 319 404 b 321 404 321 403 320 402 b 313 397 305 391 298 387 b 298 386 298 386 298 386 b 285 391 272 393 258 393 b 239 393 221 388 204 381 b 204 381 204 381 204 381 l 204 381]]},
	{'FFFFFF', [[m 160 300 b 177 289 195 279 212 270 b 212 275 211 282 210 287 b 194 293 177 298 160 300 m 141 153 b 136 129 129 117 122 117 b 118 117 115 121 115 127 b 115 141 110 155 100 169 b 92 178 88 187 88 193 b 88 203 91 212 96 221 b 99 226 105 229 112 229 b 120 229 128 216 137 189 b 145 176 166 164 201 151 b 200 153 200 155 200 157 b 200 160 204 163 211 168 l 213 186 b 201 190 189 192 179 195 l 159 195 b 155 195 154 197 154 199 b 154 202 156 204 161 207 b 172 215 181 218 189 218 b 192 218 200 217 214 214 l 214 228 b 200 231 186 236 172 241 l 160 240 b 157 240 156 241 156 243 b 156 246 158 249 162 251 b 174 257 185 259 195 259 b 174 276 154 291 133 305 l 117 310 b 113 311 111 315 111 324 b 113 337 120 343 129 343 b 133 343 138 341 146 340 b 167 332 185 326 200 321 b 180 353 152 374 118 384 b 112 386 108 388 108 391 b 108 395 114 396 125 396 b 134 396 141 396 146 395 b 186 391 213 369 228 333 b 267 353 299 372 324 392 b 339 403 351 408 359 408 b 371 408 378 401 378 388 b 378 373 364 355 337 336 b 321 326 287 320 233 315 l 235 310 b 256 304 282 297 310 288 b 335 282 347 274 347 265 b 347 257 340 250 327 246 b 324 245 319 244 313 244 b 303 244 291 241 279 236 b 285 243 291 250 299 257 b 279 265 258 272 237 280 b 238 272 239 263 240 255 b 244 251 253 247 265 244 b 271 243 274 240 274 234 b 274 229 271 224 264 221 b 258 219 253 218 249 218 l 239 219 l 240 207 b 249 205 259 204 269 201 b 279 198 284 194 284 189 b 284 182 281 177 275 175 b 265 170 258 168 252 168 b 250 168 247 171 242 176 b 243 170 244 163 244 159 b 244 153 239 148 228 143 b 258 135 289 130 319 130 b 304 147 282 157 255 161 b 273 168 287 171 296 171 b 308 171 324 167 348 159 b 366 158 375 152 375 142 b 375 134 366 123 350 111 b 343 108 338 106 335 106 b 331 106 326 106 319 108 b 301 108 279 111 253 117 b 256 114 258 109 258 103 b 258 95 254 88 244 81 b 234 75 216 72 191 69 b 187 68 180 67 178 67 b 177 68 176 69 176 72 b 176 81 185 91 202 100 b 188 107 174 111 160 116 b 169 117 176 118 182 118 b 195 118 212 117 234 115 b 238 117 242 118 246 119 b 207 128 172 139 141 153 l 141 153]]},
}

local gui_offset_x, gui_offset_y = 0, 0

local function update_menu_geometry()
	local d = mp.get_property_native('osd-dimensions')
	if type(d) ~= 'table' or type(d.w) ~= 'number' or type(d.h) ~= 'number'
		or d.w <= 0 or d.h <= 0 then
		overlay.res_x, overlay.res_y = 1280, 960
		gui_offset_x, gui_offset_y = 0, 0
		return
	end

	local left, right = d.ml or 0, d.mr or 0
	local top, bottom = d.mt or 0, d.mb or 0
	local video_w, video_h = d.w - left - right, d.h - top - bottom
	if video_w <= 0 or video_h <= 0 then
		overlay.res_x, overlay.res_y = 1280, 960
		gui_offset_x, gui_offset_y = 0, 0
		return
	end

	local scale = math.min(video_w / 1280, video_h / 960)
	overlay.res_x = math.floor(d.w / scale + 0.5)
	overlay.res_y = math.floor(d.h / scale + 0.5)
	gui_offset_x = (left + (video_w - 1280 * scale) / 2) / scale
	gui_offset_y = (top + (video_h - 960 * scale) / 2) / scale
end

local function say(message, seconds)
	mp.osd_message('[GIFit] ' .. message, seconds or 3)
end

local function time_parts(t)
	local ms = math.floor(t * 1000 + 0.5)
	return math.floor(ms / 3600000), math.floor(ms / 60000) % 60,
		math.floor(ms / 1000) % 60, ms % 1000
end

local function clock(t)
	if type(t) ~= 'number' or t < 0 then return '--:--:--.---' end
	return string.format('%02d:%02d:%02d.%03d', time_parts(t))
end

local function filename_clock(t)
	return string.format('%02dh%02dm%02ds%03d', time_parts(t))
end

local function source_path()
	local p = mp.get_property('path')
	if not p or p == '' then return nil, 'Open a local video first.' end
	if p:match('^[%a][%w+%.%-]*://') then
		return nil, 'Only local video files are supported (not streams/URLs).'
	end
	local normalized = mp.command_native({'normalize-path', p})
	p = type(normalized) == 'string' and normalized or p
	local stat = utils.file_info(p)
	if not stat or not stat.is_file then
		return nil, 'Cannot access the source video on disk.'
	end
	return p
end

local function playback_pos()
	return mp.get_property_number('time-pos')
end

local function ass_escape(s)
	s = tostring(s or ''):gsub('[\r\n]', ' ')
	return (s:gsub('\\', '\\\\'):gsub('{', '\\{'):gsub('}', '\\}'))
end

local function shorten(s, limit)
	if #s > limit then return s:sub(1, limit - 3) .. '...' end
	return s
end

local text_subtitle_codecs = {
	ass = true, ssa = true, subrip = true, mov_text = true,
	webvtt = true, text = true,
}

local function selected_subtitle(src)
	local tracks = mp.get_property_native('track-list')
	if type(tracks) ~= 'table' then
		return nil, 'Cannot read the subtitle track list from mpv.'
	end
	local sid = mp.get_property_number('sid')
	local selected
	if sid then
		for _, track in ipairs(tracks) do
			if track.type == 'sub' and track.id == sid then
				selected = track
				break
			end
		end
	end
	if not selected then
		return nil, 'Select a subtitle track in mpv before exporting with subtitles.'
	end
	local codec = tostring(selected.codec or ''):lower()
	if not text_subtitle_codecs[codec] then
		return nil, 'Selected subtitle type (' .. (codec ~= '' and codec or 'unknown') ..
			') is not supported. GIFit supports text subtitles (SRT/ASS/SSA/WebVTT).'
	end
	local result = {
		label = trim(selected.title or selected.lang or codec),
		codec = codec,
		external_ass = selected.external and (codec == 'ass' or codec == 'ssa'),
		external = not not selected.external,
	}
	if selected.external then
		local path = selected['external-filename']
		if not path or path == '' then
			return nil, 'Cannot determine the selected external subtitle filename.'
		end
		if not utils.file_info(path) then
			local source_dir = utils.split_path(src)
			local alongside = utils.join_path(source_dir, path)
			if utils.file_info(alongside) then path = alongside end
		end
		local normalized = mp.command_native({'normalize-path', path})
		if type(normalized) == 'string' then path = normalized end
		local info = utils.file_info(path)
		if not info or not info.is_file then
			return nil, 'The selected external subtitle file cannot be accessed.'
		end
		result.path = path
	else
		local index = selected['ff-index']
		if type(index) ~= 'number' then
			return nil, 'Cannot map this embedded subtitle track to FFmpeg.'
		end
		local si = 0
		for _, track in ipairs(tracks) do
			if track.type == 'sub' and not track.external
				and type(track['ff-index']) == 'number'
				and track['ff-index'] < index then
				si = si + 1
			end
		end
		result.path = src
		result.si = si
		result.ff_index = index
	end
	if result.label == '' then result.label = codec end
	return result
end

local function subtitle_filter_path(path)
	path = path:gsub('\\', '/')
	local function escape_level(value, special)
		return (value:gsub('.', function(ch)
			if special:find(ch, 1, true) then return '\\' .. ch end
			return ch
		end))
	end
	path = escape_level(path, "\\':")
	return escape_level(path, "\\'[],;")
end

local function mpv_fonts_dir()
	return mp.command_native({'expand-path', '~~/fonts'})
end

local function ass_color(value)
	if type(value) ~= 'string' then return nil end
	value = trim(value)
	local r, g, b, a
	local hex = value:match('^#?([%x]+)$')
	if hex and (#hex == 6 or #hex == 8) then
		if #hex == 8 then
			a = tonumber(hex:sub(1, 2), 16)
			hex = hex:sub(3)
		else
			a = 255
		end
		r = tonumber(hex:sub(1, 2), 16)
		g = tonumber(hex:sub(3, 4), 16)
		b = tonumber(hex:sub(5, 6), 16)
	else
		local parts = {}
		for part in value:gmatch('[^/]+') do
			local n = tonumber(part)
			if not n or n < 0 or n > 1 then return nil end
			parts[#parts + 1] = n
		end
		if #parts == 1 or #parts == 2 then
			r = parts[1]
			g, b = r, r
			a = parts[2] or 1
		elseif #parts == 3 or #parts == 4 then
			r, g, b = parts[1], parts[2], parts[3]
			a = parts[4] or 1
		else
			return nil
		end
		r = math.floor(r * 255 + 0.5)
		g = math.floor(g * 255 + 0.5)
		b = math.floor(b * 255 + 0.5)
		a = math.floor(a * 255 + 0.5)
	end
	return string.format('&H%02X%02X%02X%02X', 255 - a, b, g, r)
end

local function subtitle_style()
	local function option(name)
		return mp.get_property('options/' .. name)
	end
	local function number(name)
		return mp.get_property_number('options/' .. name)
	end
	local style = {}
	local style_scale = 288 / 720
	local function add(name, value)
		if value ~= nil then style[#style + 1] = name .. '=' .. tostring(value) end
	end
	local function add_scaled(name, value)
		if value then add(name, string.format('%.3f', value * style_scale)) end
	end

	local font = option('sub-font')
	if font and font ~= '' and not font:find("[,:'\\%c]") then add('FontName', font) end
	local scale = number('sub-scale') or 1
	local font_size = number('sub-font-size')
	add_scaled('FontSize', font_size and font_size * scale)
	add('PrimaryColour', ass_color(option('sub-color')))
	add('OutlineColour', ass_color(option('sub-outline-color') or option('sub-border-color')))
	add('BackColour', ass_color(option('sub-back-color') or option('sub-shadow-color')))
	add_scaled('Outline', (number('sub-outline-size') or number('sub-border-size') or 0) * scale)
	add_scaled('Shadow', (number('sub-shadow-offset') or 0) * scale)
	add_scaled('Spacing', (number('sub-spacing') or 0) * scale)

	for _, flag in ipairs({{'Bold', 'sub-bold'}, {'Italic', 'sub-italic'}}) do
		local value = option(flag[2])
		if value then add(flag[1], value == 'yes' and -1 or 0) end
	end
	add('BorderStyle', ({['outline-and-shadow'] = 1, ['opaque-box'] = 3,
		['background-box'] = 4})[option('sub-border-style')])
	local x = option('sub-align-x') or 'center'
	local y = option('sub-align-y') or 'bottom'
	local x_index = ({left = 1, center = 2, right = 3})[x]
	local y_index = ({bottom = 0, center = 3, top = 6})[y]
	if x_index and y_index then add('Alignment', x_index + y_index) end

	local margin_x = number('sub-margin-x')
	if margin_x then
		local margin = math.floor(margin_x * style_scale + 0.5)
		add('MarginL', margin)
		add('MarginR', margin)
	end
	local margin_y = ((number('sub-margin-y') or 0) + (number('sub-margin-y-offset') or 0)) * scale
	local position = number('sub-pos')
	if position and y == 'bottom' then margin_y = margin_y + (100 - position) * 7.2 end
	add('MarginV', math.floor(math.max(0, margin_y) * style_scale + 0.5))
	if #style == 0 then return nil end
	return "'" .. table.concat(style, ',') .. "'"
end

local draw_menu
local open_menu
local close_menu

local function mark(which)
	if editing then return end
	local p, err = source_path()
	if not p then say(err); return end
	local now = playback_pos()
	if not now then say('Playback position is unavailable.'); return end
	if mark_source ~= p then start_mark, end_mark = nil, nil end
	mark_source = p
	if which == 'start' then start_mark = now else end_mark = now end
end

local function mark_caption(which)
	if editing then return end
	local p, err = source_path()
	if not p then say(err); return end
	local now = playback_pos()
	if not now then say('Playback position is unavailable.'); return end
	if caption_mark_source ~= p then caption_start_mark, caption_end_mark = nil, nil end
	caption_mark_source = p
	if which == 'start' then caption_start_mark = now else caption_end_mark = now end
end

local function output_directory(src)
	local src_dir = utils.split_path(src)
	local dest = strip_quotes(directory_override)
	if dest == '' then return src_dir end
	local normalized = mp.command_native({'normalize-path', dest})
	dest = type(normalized) == 'string' and normalized or dest
	local stat = utils.file_info(dest)
	if not stat or not stat.is_dir then
		return nil, 'Output folder does not exist or is inaccessible.'
	end
	return dest
end

local function output_target(src, from, to)
	local dir, err = output_directory(src)
	if not dir then return nil, err end
	local _, filename = utils.split_path(src)
	local stem = filename:gsub('%.[^%.]+$', '')
	if stem == '' then stem = 'video' end
	stem = stem:sub(1, 75)
	local ext = export_format == 'gif' and 'gif' or 'webp'
	local base = name_override ~= '' and name_override
		or (stem .. '_' .. filename_clock(from) .. '_to_' .. filename_clock(to) .. (speed ~= 1 and ('_' .. tostring(speed) .. 'x') or '') .. (export_format == 'webp' and lossless_export and '_lossless' or ''))
	for i = 0, 999 do
		local suffix = i == 0 and '' or ('_' .. string.format('%03d', i))
		local candidate = utils.join_path(dir, base .. suffix .. '.' .. ext)
		if not utils.file_info(candidate) then return candidate end
	end
	return nil, 'Too many files with the same name in the output folder.'
end

local font_extensions = {ttf = true, otf = true, ttc = true, otc = true, woff = true, woff2 = true}

local function portable_temp_root()
	if not is_windows_os then
		local path = mp.command_native({'expand-path', '~~/tmp'})
		return type(path) == 'string' and path ~= '' and path or nil
	end
	local scripts_path = mp.find_config_file('scripts')
	if not scripts_path then return nil end
	local base = utils.split_path(scripts_path)
	local path = utils.join_path(base, 'tmp')
	local normalized = mp.command_native({'normalize-path', path})
	return type(normalized) == 'string' and normalized or path
end

local function temp_roots()
	local roots, seen = {}, {}
	local function add(path)
		if type(path) ~= 'string' or trim(path) == '' then return end
		local normalized = mp.command_native({'normalize-path', path})
		path = type(normalized) == 'string' and normalized or path
		local key = is_windows_os and path:lower() or path
		if not seen[key] then
			seen[key] = true
			roots[#roots + 1] = path
		end
	end
	add(portable_temp_root())
	if not is_windows_os then
		add(os.getenv('XDG_RUNTIME_DIR'))
		add(os.getenv('TMPDIR'))
	end
	add(os.getenv('TEMP'))
	add(os.getenv('TMP'))
	if not is_windows_os then add('/tmp') end
	return roots
end

local function cleanup_temp_work(work, keep_file)
	if not work then return end
	for _, path in ipairs(work.files) do
		if path ~= keep_file and utils.file_info(path) and not os.remove(path) then
			mp.msg.warn('GIFit: Could not remove temporary file: ' .. path)
		end
	end
end

local function remove_empty_legacy_directory(path)
	if not os.remove(path) and utils.file_info(path) then
		mp.msg.warn('GIFit: Could not remove old temporary directory: ' .. path)
	end
end

local function process_start_epoch(pid)
	if not is_windows_os then
		local stat = utils.file_info('/proc/' .. pid)
		if not stat then return 0 end
		if not stat.is_dir then return -1 end
		local process = mp.command_native({
			name = 'subprocess', args = {'ps', '-p', pid, '-o', 'etimes='},
			playback_only = false, capture_stdout = true, capture_stderr = true,
		})
		local elapsed = process and process.status == 0 and tonumber(process.stdout)
		return elapsed and elapsed >= 0 and (os.time() - elapsed) or -1
	end
	local result = mp.command_native({
		name = 'subprocess',
		args = {'tasklist.exe', '/FI', 'PID eq ' .. pid, '/FO', 'CSV', '/NH'},
		playback_only = false, capture_stdout = true, capture_stderr = true,
	})
	if not result or result.status ~= 0 or type(result.stdout) ~= 'string' then
		return -1
	end
	local found = false
	for line in result.stdout:gmatch('[^\r\n]+') do
		if line:match('^"[^"]+","' .. pid .. '"') then found = true; break end
	end
	if not found then return 0 end
	local script = '$p = Get-Process -Id ' .. pid ..
		' -ErrorAction Stop; $t = [DateTimeOffset]::new($p.StartTime); $t.ToUnixTimeSeconds()'
	local details = mp.command_native({
		name = 'subprocess',
		args = {'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script},
		playback_only = false, capture_stdout = true, capture_stderr = true,
	})
	if not details or details.status ~= 0 then return -1 end
	return tonumber(trim(details.stdout)) or -1
end

local function cleanup_staging_record(record, prefix)
	local file = io.open(record, 'rb')
	if not file then return end
	local staging = file:read(4097)
	file:close()
	local filename = staging and staging:match('[^/\\]+$')
	local absolute = staging and (staging:match('^%a:[/\\]') or staging:match('^\\\\') or staging:sub(1, 1) == '/')
	if staging and #staging <= 4096 and not staging:find('[\r\n%z]') and absolute
		and filename == prefix .. '-staging.tmp' then
		if utils.file_info(staging) and not os.remove(staging) then
			mp.msg.warn('GIFit: Could not remove abandoned staging file: ' .. staging)
			return
		end
	else
		mp.msg.warn('GIFit: Invalid staging record: ' .. record)
	end
	if not os.remove(record) then
		mp.msg.warn('GIFit: Could not remove staging record: ' .. record)
	end
end

local function cleanup_abandoned_temp_files()
	local checked = {}
	local function abandoned(pid, created)
		if checked[pid] == nil then checked[pid] = process_start_epoch(pid) end
		local started = checked[pid]
		return started == 0 or (started > 0 and started > tonumber(created) + 1)
	end
	for _, root in ipairs(temp_roots()) do
		for _, name in ipairs(utils.readdir(root, 'files') or {}) do
			local pid, created, _, item = name:match('^gifit%-(%d+)%-(%d+)%-(%d+)%-(.+)$')
			if pid then
				local ext = item:match('^mkv%-%d+%.([%a%d]+)$')
					or item:match('^portable%-%d+%.([%a%d]+)$')
				local owned = item == 'caption.srt' or item == 'probe.tmp' or item == 'job.tmp'
					or item == 'output.webp' or item == 'output.gif' or item == 'staging.txt'
					or item == 'subtitle.ass'
					or (ext and font_extensions[ext:lower()])
				if owned and abandoned(pid, created) then
					local path = utils.join_path(root, name)
					if item == 'staging.txt' then
						cleanup_staging_record(path, name:sub(1, -#item - 2))
					elseif not os.remove(path) then
						mp.msg.warn('GIFit: Could not remove abandoned file: ' .. path)
					end
				end
			end
		end
		for _, name in ipairs(utils.readdir(root, 'dirs') or {}) do
			local pid, created = name:match('^gifit%-work%-(%d+)%-(%d+)%-%d+$')
			if not pid then
				pid, created = name:match('^gifit%-fonts%-(%d+)%-(%d+)%-%d+$')
			end
			if pid and abandoned(pid, created) then
				local path = utils.join_path(root, name)
				for _, filename in ipairs(utils.readdir(path, 'files') or {}) do
					local ext = filename:match('^mkv%-%d+%.([%a%d]+)$')
						or filename:match('^portable%-%d+%.([%a%d]+)$')
					if filename == 'caption.srt' or (ext and font_extensions[ext:lower()]) then
						os.remove(utils.join_path(path, filename))
					end
				end
				remove_empty_legacy_directory(path)
			end
		end
	end
end

local probe_exe = executable_path(is_windows_os and 'ffprobe.exe' or 'ffprobe')

local function ffprobe_json(src, options)
	local args = {probe_exe, '-v', 'error'}
	for _, option in ipairs(options) do args[#args + 1] = option end
	args[#args + 1] = src
	local result = mp.command_native({
		name = 'subprocess', args = args,
		playback_only = false, capture_stdout = true, capture_stderr = true,
	})
	if not result or result.status ~= 0 then return nil, false end
	return utils.parse_json(result.stdout or ''), true
end

local function external_ass_fonts(src)
	local parsed, ok = ffprobe_json(src, {
		'-select_streams', 't',
		'-show_entries', 'stream=index,codec_type:stream_tags=filename,mimetype',
		'-of', 'json',
	})
	if not ok then
		mp.msg.warn('GIFit: Could not inspect MKV font attachments; using available fonts.')
		return {}
	end
	if type(parsed) ~= 'table' or type(parsed.streams) ~= 'table' then
		mp.msg.warn('GIFit: Invalid MKV font attachment metadata; using available fonts.')
		return {}
	end
	local fonts = {}
	for ordinal, stream in ipairs(parsed.streams) do
		local tags = type(stream.tags) == 'table' and stream.tags or {}
		local name = tostring(tags.filename or '')
		local extension = name:match('%.([%a%d]+)$')
		if extension then extension = extension:lower() end
		local mime = tostring(tags.mimetype or ''):lower()
		local is_font = font_extensions[extension] or mime:find('font', 1, true)
		if is_font then
			if not font_extensions[extension] then
				extension = mime:find('woff2', 1, true) and 'woff2' or
					(mime:find('woff', 1, true) and 'woff' or 'ttf')
			end
			fonts[#fonts + 1] = {ordinal = ordinal - 1, extension = extension}
		end
	end
	return fonts
end

local ass_pc_matrices = {['tv.601'] = 'PC.601', ['tv.709'] = 'PC.709',
	['tv.240m'] = 'PC.240M', ['tv.fcc'] = 'PC.FCC'}

local function ass_pc_matrix(header)
	if type(header) ~= 'string' then return nil end
	for line in header:gmatch('[^\r\n]+') do
		local value = line:lower():match('^%s*ycbcr%s+matrix%s*:%s*(%S+)')
		if value then return ass_pc_matrices[value] end
	end
	return nil
end

local function ffprobe_header_text(dump)
	if type(dump) ~= 'string' then return nil end
	local bytes = {}
	for line in dump:gmatch('[^\r\n]+') do
		local hex = line:match('^%s*%x+:%s*(.-)%s%s')
		if hex then
			for byte in hex:gmatch('%x%x') do
				bytes[#bytes + 1] = string.char(tonumber(byte, 16))
			end
		end
	end
	return table.concat(bytes)
end

local function embedded_ass_pc_matrix(src, subtitle)
	local parsed, ok = ffprobe_json(src, {
		'-select_streams', 's:' .. subtitle.si,
		'-show_entries', 'stream=index,extradata', '-show_data', '-of', 'json',
	})
	if not ok then
		mp.msg.warn('GIFit: Could not inspect embedded ASS matrix; keeping original.')
		return nil
	end
	local stream = type(parsed) == 'table' and type(parsed.streams) == 'table'
		and parsed.streams[1]
	if type(stream) ~= 'table' or stream.index ~= subtitle.ff_index then
		mp.msg.warn('GIFit: Embedded subtitle stream mismatch; keeping original ASS matrix.')
		return nil
	end
	return ass_pc_matrix(ffprobe_header_text(stream.extradata))
end

local function subtitle_pc_matrix(src, subtitle)
	if not subtitle or (subtitle.codec ~= 'ass' and subtitle.codec ~= 'ssa') then return nil end
	if subtitle.external_ass then
		local file = io.open(subtitle.path, 'rb')
		if not file then return nil end
		local header = file:read(262144)
		file:close()
		return ass_pc_matrix(header)
	end
	return embedded_ass_pc_matrix(src, subtitle)
end

local function copy_font_file(from, to)
	local input_file = io.open(from, 'rb')
	if not input_file then return false end
	local output_file = io.open(to, 'wb')
	if not output_file then input_file:close(); return false end
	local success = true
	while true do
		local block, err = input_file:read(65536)
		if not block then
			if err then success = false end
			break
		end
		if not output_file:write(block) then success = false; break end
	end
	if not output_file:close() then success = false end
	input_file:close()
	if not success then os.remove(to) end
	return success
end

local function prepare_temp_work(fonts)
	local work, last_error
	for _, root in ipairs(temp_roots()) do
		local stat = utils.file_info(root)
		if stat and stat.is_dir then
			for attempt = 1, 16 do
				temp_work_counter = temp_work_counter + 1
				local prefix = string.format('gifit-%s-%s-%d',
					tostring(utils.getpid()), tostring(os.time()), temp_work_counter)
				local marker = utils.join_path(root, prefix .. '-job.tmp')
				if not utils.file_info(marker)
					and not utils.file_info(utils.join_path(root, prefix .. '-probe.tmp'))
					and not utils.file_info(utils.join_path(root, prefix .. '-output.webp'))
					and not utils.file_info(utils.join_path(root, prefix .. '-output.gif'))
					and not utils.file_info(utils.join_path(root, prefix .. '-staging.txt'))
					and not utils.file_info(utils.join_path(root, prefix .. '-caption.srt'))
					and not utils.file_info(utils.join_path(root, prefix .. '-subtitle.ass')) then
					local handle, open_err = io.open(marker, 'wb')
					if not handle then
						last_error = 'Cannot create job marker in ' .. root .. ': ' .. tostring(open_err)
						mp.msg.warn('GIFit: ' .. last_error)
						break
					end
					local closed, close_err = handle:close()
					if not closed then
						last_error = 'Cannot close job marker in ' .. root .. ': ' .. tostring(close_err)
						mp.msg.warn('GIFit: ' .. last_error)
						os.remove(marker)
						break
					end
					work = {dir = root, prefix = prefix, files = {marker}, fonts = {}}
					break
				end
			end
		end
		if work then break end
	end
	if not work then
		return nil, last_error or 'Cannot write temporary files to any configured temp directory.'
	end
	mp.msg.info('GIFit: Temporary files in: ' .. work.dir .. ' (prefix ' .. work.prefix .. ')')

	for i, font in ipairs(fonts) do
		local path = utils.join_path(work.dir, string.format('%s-mkv-%03d.%s',
			work.prefix, i, font.extension))
		work.fonts[#work.fonts + 1] = {ordinal = font.ordinal, path = path}
		work.files[#work.files + 1] = path
	end

	return work
end

local function publish_temp_output(work, temporary, destination)
	local dir = utils.split_path(destination)
	local staging = utils.join_path(dir, work.prefix .. '-staging.tmp')
	local record = utils.join_path(work.dir, work.prefix .. '-staging.txt')
	if utils.file_info(destination) then return false, 'Output filename is now in use.' end
	if utils.file_info(staging) then return false, 'Temporary staging filename is already in use.' end

	local file, err = io.open(record, 'wb')
	if not file then return false, 'Cannot create staging record: ' .. tostring(err) end
	local written, write_err = file:write(staging)
	local closed, close_err = file:close()
	if not written or not closed then
		os.remove(record)
		return false, 'Cannot write staging record: ' .. tostring(write_err or close_err)
	end

	local function clear_staging()
		if utils.file_info(staging) and not os.remove(staging) then
			mp.msg.warn('GIFit: Staging file retained for startup cleanup: ' .. staging)
			return
		end
		if not os.remove(record) then
			mp.msg.warn('GIFit: Staging record retained for startup cleanup: ' .. record)
		end
	end

	if not copy_font_file(temporary, staging) then
		clear_staging()
		return false, 'Could not copy export to the destination folder.'
	end
	local source_info, stage_info = utils.file_info(temporary), utils.file_info(staging)
	if not source_info or not stage_info or stage_info.size ~= source_info.size then
		clear_staging()
		return false, 'Staged export size does not match the encoded file.'
	end
	if utils.file_info(destination) then
		clear_staging()
		return false, 'Output filename became occupied during export.'
	end
	if is_windows_os then
		local ok, rename_err = os.rename(staging, destination)
		clear_staging()
		if not ok then return false, 'Cannot finalize export: ' .. tostring(rename_err) end
	else
		local result = mp.command_native({
			name = 'subprocess', args = {'ln', '--', staging, destination},
			playback_only = false, capture_stdout = true, capture_stderr = true,
		})
		local ok = result and result.status == 0
		clear_staging()
		if not ok then
			return false, 'Cannot finalize export: ' .. tostring(result and result.stderr or 'hard-link failed')
		end
	end
	return true
end

local function inclusive_timing(from, to, limits)
	local rate = limits and limits.fps
	local frame_time = rate and rate > 0 and 1 / rate or nil
	local seek_from = math.max(0, from - 0.001)
	local trim_end = to - seek_from + (frame_time and frame_time / 2 or 0.002)
	return {
		frame_time = frame_time,
		seek_from = seek_from,
		trim_end = trim_end,
		duration = to - from + (frame_time or 0),
	}
end

local function build_args(src, dest, limits, subtitle, temp_work, timing)
	local seek_from, trim_end = timing.seek_from, timing.trim_end
	local subtitle_filter = ''
	if subtitle then
		local is_ass = subtitle.codec == 'ass' or subtitle.codec == 'ssa'
		local subtitle_time = seek_from - (subtitle.delay or (mp.get_property_number('sub-delay') or 0))
		if subtitle.clip_seek then subtitle_time = subtitle_time - subtitle.clip_seek end
		local subtitle_timing = subtitle.custom and 'setpts=PTS-STARTPTS,' or
			('setpts=PTS+' .. string.format('%.6f', subtitle_time) .. '/TB,')
		subtitle_filter = subtitle_timing .. 'subtitles=filename=' .. subtitle_filter_path(subtitle.path)
		if subtitle.si then subtitle_filter = subtitle_filter .. ':si=' .. subtitle.si end
		if is_ass then
			subtitle_filter = subtitle_filter .. ':original_size=' .. limits.source_w .. 'x' .. limits.source_h
		end
		if subtitle.pc_matrix then
			subtitle_filter = subtitle_filter .. ":force_style='YCbCr Matrix=" .. subtitle.pc_matrix .. "'"
		end
		local fontsdir
		if is_ass then
			if temp_work and #temp_work.fonts > 0 then fontsdir = temp_work.dir end
		else
			fontsdir = mpv_fonts_dir()
		end
		if fontsdir then subtitle_filter = subtitle_filter .. ':fontsdir=' .. subtitle_filter_path(fontsdir) end
		if not is_ass then
			local style = subtitle_style()
			if style then subtitle_filter = subtitle_filter .. ':force_style=' .. style end
		end
		subtitle_filter = subtitle_filter .. (subtitle.custom and ',' or ',setpts=PTS-STARTPTS,')
	end
	local fps_filter = fps == '' and '' or ('fps=' .. fps .. ',')
	local resize_width = width == '' and 'iw' or width
	local resize_height = width == '' and 'ih/sar' or ('ih*' .. width .. '/iw/sar')
	local resize = 'scale=' .. resize_width .. ':' .. resize_height .. ':flags=lanczos,setsar=1,'
	local speed_filter = speed == 1 and '' or ('settb=AVTB,setpts=(PTS-STARTPTS)/' .. speed .. ',')
	local graph
	if export_format == 'gif' then
		graph = '[0:v:0]trim=end=' .. string.format('%.6f', trim_end) .. ',' ..
			fps_filter .. resize .. subtitle_filter .. speed_filter ..
			'split[v1][v2];' ..
			'[v1]palettegen=max_colors=256:stats_mode=full:reserve_transparent=0[p];' ..
			'[v2][p]paletteuse=dither=sierra3:diff_mode=rectangle[v]'
	else
		graph = '[0:v:0]trim=end=' .. string.format('%.6f', trim_end) .. ',' ..
			fps_filter .. resize .. subtitle_filter .. speed_filter .. 'format=bgra[v]'
	end
	local args = {
		cfg.ffmpeg, '-hide_banner', '-nostats', '-loglevel', 'error',
		'-n', '-ss', string.format('%.6f', seek_from),
		'-t', string.format('%.6f', trim_end + 0.100),
	}
	if temp_work and #temp_work.fonts > 0 then
		for _, font in ipairs(temp_work.fonts) do
			args[#args + 1] = '-dump_attachment:t:' .. font.ordinal
			args[#args + 1] = font.path
		end
	end
	local encoder_args
	if export_format == 'gif' then
		local output_fps = tonumber(fps) or limits.fps
		local final_delay = -1
		if speed ~= 1 and output_fps then
			final_delay = math.max(1, math.min(65535, math.floor(100 / (output_fps * speed) + 0.5)))
		end
		encoder_args = {'-map', '[v]', '-an', '-sn', '-dn', '-fps_mode', 'passthrough',
			'-enc_time_base:v', 'filter', '-final_delay', tostring(final_delay), '-loop', '0'}
	else
		encoder_args = {'-map', '[v]', '-fps_mode', 'passthrough',
			'-enc_time_base:v', 'filter', '-c:v', 'libwebp_anim', '-lossless', lossless_export and '1' or '0',
			'-quality', lossless_export and '0' or '100',
			'-compression_level', lossless_export and '0' or '4', '-pix_fmt', 'bgra', '-loop', '0'}
	end
	for _, arg in ipairs({'-i', src, '-filter_complex', graph}) do args[#args + 1] = arg end
	for _, arg in ipairs(encoder_args) do args[#args + 1] = arg end
	args[#args + 1] = dest
	return args
end

local function export_media()
	if job then say('An export is already running.'); return end
	local src, err = source_path()
	if not src then say(err, 4); return end
	if src ~= mark_source or not start_mark or not end_mark then
		say('Set start and end positions from the Ctrl+g menu first.', 4)
		return
	end
	if end_mark <= start_mark then
		say('End must be after start. Set both positions using the menu.', 4)
		return
	end
	local limits, lim_err = source_limits()
	if not limits then say(lim_err, 5); return end
	local _, width_err = numeric_width(width, limits)
	if width_err then say(width_err, 6); return end
	local _, fps_err = numeric_fps(fps, limits)
	if fps_err then say(fps_err, 6); return end
	local effective_fps = (tonumber(fps) or limits.fps)
	if effective_fps and effective_fps * speed > 60 then
		say('Effective FPS exceeds 60. Reduce FPS or playback speed.', 6)
		return
	end
	local subtitle
	if subtitles_enabled and not caption_enabled then
		local sub_err
		subtitle, sub_err = selected_subtitle(src)
		if not subtitle then say(sub_err, 7); return end
	end
	if subtitle then
		subtitle.pc_matrix = subtitle_pc_matrix(src, subtitle)
		if subtitle.pc_matrix then
			mp.msg.info('GIFit: ASS matrix override: ' .. subtitle.pc_matrix)
		end
	end
	local timing = inclusive_timing(start_mark, end_mark, limits)
	local duration = timing.duration
	if end_mark - start_mark < 0.001 then say('Selected clip is too short.'); return end
	local dest, dest_err = output_target(src, start_mark, end_mark)
	if not dest then say(dest_err, 5); return end
	local caption_from, caption_to
	if caption_enabled then
		if (caption_start_mark or caption_end_mark) and caption_mark_source ~= src then
			say('Caption timing belongs to a different video. Reset caption timing.', 6)
			return
		end
		caption_from = math.max(start_mark, caption_start_mark or start_mark)
		caption_to = math.min(end_mark, caption_end_mark or end_mark)
		if caption_to - caption_from < 0.001 then
			say('Caption timing must overlap the export and end after it starts.', 6)
			return
		end
	end
	local fonts = {}
	if subtitle and (subtitle.codec == 'ass' or subtitle.codec == 'ssa')
		and src:lower():match('%.mk[vs]$') then
		fonts = external_ass_fonts(src)
	end
	local temp_work, temp_err = prepare_temp_work(fonts)
	if not temp_work then say(temp_err, 7); return end
	if caption_enabled then
		local caption_file = utils.join_path(temp_work.dir, temp_work.prefix .. '-caption.srt')
		mp.msg.info('GIFit: Temporary caption: ' .. caption_file)
		temp_work.files[#temp_work.files + 1] = caption_file
		local file, file_err = io.open(caption_file, 'wb')
		if not file then
			cleanup_temp_work(temp_work)
			say('Cannot create caption file: ' .. tostring(file_err), 7)
			return
		end
		local srt_start = clock(caption_from - start_mark):gsub('%.', ',')
		local srt_end = clock(caption_to - start_mark + (timing.frame_time or 0.002) / 2):gsub('%.', ',')
		local written, write_err = file:write('1\r\n' .. srt_start .. ' --> ' .. srt_end .. '\r\n' .. caption_text .. '\r\n')
		local closed, close_err = file:close()
		if not written or not closed then
			cleanup_temp_work(temp_work)
			say('Cannot write caption file: ' .. tostring(write_err or close_err), 7)
			return
		end
		subtitle = {path = caption_file, codec = 'subrip', custom = true}
	end
	if utils.file_info(dest) then
		cleanup_temp_work(temp_work)
		say('Output filename is now in use. Try exporting again.', 5)
		return
	end
	local temp_output = utils.join_path(temp_work.dir, temp_work.prefix .. '-output.' .. export_format)
	temp_work.files[#temp_work.files + 1] = temp_output
	active_temp_work = temp_work
	mp.msg.info('GIFit: Using ' .. cfg.ffmpeg .. ' via mpv subprocess')
	if menu_open then close_menu() end
	job = true
	say('Exporting ' .. clock(duration / speed) .. ' ' .. (export_format == 'gif' and 'GIF' or 'WebP') .. ' in background...', 4)
	local function preparation_failed(message)
		cleanup_temp_work(temp_work)
		if active_temp_work == temp_work then active_temp_work = nil end
		active_export_request = nil
		job = nil
		mp.msg.error('GIFit: ' .. message)
		say(shorten(message, 220), 8)
	end
	local function finished(success, result, error_text)
		local stat = utils.file_info(temp_output)
		local exit_code = result and result.status
		local proc_error = result and result.error_string or ''
		local stderr = type(result) == 'table' and result.stderr or ''
		if type(stderr) ~= 'string' then stderr = tostring(stderr or '') end
		local encoded = success and exit_code == 0 and stat and stat.is_file and stat.size > 0
		local published, publish_err = false, nil
		if encoded then published, publish_err = publish_temp_output(temp_work, temp_output, dest) end
		cleanup_temp_work(temp_work, encoded and not published and temp_output or nil)
		if active_temp_work == temp_work then active_temp_work = nil end
		active_export_request = nil
		job = nil
		if published then
			mp.msg.info('GIFit created: ' .. dest)
			say('Created: ' .. dest, 7)
		else
			local logline = string.format(
				'GIFit failed: command_success=%s, status=%s, error_string=%s, API_error=%s, executable=%s, stderr=%s',
				tostring(success), tostring(exit_code), tostring(proc_error),
				tostring(error_text), cfg.ffmpeg, stderr)
			mp.msg.error(logline)
			local detail
			if publish_err then
				mp.msg.warn('GIFit: Completed export retained until next startup: ' .. temp_output)
				detail = publish_err .. ' Completed export retained in GIFit temp; see mpv log.'
			elseif not success then
				detail = 'mpv command error: ' .. tostring(error_text or 'unknown')
			elseif proc_error == 'init' then
				detail = 'Could not launch ' .. cfg.ffmpeg .. ' (init error). See mpv log.'
			elseif proc_error == 'killed' then
				detail = 'FFmpeg process was terminated by mpv; see mpv log.'
			elseif exit_code ~= 0 then
				detail = 'FFmpeg exit code ' .. tostring(exit_code) .. ': ' ..
					(trim(stderr) ~= '' and trim(stderr) or 'See mpv log.')
			else
				detail = 'FFmpeg returned success but no temporary export was created.'
			end
			say(shorten(detail, 220), 9)
		end
		if menu_open then draw_menu() end
	end
	local function start_encoding()
		local args = build_args(src, temp_output, limits, subtitle, temp_work, timing)
		mp.msg.info('GIFit: ' .. table.concat(args, ' | '))
		local request, request_error = mp.command_native_async({
			name = 'subprocess', args = args,
			playback_only = false, capture_stderr = true,
		}, finished)
		if request then active_export_request = request
		else preparation_failed('Could not schedule FFmpeg: ' .. tostring(request_error)) end
	end
	if subtitle and not subtitle.external and not subtitle.custom then
		local subtitle_file = utils.join_path(temp_work.dir, temp_work.prefix .. '-subtitle.ass')
		temp_work.files[#temp_work.files + 1] = subtitle_file
		local delay = mp.get_property_number('sub-delay') or 0
		local clip_seek = math.max(0, math.floor(timing.seek_from - delay - 15))
		local clip_end = math.max(0, end_mark - delay + (timing.frame_time or 0.002) + 1)
		local clip_length = math.max(0.1, clip_end - clip_seek)
		local args = {cfg.ffmpeg, '-hide_banner', '-nostats', '-loglevel', 'error',
			'-nostdin', '-n', '-ss', string.format('%.6f', clip_seek),
			'-i', src, '-map', '0:' .. subtitle.ff_index,
			'-vn', '-an', '-dn', '-t', string.format('%.6f', clip_length),
			'-c:s', 'ass', '-f', 'ass', subtitle_file}
		mp.msg.info('GIFit: Extracting selected subtitle stream around ' .. clock(start_mark) ..
			' to ' .. clock(end_mark) .. ' into ' .. subtitle_file)
		local request, request_error = mp.command_native_async({
			name = 'subprocess', args = args,
			playback_only = false, capture_stderr = true,
		}, function(success, result, error_text)
			if active_temp_work ~= temp_work then return end
			active_export_request = nil
			local stat = utils.file_info(subtitle_file)
			if not success or not result or result.status ~= 0 or not stat or not stat.is_file or stat.size == 0 then
				local detail = result and trim(result.stderr or '') or tostring(error_text or 'unknown error')
				preparation_failed('Could not extract the selected subtitle segment: ' .. shorten(detail, 180))
				return
			end
			subtitle.path = subtitle_file
			subtitle.si = nil
			subtitle.clip_seek = clip_seek
			subtitle.delay = delay
			start_encoding()
		end)
		if request then active_export_request = request
		else preparation_failed('Could not schedule subtitle extraction: ' .. tostring(request_error)) end
	else
		start_encoding()
	end
end

local menu_bindings = {
	'gifit-menu-up', 'gifit-menu-down', 'gifit-menu-enter',
	'gifit-menu-escape', 'gifit-menu-backspace',
}

local function show_after_input()
	mp.add_timeout(0.10, function()
		if not menu_open and not editing then open_menu() end
	end)
end

local function edit_option(which)
	local current = ({width = width, fps = fps, filename = name_override,
		directory = directory_override, caption = caption_text, speed = tostring(speed)})[which]
	local prompt = ({
		width = 'Export width in px (max = source; blank = Original):',
		fps = 'Export FPS (max = source; blank = Original):',
		speed = 'Playback speed (0.25-4; blank = Normal 1x):',
		filename = 'Filename (blank = Automatic):',
		directory = 'Save folder (blank = Beside video; folder must exist):',
		caption = 'Custom caption (blank = Off):',
	})[which]
	close_menu()
	editing = true
	input.get({
		prompt = prompt,
		default_text = current,
		id = 'gifit-' .. which,
		submit = function(value)
			value = trim(value)
			if which == 'width' or which == 'fps' then
				local limits, lim_err = source_limits()
				if not limits and value ~= '' then say(lim_err, 5); return end
				local validate = which == 'width' and numeric_width or numeric_fps
				local parsed, err = validate(value, limits)
				if not parsed then say(err, 4); return end
				if which == 'width' then width = parsed else fps = parsed end
			elseif which == 'speed' then
				local parsed, err = numeric_speed(value)
				if parsed then speed = parsed else say(err, 4) end
			elseif which == 'filename' then
				local parsed, err = filename_value(value)
				if parsed then name_override = parsed else say(err, 4) end
			elseif which == 'caption' then
				caption_text = value
				caption_enabled = value ~= ''
				if caption_enabled then subtitles_enabled = false
				else caption_start_mark, caption_end_mark, caption_mark_source = nil, nil, nil end
			elseif which == 'directory' then
				local candidate = strip_quotes(value)
				if candidate ~= '' then
					local dest = mp.command_native({'normalize-path', candidate})
					local stat = type(dest) == 'string' and utils.file_info(dest)
					if not stat or not stat.is_dir then
						say('Folder not found; choose an existing folder before exporting.', 5)
						return
					end
				end
				directory_override = candidate
			end
		end,
		closed = function()
			editing = false
			show_after_input()
		end,
	})
end

local function toggle_subtitles()
	if subtitles_enabled then
		subtitles_enabled = false
		return
	end
	local src, err = source_path()
	if not src then say(err, 5); return end
	local selected, sub_err = selected_subtitle(src)
	if not selected then say(sub_err, 6); return end
	subtitles_enabled = true
	caption_enabled = false
end

local function caption_label()
	if caption_text == '' then return 'Off  [Enter = enter text]' end
	return (caption_enabled and 'On (' or 'Off (') .. shorten(caption_text, 28) .. ')  [Enter = edit]'
end

local function subtitles_label()
	if caption_enabled then return 'Custom caption  [Enter = disable]' end
	if not subtitles_enabled then return 'Off  [Enter = toggle]' end
	local src = source_path()
	local sub = src and selected_subtitle(src)
	return (sub and ('On (' .. shorten(sub.label, 28) .. ')') or 'On (no valid track)') .. '  [Enter = toggle]'
end

local function toggle_menu_subtitles()
	if caption_enabled then
		caption_enabled = false
	else
		toggle_subtitles()
	end
end

local function advanced_summary()
	local active = {}
	if fps ~= '' then active[#active + 1] = fps .. ' FPS' end
	if speed ~= 1 then active[#active + 1] = tostring(speed) .. 'x speed' end
	if export_format == 'gif' then active[#active + 1] = 'GIF format'
	elseif lossless_export then active[#active + 1] = 'Lossless' end
	if caption_enabled then active[#active + 1] = 'Caption' end
	if name_override ~= '' then active[#active + 1] = 'Filename' end
	if directory_override ~= '' then active[#active + 1] = 'Folder' end
	return table.concat(active, '  |  ')
end

local menu_items = {
	{label = 'Start position', value = function() return clock(start_mark) .. '  [Enter = mark current frame]' end,
		action = function() mark('start') end},
	{label = 'End position', value = function() return clock(end_mark) .. '  [Enter = mark current frame]' end,
		action = function() mark('end') end},
	{label = 'Output width', value = function(limits)
		local maxw = limits and (limits.max_width .. ' px') or 'Unknown'
		return (width == '' and 'Original' or (width .. ' px')) .. '  [max ' .. maxw .. ']'
	end, action = function() edit_option('width') end},
	{label = 'Output FPS', value = function(limits)
		return (fps == '' and 'Original' or fps) .. '  [max ' .. format_fps(limits and limits.fps) .. ']'
	end, action = function() edit_option('fps') end},
	{label = 'Playback speed', value = function()
		return speed == 1 and '1x (Normal)' or (tostring(speed) .. 'x')
	end, action = function() edit_option('speed') end},
	{label = 'Subtitles', value = subtitles_label, action = toggle_menu_subtitles},
	{label = 'Custom caption', value = caption_label, action = function() edit_option('caption') end},
	{label = 'Output filename', value = function()
		return name_override == '' and 'Automatic' or name_override .. (export_format == 'gif' and '.gif' or '.webp')
	end, action = function() edit_option('filename') end},
	{label = 'Output folder', value = function()
		return directory_override == '' and 'Beside video' or shorten(directory_override, 65)
	end, action = function() edit_option('directory') end},
	{label = 'EXPORT', value = function() return job and 'Busy: encoding...' or ('Create ' .. (export_format == 'gif' and 'GIF' or 'WebP')) end,
		action = export_media},
	{label = 'Reset marks', value = function() return 'Clear both markers' end, action = function()
		start_mark, end_mark = nil, nil
		say('Start/end markers cleared.', 2)
	end},
	{label = 'Advanced settings', value = function()
		return advanced_open and 'Hide  [-]' or 'Show  [+]'
	end, action = function() advanced_open = not advanced_open end},
	{label = 'Caption start', value = function()
		return caption_start_mark and clock(caption_start_mark) or 'Clip start'
	end, action = function() mark_caption('start') end},
	{label = 'Caption end', value = function()
		return caption_end_mark and clock(caption_end_mark) or 'Clip end'
	end, action = function() mark_caption('end') end},
	{label = 'Reset caption timing', value = function() return 'Show for full export' end,
		action = function()
			caption_start_mark, caption_end_mark, caption_mark_source = nil, nil, nil
			say('Caption timing reset to full export.', 2)
		end},
	{label = 'Lossless export (large)', value = function()
		return export_format == 'gif' and 'N/A' or (lossless_export and 'Yes' or 'No')
	end, action = function()
		if export_format == 'webp' then lossless_export = not lossless_export end
	end},
	{label = 'Export format', value = function() return export_format == 'gif' and 'GIF (Legacy)' or 'WebP (Animated)' end,
		action = function()
			export_format = export_format == 'gif' and 'webp' or 'gif'
		end},
}

local function act_on_menu()
	local item = menu_items[menu_index]
	if item then item.action() end
	if menu_open then draw_menu() end
end

local function menu_shape(lines, x, y, w, h, radius, color, alpha)
	local path
	if radius > 0 then
		local r = radius
		local half_r = math.floor(r / 2)
		path = string.format(
			'm %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d ' ..
			'l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d',
			x + r, y, x + w - r, y,
			x + w - half_r, y, x + w, y + half_r, x + w, y + r,
			x + w, y + h - r,
			x + w, y + h - half_r, x + w - half_r, y + h, x + w - r, y + h,
			x + r, y + h,
			x + half_r, y + h, x, y + h - half_r, x, y + h - r,
			x, y + r,
			x, y + half_r, x + half_r, y, x + r, y)
	else
		path = string.format('m %d %d l %d %d %d %d %d %d',
			x, y, x + w, y, x + w, y + h, x, y + h)
	end
	lines[#lines + 1] = string.format(
		'{\\rDefault\\an7\\pos(%.3f,%.3f)\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H%02X&\\p1}%s{\\p0}',
		gui_offset_x, gui_offset_y, color, alpha, path)
end


local function menu_logo_watermark(lines, panel_x, panel_y, panel_w, panel_h)
    local base_size = 62.5
    local scale = 700
    local draw_size = base_size * scale / 100
    local x = panel_x + (panel_w - draw_size) / 2 + gui_offset_x
    local y = panel_y + (panel_h - draw_size) / 2 + gui_offset_y
    local clip_x1 = panel_x + gui_offset_x
    local clip_y1 = panel_y + gui_offset_y
    local clip_x2 = panel_x + panel_w + gui_offset_x
    local clip_y2 = panel_y + panel_h + gui_offset_y
    for index, alpha in ipairs({'D6', 'D6', 'E4'}) do
        local vector = logo_vectors[index]
        lines[#lines + 1] = string.format(
            '{\\rDefault\\an7\\pos(%.3f,%.3f)\\fscx%.2f\\fscy%.2f\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H%s&\\clip(%.3f,%.3f,%.3f,%.3f)\\p4}%s{\\p0}',
            x, y, scale, scale, vector[1], alpha, clip_x1, clip_y1, clip_x2, clip_y2, vector[2])
    end
end

local menu_font_cache = {}

local function menu_text(lines, x, y, content, size, color, align, bold)
	x, y = x + gui_offset_x, y + gui_offset_y
	local font_key = size * 2 + (bold and 1 or 0)
	local font = menu_font_cache[font_key]
	if not font then
		font = string.format('\\fnSegoe UI\\fs%d\\b%d\\q2\\bord0\\shad0',
			size, bold and 1 or 0)
		menu_font_cache[font_key] = font
	end
	local text = ass_escape(content)

	lines[#lines + 1] = string.format(
		'{\\rDefault\\an%d\\pos(%.1f,%.1f)%s\\1c&H000000&\\1a&H80&\\blur1.2}%s',
		align or 7, x + 1.5, y + 2, font, text)

	lines[#lines + 1] = string.format(
		'{\\rDefault\\an%d\\pos(%.1f,%.1f)%s\\1c&H%s&\\1a&H00&\\blur0}%s',
		align or 7, x, y, font, color, text)
end

local function menu_selection(lines, x, y, width, height, marker_y, marker_height)
	menu_shape(lines, x, y, width, height, 7, '514237', 70)
	menu_shape(lines, x + 5, marker_y, 3, marker_height, 1, '21B6F2', 0)
end

local function menu_row(lines, index, y, label, value, compact, nested, disabled)
	local selected = not disabled and menu_index == index
	local indent = nested and 28 or 0
	local row_height = compact and 35 or 40
	local text_y = y + row_height / 2 - 2
	if selected then
		local marker_height = compact and 19 or 20
		menu_selection(lines, 365 + indent, y, 550 - indent, row_height,
			y + (row_height - marker_height) / 2, marker_height)
	end
	menu_text(lines, (selected and 399 or 394) + indent, text_y, label, 25,
		disabled and '88929E' or (selected and 'FFFFFF' or 'E0E4EB'), 4, true)
	menu_text(lines, 899, text_y, shorten(value, 32), 24,
		disabled and '88929E' or (selected and 'FFFFFF' or 'F0F2F5'), 6, selected)
end

local function menu_section(lines, y, label, index, value)
	local selected = index and menu_index == index
	local text_y = index and (y + 11.5 - 2) or y
	if selected then menu_selection(lines, 365, y - 5, 550, 33, y + 2, 19) end
	menu_text(lines, 380, text_y, label, 17,
		selected and 'FFFFFF' or '21B6F2', index and 4 or 7, true)
	if value then
		menu_text(lines, 899, text_y, value, 17,
			selected and 'FFFFFF' or 'BEC6D1', index and 6 or 9, selected)
	end
end

local advanced_rows = {
	{index = 4, label = 'Frame rate', strip = '%s+%[max.*$'},
	{index = 5, label = 'Playback speed'},
	{index = 17, label = 'Export format'},
	{index = 16, label = 'Lossless export (large)', disabled_in_gif = true},
	{index = 7, label = 'Custom caption', strip = '%s+%[Enter.*$'},
	{index = 13, label = 'Caption start', caption_only = true, nested = true},
	{index = 14, label = 'Caption end', caption_only = true, nested = true},
	{index = 15, label = 'Reset caption timing', caption_only = true, nested = true},
	{index = 8, label = 'Filename'},
	{index = 9, label = 'Save to'},
	{index = 11, label = 'Reset marks', display_value = 'Clear start and end'},
}

local function advanced_menu_rows()
	local rows = {}
	for _, row in ipairs(advanced_rows) do
		if not row.caption_only or caption_enabled then rows[#rows + 1] = row end
	end
	return rows
end

local function menu_display_value(index, limits, strip)
	local value = menu_items[index].value(limits)
	return strip and (value:gsub(strip, '')) or value
end

local function visible_menu_items()
	local items = {1, 2, 3, 6, 12}
	if advanced_open then
		for _, row in ipairs(advanced_menu_rows()) do
			if not (row.disabled_in_gif and export_format == 'gif') then
				items[#items + 1] = row.index
			end
		end
	end
	items[#items + 1] = 10
	return items
end

draw_menu = function()
	if not menu_open then return end
	update_menu_geometry()
	local src = mp.get_property('filename') or '(no file)'
	local limits = source_limits()
	local caption_controls = advanced_open and caption_enabled
	local summary = advanced_open and '' or advanced_summary()
	local advanced_items = advanced_open and advanced_menu_rows() or {}
	local row_step = caption_controls and 35 or 43
	local panel_height = caption_controls and 560 or 571
	if advanced_open then
		panel_height = panel_height + #advanced_items * row_step
	elseif summary ~= '' then
		panel_height = panel_height + 27
	end
	local panel_y = math.floor((960 - panel_height) / 2)
	local lines = {}

	menu_shape(lines,375,panel_y + 24,4,39,2,'21B6F2',0)
	menu_text(lines, 391, panel_y + 19, 'GIFit', 43, 'FFFFFF', 7, true)
	menu_text(lines, 905, panel_y + 29, export_format == 'gif' and 'GIF EXPORTER' or 'ANIMATED WEBP EXPORTER', 17, 'D1DAE6', 9, true)
	menu_text(lines, 905, panel_y + 44, '(SDR ONLY)', 17, 'D1DAE6', 9, true)
	menu_text(lines, 379, panel_y + 84, shorten(src, 63), 19, 'E3E7ED', 7, false)
	menu_shape(lines,375,panel_y + 127,530,1,0,'635850',85)

	local y = panel_y + 141
	menu_section(lines, y, 'TIMING')
	y = y + 25
	menu_row(lines, 1, y, 'Start', (menu_display_value(1, limits, '%s+%[Enter.*$')))
	y = y + 43
	menu_row(lines, 2, y, 'End', (menu_display_value(2, limits, '%s+%[Enter.*$')))
	y = y + 43
	if start_mark and end_mark and end_mark > start_mark then
		local duration = inclusive_timing(start_mark, end_mark, limits).duration
		menu_text(lines, 394, y + 0, 'Clip  ' .. clock(duration), 19, 'D5DCE5', 7, false)
		menu_text(lines, 899, y + 0, (export_format == 'gif' and 'GIF' or 'WebP') .. '  ' .. clock(duration / speed), 19, '21B6F2', 9, false)
	else
		menu_text(lines, 394, y + 0, 'Mark both positions to see the duration', 19, 'C6CED9', 7, false)
	end
	y = y + (caption_controls and 34 or 40)

	menu_section(lines, y, 'VIDEO')
	y = y + 24
	menu_row(lines, 3, y, 'Width', menu_display_value(3, limits, '%s+%[max.*$'), true)
	y = y + 43

	menu_row(lines, 6, y, 'Subtitles', menu_display_value(6, limits, '%s+%[Enter.*$'), true)
	y = y + 48

	menu_section(lines, y, 'ADVANCED SETTINGS', 12, menu_items[12].value(limits))
	y = y + (caption_controls and 27 or 32)
	if advanced_open then
		for _, row in ipairs(advanced_items) do
			local value = row.display_value or menu_display_value(row.index, limits, row.strip)
			local disabled = row.disabled_in_gif and export_format == 'gif'
			menu_row(lines, row.index, y, row.label, value, caption_controls, row.nested, disabled)
			y = y + row_step
		end
	else
		if summary ~= '' then
			menu_text(lines, 640, y, shorten(summary, 70), 19, 'D5DCE5', 8, false)
			y = y + 27
		end
	end

	menu_shape(lines,375,y + 12,530,1,0,'635850',85)
	y = y + 25
	menu_shape(lines,365,y,550,51,8,menu_index == 10 and '21B6F2' or '635850',menu_index == 10 and 18 or 80)
	menu_text(lines, 640, y + 25.5, job and 'ENCODING...' or ('EXPORT ' .. (export_format == 'gif' and 'GIF' or 'WEBP')), 25, 'FFFFFF', 5, true)
	y = y + 60
	menu_text(lines, 640, y + 9, 'UP/DOWN  Navigate     ENTER  Select     ESC  Close',
		17, 'D5DCE5', 8, false)

	local background = {}
	local panel_h = y + 47 - panel_y
	menu_shape(background,350,panel_y,580,panel_h,15,'171411',118)
	menu_logo_watermark(background, 350, panel_y, 580, panel_h)
	for _, line in ipairs(lines) do background[#background + 1] = line end
	overlay.data = table.concat(background, '\n')
	overlay:update()
end

close_menu = function()
	if not menu_open then return end
	menu_open = false
	overlay:remove()
	for _, binding in ipairs(menu_bindings) do mp.remove_key_binding(binding) end
end

local function move_menu(direction)
	local items = visible_menu_items()
	local position = 1
	for i, index in ipairs(items) do
		if index == menu_index then position = i; break end
	end
	menu_index = items[(position - 1 + direction) % #items + 1]
	draw_menu()
end

open_menu = function()
	if editing then return end
	if menu_open then close_menu(); return end
	local visible = false
	for _, index in ipairs(visible_menu_items()) do
		if index == menu_index then visible = true; break end
	end
	if not visible then menu_index = 12 end
	menu_open = true
	mp.add_forced_key_binding('UP', menu_bindings[1], function() move_menu(-1) end)
	mp.add_forced_key_binding('DOWN', menu_bindings[2], function() move_menu(1) end)
	mp.add_forced_key_binding('ENTER', menu_bindings[3], act_on_menu)
	mp.add_forced_key_binding('ESC', menu_bindings[4], close_menu)
	mp.add_forced_key_binding('BS', menu_bindings[5], close_menu)
	draw_menu()
end

mp.add_key_binding('', 'gifit-export-menu', open_menu)

mp.observe_property('osd-dimensions', 'native', function()
	if menu_open then draw_menu() end
end)

mp.register_event('file-loaded', function()
	if menu_open then close_menu() end
	start_mark, end_mark, mark_source = nil, nil, nil
	name_override = ''
	width = ''
	subtitles_enabled = false
	caption_text, caption_enabled = '', false
	caption_start_mark, caption_end_mark, caption_mark_source = nil, nil, nil
	advanced_open = false
end)

mp.register_event('shutdown', function()
	if active_export_request then
		mp.abort_async_command(active_export_request)
	elseif active_temp_work then
		cleanup_temp_work(active_temp_work)
		active_temp_work = nil
	end
end)

cleanup_abandoned_temp_files()

mp.msg.info('GIFit loaded: Ctrl+g menu; start/end markers are menu items; FFmpeg=' .. cfg.ffmpeg .. '; FFprobe=' .. probe_exe)