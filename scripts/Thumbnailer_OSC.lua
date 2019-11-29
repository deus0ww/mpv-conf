local ipairs,loadfile,pairs,pcall,tonumber,tostring = ipairs,loadfile,pairs,pcall,tonumber,tostring
local debug,io,math,os,string,table,utf8 = debug,io,math,os,string,table,utf8
local min,max,floor,ceil,huge = math.min,math.max,math.floor,math.ceil,math.huge
local mp      = require 'mp'
local assdraw = require 'mp.assdraw'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'

--
-- Parameters
--
-- default user option values
-- do not touch, change them in osc.conf
local user_opts = {
    showwindowed = true,        -- show OSC when windowed?
    showfullscreen = true,      -- show OSC when fullscreen?
    scalewindowed = 1,          -- scaling of the controller when windowed
    scalefullscreen = 1,        -- scaling of the controller when fullscreen
    scaleforcedwindow = 2,      -- scaling when rendered on a forced window
    vidscale = true,            -- scale the controller with the video?
    valign = 0.8,               -- vertical alignment, -1 (top) to 1 (bottom)
    halign = 0,                 -- horizontal alignment, -1 (left) to 1 (right)
    barmargin = 0,              -- vertical margin of top/bottombar
    boxalpha = 80,              -- alpha of the background box,
                                -- 0 (opaque) to 255 (fully transparent)
    hidetimeout = 500,          -- duration in ms until the OSC hides if no
                                -- mouse movement. enforced non-negative for the
                                -- user, but internally negative is "always-on".
    fadeduration = 200,         -- duration of fade out in ms, 0 = no fade
    deadzonesize = 0.5,         -- size of deadzone
    minmousemove = 0,           -- minimum amount of pixels the mouse has to
                                -- move between ticks to make the OSC show up
    iamaprogrammer = false,     -- use native mpv values and disable OSC
                                -- internal track list management (and some
                                -- functions that depend on it)
    layout = "bottombar",
    seekbarstyle = "bar",       -- bar, diamond or knob
    seekbarhandlesize = 0.6,    -- size ratio of the diamond and knob handle
    seekrangestyle = "inverted",-- bar, line, slider, inverted or none
    seekrangeseparate = true,   -- wether the seekranges overlay on the bar-style seekbar
    seekrangealpha = 200,       -- transparency of seekranges
    seekbarkeyframes = true,    -- use keyframes when dragging the seekbar
    title = "${media-title}",   -- string compatible with property-expansion
                                -- to be shown as OSC title
    tooltipborder = 1,          -- border of tooltip in bottom/topbar
    timetotal = false,          -- display total time instead of remaining time?
    timems = false,             -- display timecodes with milliseconds?
    visibility = "auto",        -- only used at init to set visibility_mode(...)
    boxmaxchars = 80,           -- title crop threshold for box layout
    boxvideo = false,           -- apply osc_param.video_margins to video
    windowcontrols = "no",      -- where to show window controls (or not at all)
}

-- read_options may modify hidetimeout, so save the original default value in
-- case the user set hidetimeout < 0 and we need the default instead.
local hidetimeout_def = user_opts.hidetimeout
-- read options from config and command-line
opt.read_options(user_opts, "osc")
if user_opts.hidetimeout < 0 then
    user_opts.hidetimeout = hidetimeout_def
    msg.warn("hidetimeout cannot be negative. Using " .. user_opts.hidetimeout)
end








-- deus0ww - 2019-11-29

------------
-- tn_osc --
------------
local message = {
	osc = {
		registration  = 'tn_osc_registration',
		reset         = 'tn_osc_reset',
		update        = 'tn_osc_update',
		finish        = 'tn_osc_finish',
	},
	debug = 'Thumbnailer-debug',

	queued     = 1,
	processing = 2,
	ready      = 3,
	failed     = 4,
}


-----------
-- Utils --
-----------
local OS_MAC, OS_WIN, OS_NIX = 'MAC', 'WIN', 'NIX'
local function get_os()
	if jit and jit.os then
		if jit.os == 'Windows' then return OS_WIN
		elseif jit.os == 'OSX' then return OS_MAC
		else return OS_NIX end
	end
	if (package.config:sub(1,1) ~= '/') then return OS_WIN end
	local success, file = pcall(io.popen, 'uname -s')
	if not (success and file) then return OS_MAC end
	local line = file:read('*l')
	file:close()
	return (line and line:lower() ~= 'darwin') and OS_NIX or OS_MAC
end
local OPERATING_SYSTEM = get_os()

local function format_json(tab)
	local json, err = utils.format_json(tab)
	if err then msg.error('Formatting JSON failed:', err) end
	if json then return json else return '' end
end

local function parse_json(json)
	local tab, err = utils.parse_json(json, true)
	if err then msg.error('Parsing JSON failed:', err) end
	if tab then return tab else return {} end
end

local function join_paths(...)
	local sep = OPERATING_SYSTEM == OS_WIN and '\\' or '/'
	local result = ''
	for _, p in ipairs({...}) do
		result = (result == '') and p or result .. sep .. p
	end
	return result
end


--------------------
-- Data Structure --
--------------------
local tn_state, tn_osc, tn_osc_options, tn_osc_stats
local tn_thumbnails_indexed, tn_thumbnails_ready
local tn_gen_time_start, tn_gen_duration

local function reset_all()
	tn_state              = nil
	tn_osc = {
		cursor            = {},
		position          = {},
		scale             = {},
		osc_scale         = {},
		spacer            = {},
		osd               = {},
		background        = {text = '︎✇',},
		font_scale        = {},
		display_progress  = {},
		progress          = {},
		mini              = {text = '⚆',},
		thumbnail = {
			visible       = false,
			path_last     = nil,
			x_last        = nil,
			y_last        = nil,
		},
	}
	tn_osc_options        = nil
	tn_osc_stats = {
		queued            = 0,
		processing        = 0,
		ready             = 0,
		failed            = 0,
		total             = 0,
		total_expected    = 0,
		percent           = 0,
		timer             = 0,
	}
	tn_thumbnails_indexed = {}
	tn_thumbnails_ready   = {}
	tn_gen_time_start     = nil
	tn_gen_duration       = nil
end

------------
-- TN OSC --
------------
local mpv_cmd = {async = 'async', overlay_add = 'overlay-add', overlay_remove = 'overlay-remove', script_message = 'script-message', bgra = 'bgra',}

local osc_reg = {
	script_name = mp.get_script_name(),
	osc_opts = {
		scalewindowed   = user_opts.scalewindowed,
		scalefullscreen = user_opts.scalefullscreen,
	},
}
mp.command_native({mpv_cmd.script_message, message.osc.registration, format_json(osc_reg)})

local tn_palette = {
	black        = '000000',
	white        = 'FFFFFF',
	alpha_opaque = 0,
	alpha_clear  = 255,
	alpha_black  = min(255, user_opts.boxalpha),
	alpha_white  = min(255, user_opts.boxalpha + (255 - user_opts.boxalpha) * 0.8),
}

local tn_style_format = {
	background     = '{\\bord0\\1c&H%s&\\1a&H%X&}',
	subbackground  = '{\\bord0\\1c&H%s&\\1a&H%X&}',
	spinner        = '{\\bord0\\fs%d\\fscx%f\\fscy%f',
	spinner2       = '\\1c&%s&\\1a&H%X&\\frz%d}',
	closest_index  = '{\\1c&H%s&\\1a&H%X&\\3c&H%s&\\3a&H%X&\\xbord%d\\ybord%d}',
	progress_mini  = '{\\bord0\\1c&%s&\\1a&H%X&\\fs18\\fscx%f\\fscy%f',
	progress_mini2 = '\\frz%d}',
	progress_block = '{\\bord0\\1c&H%s&\\1a&H%X&}',
	progress_text  = '{\\1c&%s&\\3c&H%s&\\1a&H%X&\\3a&H%X&\\blur0.25\\fs18\\fscx%f\\fscy%f\\xbord%f\\ybord%f}',
	text_timer     = '%.2ds',
	text_progress  = '%.3d/%.3d',
	text_progress2 = '[%d]',
	text_percent   = '%d%%',
}

local tn_style = {
	background     = (tn_style_format.background):format(tn_palette.black, tn_palette.alpha_black),
	subbackground  = (tn_style_format.subbackground):format(tn_palette.white, tn_palette.alpha_white),
	spinner        = (tn_style_format.spinner):format(0, 1, 1),
	closest_index  = (tn_style_format.closest_index):format(tn_palette.white, tn_palette.alpha_black, tn_palette.black, tn_palette.alpha_black, -1, -1),
	progress_mini  = (tn_style_format.progress_mini):format(tn_palette.white, tn_palette.alpha_opaque, 1, 1),
	progress_block = (tn_style_format.progress_block):format(tn_palette.white, tn_palette.alpha_white),
	progress_text  = (tn_style_format.progress_text):format(tn_palette.white, tn_palette.black, tn_palette.alpha_opaque, tn_palette.alpha_black, 1, 1, 2, 2),
}

local function set_thumbnail_above(offset)
	local tn_osc = tn_osc
	tn_osc.background.bottom   = tn_osc.position.y - offset - tn_osc.spacer.bottom
	tn_osc.background.top      = tn_osc.background.bottom - tn_osc.background.h
	tn_osc.thumbnail.top       = tn_osc.background.bottom - tn_osc.thumbnail.h
	tn_osc.progress.top        = tn_osc.background.bottom - tn_osc.background.h
	tn_osc.progress.mid        = tn_osc.progress.top + tn_osc.progress.h * 0.5
	tn_osc.background.rotation = -1
end

local function set_thumbnail_below(offset)
	local tn_osc = tn_osc
	tn_osc.background.top      = tn_osc.position.y + offset + tn_osc.spacer.top
	tn_osc.thumbnail.top       = tn_osc.background.top
	tn_osc.progress.top        = tn_osc.background.top + tn_osc.thumbnail.h + tn_osc.spacer.y
	tn_osc.progress.mid        = tn_osc.progress.top + tn_osc.progress.h * 0.5
	tn_osc.background.rotation = 1
end

local function set_mini_above() tn_osc.mini.y = (tn_osc.background.top    - 12 * tn_osc.osc_scale.y) end
local function set_mini_below() tn_osc.mini.y = (tn_osc.background.bottom + 12 * tn_osc.osc_scale.y) end

local set_thumbnail_layout = {
	topbar    = function()	tn_osc.spacer.top   = 0.25
							set_thumbnail_below(38.75)
							set_mini_above() end,
	bottombar = function()	tn_osc.spacer.bottom = 0.25
							set_thumbnail_above(38.75)
							set_mini_below() end,
	box       = function()	set_thumbnail_above(15)
							set_mini_above() end,
	slimbox   = function()	set_thumbnail_above(12)
							set_mini_above() end,
}

local function update_tn_osc_params(seek_y)
	local tn_state, tn_osc_stats, tn_osc, tn_style, tn_style_format = tn_state, tn_osc_stats, tn_osc, tn_style, tn_style_format
	tn_osc.scale.x, tn_osc.scale.y   = get_virt_scale_factor()
	tn_osc.osd.w, tn_osc.osd.h       = mp.get_osd_size()
	tn_osc.cursor.x, tn_osc.cursor.y = get_virt_mouse_pos()
	tn_osc.position.y                = seek_y

	local osc_changed = false
	if     tn_osc.scale.x_last ~= tn_osc.scale.x or tn_osc.scale.y_last ~= tn_osc.scale.y
		or tn_osc.w_last       ~= tn_state.width or tn_osc.h_last       ~= tn_state.height
		or tn_osc.osd.w_last   ~= tn_osc.osd.w   or tn_osc.osd.h_last   ~= tn_osc.osd.h
	then
		tn_osc.scale.x_last, tn_osc.scale.y_last = tn_osc.scale.x, tn_osc.scale.y
		tn_osc.w_last, tn_osc.h_last             = tn_state.width, tn_state.height
		tn_osc.osd.w_last, tn_osc.osd.h_last     = tn_osc.osd.w, tn_osc.osd.h
		osc_changed = true
	end

	if osc_changed then
		tn_osc.osc_scale.x, tn_osc.osc_scale.y   = 1, 1
		tn_osc.spacer.x, tn_osc.spacer.y         = tn_osc_options.spacer, tn_osc_options.spacer
		tn_osc.font_scale.x, tn_osc.font_scale.y = 100, 100
		tn_osc.progress.h                        = (16 + tn_osc_options.spacer)
		if not user_opts.vidscale then
			tn_osc.osc_scale.x  = tn_osc.scale.x     * tn_osc_options.scale
			tn_osc.osc_scale.y  = tn_osc.scale.y     * tn_osc_options.scale
			tn_osc.spacer.x     = tn_osc.osc_scale.x * tn_osc.spacer.x
			tn_osc.spacer.y     = tn_osc.osc_scale.y * tn_osc.spacer.y
			tn_osc.font_scale.x = tn_osc.osc_scale.x * tn_osc.font_scale.x
			tn_osc.font_scale.y = tn_osc.osc_scale.y * tn_osc.font_scale.y
			tn_osc.progress.h   = tn_osc.osc_scale.y * tn_osc.progress.h
		end
		tn_osc.spacer.top, tn_osc.spacer.bottom  = tn_osc.spacer.y, tn_osc.spacer.y
		tn_osc.thumbnail.w, tn_osc.thumbnail.h   = tn_state.width * tn_osc.scale.x, tn_state.height * tn_osc.scale.y
		tn_osc.osd.w_scaled, tn_osc.osd.h_scaled = tn_osc.osd.w * tn_osc.scale.x, tn_osc.osd.h * tn_osc.scale.y
		tn_style.spinner                         = (tn_style_format.spinner):format(min(tn_osc.thumbnail.w, tn_osc.thumbnail.h) * 0.6667, tn_osc.font_scale.x, tn_osc.font_scale.y)
		tn_style.closest_index                   = (tn_style_format.closest_index):format(tn_palette.white, tn_palette.alpha_black, tn_palette.black, tn_palette.alpha_black, -1 * tn_osc.scale.x, -1 * tn_osc.scale.y)
		if tn_osc_stats.percent < 1 then
			tn_style.progress_text = (tn_style_format.progress_text):format(tn_palette.white, tn_palette.black, tn_palette.alpha_opaque, tn_palette.alpha_black, tn_osc.font_scale.x, tn_osc.font_scale.y, 2 * tn_osc.scale.x, 2 * tn_osc.scale.y)
			tn_style.progress_mini = (tn_style_format.progress_mini):format(tn_palette.white, tn_palette.alpha_opaque, tn_osc.font_scale.x, tn_osc.font_scale.y)
		end
	end
	
	if not tn_osc.position.y then return end
	if (osc_changed or tn_osc.cursor.x_last ~= tn_osc.cursor.x) and tn_osc.osd.w_scaled >= (tn_osc.thumbnail.w + 2 * tn_osc.spacer.x) then
		tn_osc.cursor.x_last  = tn_osc.cursor.x
		if tn_osc_options.centered then
			tn_osc.position.x = tn_osc.osd.w_scaled * 0.5
		else
			local limit_left  = tn_osc.spacer.x + tn_osc.thumbnail.w * 0.5
			local limit_right = tn_osc.osd.w_scaled - limit_left
			tn_osc.position.x = min(max(tn_osc.cursor.x, limit_left), limit_right)
		end
		tn_osc.thumbnail.left, tn_osc.thumbnail.right = tn_osc.position.x - tn_osc.thumbnail.w * 0.5, tn_osc.position.x + tn_osc.thumbnail.w * 0.5
		tn_osc.mini.x = tn_osc.thumbnail.right - 6 * tn_osc.osc_scale.x
	end
	
	if (osc_changed or tn_osc.display_progress.last ~= tn_osc.display_progress.current) then
		tn_osc.display_progress.last = tn_osc.display_progress.current
		tn_osc.background.h          = tn_osc.thumbnail.h + (tn_osc.display_progress.current and (tn_osc.progress.h + tn_osc.spacer.y) or 0)
		set_thumbnail_layout[user_opts.layout]()
	end
end

local function find_closest(seek_index, round_up)
	local tn_state, tn_thumbnails_indexed, tn_thumbnails_ready = tn_state, tn_thumbnails_indexed, tn_thumbnails_ready
	if not (tn_thumbnails_indexed and tn_thumbnails_ready) then return nil, nil end
	local time_index = floor(seek_index * tn_state.delta)
	if tn_thumbnails_ready[time_index] then return seek_index + 1, tn_thumbnails_indexed[time_index] end
	local direction, index = round_up and 1 or -1
	for i = 1, tn_osc_stats.total_expected do
		index        = seek_index + (i * direction)
		time_index   = floor(index * tn_state.delta)
		if tn_thumbnails_ready[time_index] then return index + 1, tn_thumbnails_indexed[time_index] end
		index        = seek_index + (i * -direction)
		time_index   = floor(index * tn_state.delta)
		if tn_thumbnails_ready[time_index] then return index + 1, tn_thumbnails_indexed[time_index] end
	end
	return nil, nil
end

local id = 9
local cmd_async

local function draw_thumbnail(x, y, path)
	if cmd_async then mp.abort_async_command(cmd_async) end
	cmd_async = mp.command_native_async( { mpv_cmd.overlay_add, id, x, y, path, 0, mpv_cmd.bgra, tn_state.width, tn_state.height, tn_state.width * 4 }, function() end )
	tn_osc.thumbnail.visible = true
end

local function hide_thumbnail()
	if tn_osc and tn_osc.thumbnail and tn_osc.thumbnail.visible then
		if cmd_async then mp.abort_async_command(cmd_async) end
		cmd_async = mp.command_native_async( { mpv_cmd.overlay_remove, id }, function() end )
		tn_osc.thumbnail.visible = false
	end
end

local function show_thumbnail(seek_percent)
	if not seek_percent then return nil, nil end
	local scale, thumbnail, total_expected, ready = tn_osc.scale, tn_osc.thumbnail, tn_osc_stats.total_expected, tn_osc_stats.ready
	local seek = seek_percent * (total_expected - 1)
	local seek_index = floor(seek + 0.5)
	local closest_index, path = thumbnail.closest_index_last, thumbnail.path_last
	if     thumbnail.seek_index_last     ~= seek_index
		or thumbnail.ready_last          ~= ready
		or thumbnail.total_expected_last ~= tn_osc_stats.total_expected
	then
		closest_index, path = find_closest(seek_index, seek_index < seek)
		thumbnail.closest_index_last, thumbnail.total_expected_last, thumbnail.ready_last, thumbnail.seek_index_last = closest_index, total_expected, ready, seek_index
	end
	local x, y = floor(thumbnail.left / scale.x + 0.5), floor(thumbnail.top / scale.y + 0.5)
	if path and not (thumbnail.visible and thumbnail.x_last == x and thumbnail.y_last == y and thumbnail.path_last == path) then
		thumbnail.x_last, thumbnail.y_last, thumbnail.path_last  = x, y, path
		draw_thumbnail(x, y, path)
	end
	return closest_index, path
end

local function ass_new(ass, x, y, align, style, text)
	ass:new_event()
	ass:pos(x, y)
	if align then ass:an(align)     end
	if style then ass:append(style) end
	if text  then ass:append(text)  end
end

local function ass_rect(ass, x1, y1, x2, y2)
	ass:draw_start()
	ass:rect_cw(x1, y1, x2, y2)
	ass:draw_stop()
end

local draw_progress = {
	[message.queued]     = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w,             0, index * block_w, block_h) end,
	[message.processing] = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w, block_h * 0.2, index * block_w, block_h * 0.8) end,
	[message.failed]     = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w, block_h * 0.4, index * block_w, block_h * 0.6) end,
}

local function display_tn_osc(seek_y, seek_percent, ass)
	if not (seek_y and seek_percent and ass and tn_state and tn_osc_stats and tn_osc_options and tn_state.width and tn_state.height and tn_state.duration and tn_state.cache_dir) or not tn_osc_options.visible then hide_thumbnail() return end

	update_tn_osc_params(seek_y)
	local tn_osc_stats, tn_osc, tn_style, tn_style_format, ass_new, ass_rect, seek_percent = tn_osc_stats, tn_osc, tn_style, tn_style_format, ass_new, ass_rect, seek_percent * 0.01
	local closest_index, path = show_thumbnail(seek_percent)

	-- Background
	ass_new(ass, tn_osc.thumbnail.left, tn_osc.background.top, 7, tn_style.background)
	ass_rect(ass, -tn_osc.spacer.x, -tn_osc.spacer.top, tn_osc.thumbnail.w + tn_osc.spacer.x, tn_osc.background.h + tn_osc.spacer.bottom)

	local spinner_color, spinner_alpha = tn_palette.white, tn_palette.alpha_white
	if not path then
		ass_new(ass, tn_osc.thumbnail.left, tn_osc.thumbnail.top, 7, tn_style.subbackground)
		ass_rect(ass, 0, 0, tn_osc.thumbnail.w, tn_osc.thumbnail.h)
		spinner_color, spinner_alpha = tn_palette.black, tn_palette.alpha_black
	end
	ass_new(ass, tn_osc.position.x, tn_osc.thumbnail.top + tn_osc.thumbnail.h * 0.5, 5, tn_style.spinner .. (tn_style_format.spinner2):format(spinner_color, spinner_alpha, tn_osc.background.rotation * seek_percent * 1080), tn_osc.background.text)

	-- Mini Progress Spinner
	if tn_osc.display_progress.current ~= nil and not tn_osc.display_progress.current and tn_osc_stats.percent < 1 then
		ass_new(ass, tn_osc.mini.x, tn_osc.mini.y, 5, tn_style.progress_mini .. (tn_style_format.progress_mini2):format(tn_osc_stats.percent * -360 + 90), tn_osc.mini.text)
	end

	-- Progress Bar
	if tn_osc.display_progress.current then
		local block_w, index = tn_osc_stats.total_expected > 0 and tn_state.width * tn_osc.scale.y / tn_osc_stats.total_expected or 0, 0
		if tn_thumbnails_indexed and block_w > 0 then
			-- Loading bar
			ass_new(ass, tn_osc.thumbnail.left, tn_osc.progress.top, 7, tn_style.progress_block)
			ass:draw_start()
			for time_index, status in pairs(tn_thumbnails_indexed) do
				index = floor(time_index / tn_state.delta) + 1
				if index ~= closest_index and not tn_thumbnails_ready[time_index] and index <= tn_osc_stats.total_expected and draw_progress[status] ~= nil then
					draw_progress[status](ass, index, block_w, tn_osc.progress.h)
				end
			end
			ass:draw_stop()

			if closest_index and closest_index <= tn_osc_stats.total_expected then
				ass_new(ass, tn_osc.thumbnail.left, tn_osc.progress.top, 7, tn_style.closest_index)
				ass_rect(ass, (closest_index - 1) * block_w, 0, closest_index * block_w, tn_osc.progress.h)
			end
		end

		-- Text: Timer
		ass_new(ass, tn_osc.thumbnail.left + 3 * tn_osc.osc_scale.y, tn_osc.progress.mid, 4, tn_style.progress_text, (tn_style_format.text_timer):format(tn_osc_stats.timer))

		-- Text: Number or Index of Thumbnail
		local temp = tn_osc_stats.percent < 1 and tn_osc_stats.ready or closest_index
		local processing = tn_osc_stats.processing > 0 and (tn_style_format.text_progress2):format(tn_osc_stats.processing) or ''
		ass_new(ass, tn_osc.position.x, tn_osc.progress.mid, 5, tn_style.progress_text, (tn_style_format.text_progress):format(temp and temp or 0, tn_osc_stats.total_expected) .. processing)

		-- Text: Percentage
		ass_new(ass, tn_osc.thumbnail.right - 3 * tn_osc.osc_scale.y, tn_osc.progress.mid, 6, tn_style.progress_text, (tn_style_format.text_percent):format(min(100, tn_osc_stats.percent * 100)))
	end
end


---------------
-- Listeners --
---------------
mp.register_script_message(message.osc.reset, function()
	hide_thumbnail()
	reset_all()	
end)

local text_progress_format = { two_digits = '%.2d/%.2d', three_digits = '%.3d/%.3d' }

mp.register_script_message(message.osc.update, function(json)
	local new_data = parse_json(json)
	if not new_data then return end
	if new_data.state then
		tn_state = new_data.state
		if tn_state.is_rotated then tn_state.width, tn_state.height = tn_state.height, tn_state.width end
	end
	if new_data.osc_options then tn_osc_options = new_data.osc_options end
	if new_data.osc_stats then
		tn_osc_stats = new_data.osc_stats
		if tn_osc_options and tn_osc_options.show_progress then
			if     tn_osc_options.show_progress == 0 then tn_osc.display_progress.current = false
			elseif tn_osc_options.show_progress == 1 then tn_osc.display_progress.current = tn_osc_stats.percent < 1
			else                                          tn_osc.display_progress.current = true end
		end
		tn_style_format.text_progress = tn_osc_stats.total > 99 and text_progress_format.three_digits or text_progress_format.two_digits
		if tn_osc_stats.percent >= 1 then mp.command_native({mpv_cmd.script_message, message.osc.finish}) end
	end
	if new_data.thumbnails and tn_state then
		local index, ready
		for time_string, status in pairs(new_data.thumbnails) do
			index, ready = tonumber(time_string), (status == message.ready)
			tn_thumbnails_indexed[index] = ready and join_paths(tn_state.cache_dir, time_string) .. tn_state.cache_extension or status
			tn_thumbnails_ready[index]   = ready
		end
	end
end)

mp.register_script_message(message.debug, function()
	msg.info("Thumbnailer OSC Internal States:")
	msg.info("tn_state:", tn_state and utils.to_string(tn_state) or 'nil')
	msg.info("tn_thumbnails_indexed:", tn_thumbnails_indexed and utils.to_string(tn_thumbnails_indexed) or 'nil')
	msg.info("tn_thumbnails_ready:", tn_thumbnails_ready and utils.to_string(tn_thumbnails_ready) or 'nil')
	msg.info("tn_osc_options:", tn_osc_options and utils.to_string(tn_osc_options) or 'nil')
	msg.info("tn_osc_stats:", tn_osc_stats and utils.to_string(tn_osc_stats) or 'nil')
	msg.info("tn_osc:", tn_osc and utils.to_string(tn_osc) or 'nil')
end)










-------------
-- osc.lua --
-------------
local osc_param = { -- calculated by osc_init()
    playresy = 0,                           -- canvas size Y
    playresx = 0,                           -- canvas size X
    display_aspect = 1,
    unscaled_y = 0,
    areas = {},
    video_margins = {
        l = 0, r = 0, t = 0, b = 0,         -- left/right/top/bottom
    },
}

local osc_styles = {
    bigButtons = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs50\\fnmpv-osd-symbols}",
    smallButtonsL = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs19\\fnmpv-osd-symbols}",
    smallButtonsLlabel = "{\\fscx105\\fscy105\\fn" .. mp.get_property("options/osd-font") .. "}",
    smallButtonsR = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs30\\fnmpv-osd-symbols}",
    topButtons = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs12\\fnmpv-osd-symbols}",

    elementDown = "{\\1c&H999999}",
    timecodes = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs20}",
    vidtitle = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs12\\q2}",
    box = "{\\rDefault\\blur0\\bord1\\1c&H000000\\3c&HFFFFFF}",

    topButtonsBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs18\\fnmpv-osd-symbols}",
    smallButtonsBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs28\\fnmpv-osd-symbols}",
    timecodesBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs27}",
    timePosBar = "{\\blur0.4\\bord".. user_opts.tooltipborder .."\\1c&HFFFFFF\\3c&H000000\\fs27}",
    vidtitleBar = "{\\blur0\\bord0\\1c&HFFFFFF\\3c&HFFFFFF\\fs18\\q2}",

    wcButtons = "{\\1c&HFFFFFF\\fs24}",
    wcBar = "{\\1c&H000000}",
}

-- internal states, do not touch
local state = {
    showtime,                               -- time of last invocation (last mouse move)
    osc_visible = false,
    anistart,                               -- time when the animation started
    anitype,                                -- current type of animation
    animation,                              -- current animation alpha
    mouse_down_counter = 0,                 -- used for softrepeat
    active_element = nil,                   -- nil = none, 0 = background, 1+ = see elements[]
    active_event_source = nil,              -- the "button" that issued the current event
    rightTC_trem = not user_opts.timetotal, -- if the right timecode should display total or remaining time
    tc_ms = user_opts.timems,               -- Should the timecodes display their time with milliseconds
    mp_screen_sizeX, mp_screen_sizeY,       -- last screen-resolution, to detect resolution changes to issue reINITs
    initREQ = false,                        -- is a re-init request pending?
    last_mouseX, last_mouseY,               -- last mouse position, to detect significant mouse movement
    message_text,
    message_timeout,
    fullscreen = false,
    timer = nil,
    cache_idle = false,
    idle = false,
    enabled = true,
    input_enabled = true,
    showhide_enabled = false,
    dmx_cache = 0,
    using_video_margins = false,
}

local window_control_box_width = 80


--
-- Helperfunctions
--

local margins_opts = {
    {"l", "video-margin-ratio-left"},
    {"r", "video-margin-ratio-right"},
    {"t", "video-margin-ratio-top"},
    {"b", "video-margin-ratio-bottom"},
}

-- scale factor for translating between real and virtual ASS coordinates
function get_virt_scale_factor()
    local w, h = mp.get_osd_size()
    if w <= 0 or h <= 0 then
        return 0, 0
    end
    return osc_param.playresx / w, osc_param.playresy / h
end

-- return mouse position in virtual ASS coordinates (playresx/y)
function get_virt_mouse_pos()
    local sx, sy = get_virt_scale_factor()
    local x, y = mp.get_mouse_pos()
    return x * sx, y * sy
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

-- returns hitbox spanning coordinates (top left, bottom right corner)
-- according to alignment
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

-- translate value into element coordinates
function get_slider_ele_pos_for(element, val)

    local ele_pos = scale_value(
        element.slider.min.value, element.slider.max.value,
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        val)

    return limit_range(
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        ele_pos)
end

-- translates global (mouse) coordinates to value
function get_slider_value_at(element, glob_pos)

    local val = scale_value(
        element.slider.min.glob_pos, element.slider.max.glob_pos,
        element.slider.min.value, element.slider.max.value,
        glob_pos)

    return limit_range(
        element.slider.min.value, element.slider.max.value,
        val)
end

-- get value at current mouse position
function get_slider_value(element)
    return get_slider_value_at(element, get_virt_mouse_pos())
end

function countone(val)
    if not (user_opts.iamaprogrammer) then
        val = val + 1
    end
    return val
end

-- align:  -1 .. +1
-- frame:  size of the containing area
-- obj:    size of the object that should be positioned inside the area
-- margin: min. distance from object to frame (as long as -1 <= align <= +1)
function get_align(align, frame, obj, margin)
    return (frame / 2) + (((frame / 2) - margin - (obj / 2)) * align)
end

-- multiplies two alpha values, formular can probably be improved
function mult_alpha(alphaA, alphaB)
    return 255 - (((1-(alphaA/255)) * (1-(alphaB/255))) * 255)
end

function add_area(name, x1, y1, x2, y2)
    -- create area if needed
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

function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
    end
end

function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_ccw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_ccw(x0, y0, x1, y1, r1, r2)
    end
end


--
-- Tracklist Management
--

local nicetypes = {video = "Video", audio = "Audio", sub = "Subtitle"}

-- updates the OSC internal playlists, should be run each time the track-layout changes
function update_tracklist()
    local tracktable = mp.get_property_native("track-list", {})

    -- by osc_id
    tracks_osc = {}
    tracks_osc.video, tracks_osc.audio, tracks_osc.sub = {}, {}, {}
    -- by mpv_id
    tracks_mpv = {}
    tracks_mpv.video, tracks_mpv.audio, tracks_mpv.sub = {}, {}, {}
    for n = 1, #tracktable do
        if not (tracktable[n].type == "unknown") then
            local type = tracktable[n].type
            local mpv_id = tonumber(tracktable[n].id)

            -- by osc_id
            table.insert(tracks_osc[type], tracktable[n])

            -- by mpv_id
            tracks_mpv[type][mpv_id] = tracktable[n]
            tracks_mpv[type][mpv_id].osc_id = #tracks_osc[type]
        end
    end
end

-- return a nice list of tracks of the given type (video, audio, sub)
function get_tracklist(type)
    local msg = "Available " .. nicetypes[type] .. " Tracks: "
    if #tracks_osc[type] == 0 then
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

-- relatively change the track of given <type> by <next> tracks
    --(+1 -> next, -1 -> previous)
function set_track(type, next)
    local current_track_mpv, current_track_osc
    if (mp.get_property(type) == "no") then
        current_track_osc = 0
    else
        current_track_mpv = tonumber(mp.get_property(type))
        current_track_osc = tracks_mpv[type][current_track_mpv].osc_id
    end
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

-- get the currently selected track of <type>, OSC-style counted
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


--
-- Element Management
--

local elements = {}

function prepare_elements()

    -- remove elements without layout or invisble
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

        -- Calculate the hitbox
        local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
        element.hitbox = {x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2}

        local style_ass = assdraw.ass_new()

        -- prepare static elements
        style_ass:append("{}") -- hack to troll new_event into inserting a \n
        style_ass:new_event()
        style_ass:pos(elem_geo.x, elem_geo.y)
        style_ass:an(elem_geo.an)
        style_ass:append(element.layout.style)

        element.style_ass = style_ass

        local static_ass = assdraw.ass_new()


        if (element.type == "box") then
            --draw box
            static_ass:draw_start()
            ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
                             element.layout.box.radius, element.layout.box.hexagon)
            static_ass:draw_stop()

        elseif (element.type == "slider") then
            --draw static slider parts

            local r1 = 0
            local r2 = 0
            local slider_lo = element.layout.slider
            -- offset between element outline and drag-area
            local foV = slider_lo.border + slider_lo.gap

            -- calculate positions of min and max points
            if (slider_lo.stype ~= "bar") then
                r1 = elem_geo.h / 2
                element.slider.min.ele_pos = elem_geo.h / 2
                element.slider.max.ele_pos = elem_geo.w - (elem_geo.h / 2)
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

            -- -- --

            static_ass:draw_start()

            -- the box
            ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h, r1, slider_lo.stype == "diamond")

            -- the "hole"
            ass_draw_rr_h_ccw(static_ass, slider_lo.border, slider_lo.border,
                              elem_geo.w - slider_lo.border, elem_geo.h - slider_lo.border,
                              r2, slider_lo.stype == "diamond")

            -- marker nibbles
            if not (element.slider.markerF == nil) and (slider_lo.gap > 0) then
                local markers = element.slider.markerF()
                for _,marker in pairs(markers) do
                    if (marker > element.slider.min.value) and
                        (marker < element.slider.max.value) then

                        local s = get_slider_ele_pos_for(element, marker)

                        if (slider_lo.gap > 1) then -- draw triangles

                            local a = slider_lo.gap / 0.5 --0.866

                            --top
                            if (slider_lo.nibbles_top) then
                                static_ass:move_to(s - (a/2), slider_lo.border)
                                static_ass:line_to(s + (a/2), slider_lo.border)
                                static_ass:line_to(s, foV)
                            end

                            --bottom
                            if (slider_lo.nibbles_bottom) then
                                static_ass:move_to(s - (a/2),
                                    elem_geo.h - slider_lo.border)
                                static_ass:line_to(s,
                                    elem_geo.h - foV)
                                static_ass:line_to(s + (a/2),
                                    elem_geo.h - slider_lo.border)
                            end

                        else -- draw 2x1px nibbles

                            --top
                            if (slider_lo.nibbles_top) then
                                static_ass:rect_cw(s - 1, slider_lo.border,
                                    s + 1, slider_lo.border + slider_lo.gap);
                            end

                            --bottom
                            if (slider_lo.nibbles_bottom) then
                                static_ass:rect_cw(s - 1,
                                    elem_geo.h -slider_lo.border -slider_lo.gap,
                                    s + 1, elem_geo.h - slider_lo.border);
                            end
                        end
                    end
                end
            end
        end

        element.static_ass = static_ass


        -- if the element is supposed to be disabled,
        -- style it accordingly and kill the eventresponders
        if not (element.enabled) then
            element.layout.alpha[1] = 136
            element.eventresponder = nil
        end
    end
end


--
-- Element Rendering
--

function render_elements(master_ass)

    for n=1, #elements do
        local element = elements[n]

        local style_ass = assdraw.ass_new()
        style_ass:merge(element.style_ass)
        ass_append_alpha(style_ass, element.layout.alpha, 0)

        if element.eventresponder and (state.active_element == n) then

            -- run render event functions
            if not (element.eventresponder.render == nil) then
                element.eventresponder.render(element)
            end

            if mouse_hit(element) then
                -- mouse down styling
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

            -- draw pos marker
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
                        -- Punch holes for the seekRanges to be drawn later
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

            -- add tooltip
            if not (element.slider.tooltipF == nil) then

                if mouse_hit(element) then
                    local sliderpos = get_slider_value(element)
                    local tooltiplabel = element.slider.tooltipF(sliderpos)

                    local an = slider_lo.tooltip_an

                    local ty

                    if (an == 2) then
                        ty = element.hitbox.y1 - slider_lo.border
                    else
                        ty = element.hitbox.y1 + elem_geo.h/2
                    end

                    local tx = get_virt_mouse_pos()
                    if (slider_lo.adjust_tooltip) then
                        if (an == 2) then
                            if (sliderpos < (s_min + 3)) then
                                an = an - 1
                            elseif (sliderpos > (s_max - 3)) then
                                an = an + 1
                            end
                        elseif (sliderpos > (s_max-s_min)/2) then
                            an = an + 1
                            tx = tx - 5
                        else
                            an = an - 1
                            tx = tx + 10
                        end
                    end

                    -- tooltip label
                    elem_ass:new_event()
                    elem_ass:pos(tx, ty)
                    elem_ass:an(an)
                    elem_ass:append(slider_lo.tooltip_style)
                    ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                    elem_ass:append(tooltiplabel)

                    display_tn_osc(ty, sliderpos, elem_ass)
				else
					hide_thumbnail()
                end
            end

        elseif (element.type == "button") then

            local buttontext
            if type(element.content) == "function" then
                buttontext = element.content() -- function objects
            elseif not (element.content == nil) then
                buttontext = element.content -- text objects
            end

            local maxchars = element.layout.button.maxchars
            if not (maxchars == nil) and (#buttontext > maxchars) then
                local max_ratio = 1.25  -- up to 25% more chars while shrinking
                local limit = math.max(0, math.floor(maxchars * max_ratio) - 3)
                if (#buttontext > limit) then
                    while (#buttontext > limit) do
                        buttontext = buttontext:gsub(".[\128-\191]*$", "")
                    end
                    buttontext = buttontext .. "..."
                end
                local _, nchars2 = buttontext:gsub(".[\128-\191]*", "")
                local stretch = (maxchars/#buttontext)*100
                buttontext = string.format("{\\fscx%f}",
                    (maxchars/#buttontext)*100) .. buttontext
            end

            elem_ass:append(buttontext)
        end

        master_ass:merge(elem_ass)
    end
end

--
-- Message display
--

-- pos is 1 based
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
        local title = v.title
        local _, filename = utils.split_path(v.filename)
        if title == nil then
            title = filename
        end
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

    --print("text: "..text.."   duration: " .. duration)
    if duration == nil then
        duration = tonumber(mp.get_property("options/osd-duration")) / 1000
    elseif not type(duration) == "number" then
        print("duration: " .. duration)
    end

    -- cut the text short, otherwise the following functions
    -- may slow down massively on huge input
    text = string.sub(text, 0, 4000)

    -- replace actual linebreaks with ASS linebreaks
    text = string.gsub(text, "\n", "\\N")

    state.message_text = text
    state.message_timeout = mp.get_time() + duration
end

function render_message(ass)
    if not(state.message_timeout == nil) and not(state.message_text == nil)
        and state.message_timeout > mp.get_time() then
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
        state.message_timeout = nil
    end
end

--
-- Initialisation and Layout
--

function new_element(name, type)
    elements[name] = {}
    elements[name].type = type

    -- add default stuff
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
        -- new layout
        elements[name].layout = {}

        -- set layout defaults
        elements[name].layout.layer = 50
        elements[name].layout.alpha = {[1] = 0, [2] = 255, [3] = 255, [4] = 255}

        if (elements[name].type == "button") then
            elements[name].layout.button = {
                maxchars = nil,
            }
        elseif (elements[name].type == "slider") then
            -- slider defaults
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

-- Window Controls
function window_controls(alignment, topbar)
    local wc_geo = {
        x = 0,
        y = 30 + user_opts.barmargin,
        an = 1,
        w = osc_param.playresx,
        h = 30,
    }

    local controlbox_w = window_control_box_width
    local titlebox_w = wc_geo.w - controlbox_w

    -- Default alignment is "right"
    local controlbox_left = wc_geo.w - controlbox_w
    local titlebox_left = wc_geo.x + 5

    if alignment == "left" then
        controlbox_left = wc_geo.x
        titlebox_left = wc_geo.x + controlbox_w + 5
    elseif alignment == "right" then
        -- Already default
    else
        msg.error("Invalid setting \""..alignment.."\" for windowcontrols")
        -- Falls back to "right"
    end

    add_area("window-controls",
             get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an,
                               controlbox_w, wc_geo.h))

    local lo

    -- Background Bar
    new_element("wcbar", "box")
    lo = add_layout("wcbar")
    lo.geometry = wc_geo
    lo.layer = 10
    lo.style = osc_styles.wcBar
    lo.alpha[1] = user_opts.boxalpha

    local button_y = wc_geo.y - (wc_geo.h / 2)
    local first_geo =
        {x = controlbox_left + 5, y = button_y, an = 4, w = 25, h = 25}
    local second_geo =
        {x = controlbox_left + 30, y = button_y, an = 4, w = 25, h = 25}
    local third_geo =
        {x = controlbox_left + 55, y = button_y, an = 4, w = 25, h = 25}

    -- Close
    ne = new_element("close", "button")
    ne.content = "\226\152\146"
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("quit") end
    lo = add_layout("close")
    lo.geometry = alignment == "left" and first_geo or third_geo
    lo.style = osc_styles.wcButtons

    -- Minimize
    ne = new_element("minimize", "button")
    ne.content = "\226\154\128"
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("cycle", "window-minimized") end
    lo = add_layout("minimize")
    lo.geometry = alignment == "left" and second_geo or first_geo
    lo.style = osc_styles.wcButtons

    -- Maximize
    ne = new_element("maximize", "button")
    ne.content = "\226\150\163"
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("cycle", "window-maximized") end
    lo = add_layout("maximize")
    lo.geometry = alignment == "left" and third_geo or second_geo
    -- At least with default Ubuntu fonts, this symbol is differently aligned
    lo.geometry.y = lo.geometry.y - 2
    lo.style = osc_styles.wcButtons

    -- deadzone below window controls
    local sh_area_y0, sh_area_y1
    sh_area_y0 = user_opts.barmargin
    sh_area_y1 = (wc_geo.y + (wc_geo.h / 2)) +
                 get_align(1 - (2 * user_opts.deadzonesize),
                 osc_param.playresy - (wc_geo.y + (wc_geo.h / 2)), 0, 0)
    add_area("showhide_wc", wc_geo.x, sh_area_y0, wc_geo.w, sh_area_y1)

    if topbar then
        -- The title is already there as part of the top bar
        return
    end

    -- Window Title
    ne = new_element("wctitle", "button")
    ne.content = function ()
        local title = mp.command_native({"expand-text", user_opts.title})
        -- escape ASS, and strip newlines and trailing slashes
        title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
        return not (title == "") and title or "mpv"
    end
    lo = add_layout("wctitle")
    lo.geometry =
        { x = titlebox_left, y = wc_geo.y - 3, an = 1, w = titlebox_w, h = wc_geo.h }
    lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}",
        osc_styles.wcButtons,
        titlebox_left, wc_geo.y - wc_geo.h, titlebox_w, wc_geo.y + wc_geo.h)
end

--
-- Layouts
--

local layouts = {}

-- Classic box layout
layouts["box"] = function ()

    local osc_geo = {
        w = 550,    -- width
        h = 138,    -- height
        r = 10,     -- corner-radius
        p = 15,     -- padding
    }

    -- make sure the OSC actually fits into the video
    if (osc_param.playresx < (osc_geo.w + (2 * osc_geo.p))) then
        osc_param.playresy = (osc_geo.w+(2*osc_geo.p))/osc_param.display_aspect
        osc_param.playresx = osc_param.playresy * osc_param.display_aspect
    end

    -- position of the controller according to video aspect and valignment
    local posX = math.floor(get_align(user_opts.halign, osc_param.playresx,
        osc_geo.w, 0))
    local posY = math.floor(get_align(user_opts.valign, osc_param.playresy,
        osc_geo.h, 0))

    -- position offset for contents aligned at the borders of the box
    local pos_offsetX = (osc_geo.w - (2*osc_geo.p)) / 2
    local pos_offsetY = (osc_geo.h - (2*osc_geo.p)) / 2

    osc_param.areas = {} -- delete areas

    -- area for active mouse input
    add_area("input", get_hitbox_coords(posX, posY, 5, osc_geo.w, osc_geo.h))

    -- area for show/hide
    local sh_area_y0, sh_area_y1
    if user_opts.valign > 0 then
        -- deadzone above OSC
        sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
            posY - (osc_geo.h / 2), 0, 0)
        sh_area_y1 = osc_param.playresy
    else
        -- deadzone below OSC
        sh_area_y0 = 0
        sh_area_y1 = (posY + (osc_geo.h / 2)) +
            get_align(1 - (2*user_opts.deadzonesize),
            osc_param.playresy - (posY + (osc_geo.h / 2)), 0, 0)
    end
    add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

    -- fetch values
    local osc_w, osc_h, osc_r, osc_p =
        osc_geo.w, osc_geo.h, osc_geo.r, osc_geo.p

    local lo

    --
    -- Background box
    --

    new_element("bgbox", "box")
    lo = add_layout("bgbox")

    lo.geometry = {x = posX, y = posY, an = 5, w = osc_w, h = osc_h}
    lo.layer = 10
    lo.style = osc_styles.box
    lo.alpha[1] = user_opts.boxalpha
    lo.alpha[3] = user_opts.boxalpha
    lo.box.radius = osc_r

    --
    -- Title row
    --

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

    --
    -- Big buttons
    --

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

    --
    -- Seekbar
    --

    lo = add_layout("seekbar")
    lo.geometry =
        {x = posX, y = posY+pos_offsetY-22, an = 2, w = pos_offsetX*2, h = 15}
    lo.style = osc_styles.timecodes
    lo.slider.tooltip_style = osc_styles.vidtitle
    lo.slider.stype = user_opts["seekbarstyle"]
    lo.slider.rtype = user_opts["seekrangestyle"]

    --
    -- Timecodes + Cache
    --

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

-- slim box layout
layouts["slimbox"] = function ()

    local osc_geo = {
        w = 660,    -- width
        h = 70,     -- height
        r = 10,     -- corner-radius
    }

    -- make sure the OSC actually fits into the video
    if (osc_param.playresx < (osc_geo.w)) then
        osc_param.playresy = (osc_geo.w)/osc_param.display_aspect
        osc_param.playresx = osc_param.playresy * osc_param.display_aspect
    end

    -- position of the controller according to video aspect and valignment
    local posX = math.floor(get_align(user_opts.halign, osc_param.playresx,
        osc_geo.w, 0))
    local posY = math.floor(get_align(user_opts.valign, osc_param.playresy,
        osc_geo.h, 0))

    osc_param.areas = {} -- delete areas

    -- area for active mouse input
    add_area("input", get_hitbox_coords(posX, posY, 5, osc_geo.w, osc_geo.h))

    -- area for show/hide
    local sh_area_y0, sh_area_y1
    if user_opts.valign > 0 then
        -- deadzone above OSC
        sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
            posY - (osc_geo.h / 2), 0, 0)
        sh_area_y1 = osc_param.playresy
    else
        -- deadzone below OSC
        sh_area_y0 = 0
        sh_area_y1 = (posY + (osc_geo.h / 2)) +
            get_align(1 - (2*user_opts.deadzonesize),
            osc_param.playresy - (posY + (osc_geo.h / 2)), 0, 0)
    end
    add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

    local lo

    local tc_w, ele_h, inner_w = 100, 20, osc_geo.w - 100

    -- styles
    local styles = {
        box = "{\\rDefault\\blur0\\bord1\\1c&H000000\\3c&HFFFFFF}",
        timecodes = "{\\1c&HFFFFFF\\3c&H000000\\fs20\\bord2\\blur1}",
        tooltip = "{\\1c&HFFFFFF\\3c&H000000\\fs12\\bord1\\blur0.5}",
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

    --
    -- Timecodes
    --

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

    -- Cache

    lo = add_layout("cache")
    lo.geometry =
        {x = posX, y = posY + 1,
        an = 8, w = tc_w, h = ele_h}
    lo.style = styles.timecodes
    lo.alpha[3] = user_opts.boxalpha


end

function bar_layout(direction, windowcontrols)
    local osc_geo = {
        x = -2,
        y,
        an = (direction < 0) and 7 or 1,
        w,
        h = 56,
    }

    local padX = 9
    local padY = 3
    local buttonW = 27
    local tcW = (state.tc_ms) and 170 or 110
    local tsW = 90
    local minW = (buttonW + padX)*5 + (tcW + padX)*4 + (tsW + padX)*2

    -- Special topbar handling when window controls are present
    local padwc_l
    local padwc_r
    if direction < 0 or windowcontrols == "no" then
        padwc_l = 0
        padwc_r = 0
    elseif windowcontrols == "left" then
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

    osc_geo.y = direction * (54 + user_opts.barmargin)
    osc_geo.w = osc_param.playresx + 4
    if direction < 0 then
        osc_geo.y = osc_geo.y + osc_param.playresy
    end

    local line1 = osc_geo.y - direction * (9 + padY)
    local line2 = osc_geo.y - direction * (36 + padY)

    osc_param.areas = {}

    add_area("input", get_hitbox_coords(osc_geo.x, osc_geo.y, osc_geo.an,
                                        osc_geo.w, osc_geo.h))

    local sh_area_y0, sh_area_y1
    if direction > 0 then
        -- deadzone below OSC
        sh_area_y0 = user_opts.barmargin
        sh_area_y1 = (osc_geo.y + (osc_geo.h / 2)) +
                     get_align(1 - (2*user_opts.deadzonesize),
                     osc_param.playresy - (osc_geo.y + (osc_geo.h / 2)), 0, 0)
    else
        -- deadzone above OSC
        sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
                               osc_geo.y - (osc_geo.h / 2), 0, 0)
        sh_area_y1 = osc_param.playresy - user_opts.barmargin
    end
    add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

    local lo, geo

    -- Background bar
    new_element("bgbox", "box")
    lo = add_layout("bgbox")

    lo.geometry = osc_geo
    lo.layer = 10
    lo.style = osc_styles.box
    lo.alpha[1] = user_opts.boxalpha


    -- Playlist prev/next
    geo = { x = osc_geo.x + padX, y = line1,
            an = 4, w = 18, h = 18 - padY }
    lo = add_layout("pl_prev")
    lo.geometry = geo
    lo.style = osc_styles.topButtonsBar

    geo = { x = geo.x + geo.w + padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
    lo = add_layout("pl_next")
    lo.geometry = geo
    lo.style = osc_styles.topButtonsBar

    local t_l = geo.x + geo.w + padX

    -- Cache
    geo = { x = osc_geo.x + osc_geo.w - padX, y = geo.y,
            an = 6, w = 150, h = geo.h }
    lo = add_layout("cache")
    lo.geometry = geo
    lo.style = osc_styles.vidtitleBar

    local t_r = geo.x - geo.w - padX*2

    -- Title
    geo = { x = t_l, y = geo.y, an = 4,
            w = t_r - t_l, h = geo.h }
    lo = add_layout("title")
    lo.geometry = geo
    lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}",
        osc_styles.vidtitleBar,
        geo.x, geo.y-geo.h, geo.w, geo.y+geo.h)


    -- Playback control buttons
    geo = { x = osc_geo.x + padX + padwc_l, y = line2, an = 4,
            w = buttonW, h = 36 - padY*2}
    lo = add_layout("playpause")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    geo = { x = geo.x + geo.w + padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
    lo = add_layout("ch_prev")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    geo = { x = geo.x + geo.w + padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
    lo = add_layout("ch_next")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    -- Left timecode
    geo = { x = geo.x + geo.w + padX + tcW, y = geo.y, an = 6,
            w = tcW, h = geo.h }
    lo = add_layout("tc_left")
    lo.geometry = geo
    lo.style = osc_styles.timecodesBar

    local sb_l = geo.x + padX

    -- Fullscreen button
    geo = { x = osc_geo.x + osc_geo.w - buttonW - padX - padwc_r, y = geo.y, an = 4,
            w = buttonW, h = geo.h }
    lo = add_layout("tog_fs")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    -- Volume
    geo = { x = geo.x - geo.w - padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
    lo = add_layout("volume")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    -- Track selection buttons
    geo = { x = geo.x - tsW - padX, y = geo.y, an = geo.an, w = tsW, h = geo.h }
    lo = add_layout("cy_sub")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar

    geo = { x = geo.x - geo.w - padX, y = geo.y, an = geo.an, w = geo.w, h = geo.h }
    lo = add_layout("cy_audio")
    lo.geometry = geo
    lo.style = osc_styles.smallButtonsBar


    -- Right timecode
    geo = { x = geo.x - padX - tcW - 10, y = geo.y, an = geo.an,
            w = tcW, h = geo.h }
    lo = add_layout("tc_right")
    lo.geometry = geo
    lo.style = osc_styles.timecodesBar

    local sb_r = geo.x - padX


    -- Seekbar
    geo = { x = sb_l, y = geo.y, an = geo.an,
            w = math.max(0, sb_r - sb_l), h = geo.h }
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
    lo.style = osc_styles.timecodesBar
    lo.slider.border = 0
    lo.slider.gap = 2
    lo.slider.tooltip_style = osc_styles.timePosBar
    lo.slider.tooltip_an = 5
    lo.slider.stype = user_opts["seekbarstyle"]
    lo.slider.rtype = user_opts["seekrangestyle"]

    if direction < 0 then
        osc_param.video_margins.b = osc_geo.h / osc_param.playresy
    else
        osc_param.video_margins.t = osc_geo.h / osc_param.playresy
    end
end

layouts["bottombar"] = function()
    bar_layout(-1, false)
end

layouts["topbar"] = function()
    bar_layout(1, user_opts.windowcontrols)
end

-- Validate string type user options
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
end


-- OSC INIT
function osc_init()
    msg.debug("osc_init")

    -- set canvas resolution according to display aspect and scaling setting
    local baseResY = 720
    local display_w, display_h, display_aspect = mp.get_osd_size()
    local scale = 1

    if (mp.get_property("video") == "no") then -- dummy/forced window
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

    -- stop seeking with the slider to prevent skipping files
    state.active_element = nil




    elements = {}

    -- some often needed stuff
    local pl_count = mp.get_property_number("playlist-count", 0)
    local have_pl = (pl_count > 1)
    local pl_pos = mp.get_property_number("playlist-pos", 0) + 1
    local have_ch = (mp.get_property_number("chapters", 0) > 0)
    local loop = mp.get_property("loop-playlist", "no")

    local ne

    -- title
    ne = new_element("title", "button")

    ne.content = function ()
        local title = mp.command_native({"expand-text", user_opts.title})
        -- escape ASS, and strip newlines and trailing slashes
        title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
        return not (title == "") and title or "mpv"
    end

    ne.eventresponder["mbtn_left_up"] = function ()
        local title = mp.get_property_osd("media-title")
        if (have_pl) then
            title = string.format("[%d/%d] %s", countone(pl_pos - 1),
                                  pl_count, title)
        end
        show_message(title)
    end

    ne.eventresponder["mbtn_right_up"] =
        function () show_message(mp.get_property_osd("filename")) end

    -- playlist buttons

    -- prev
    ne = new_element("pl_prev", "button")

    ne.content = "\238\132\144"
    ne.enabled = (pl_pos > 1) or (loop ~= "no")
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("playlist-prev", "weak")
            show_message(get_playlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_playlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_playlist(), 3) end

    --next
    ne = new_element("pl_next", "button")

    ne.content = "\238\132\129"
    ne.enabled = (have_pl and (pl_pos < pl_count)) or (loop ~= "no")
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("playlist-next", "weak")
            show_message(get_playlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_playlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_playlist(), 3) end


    -- big buttons

    --playpause
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

    --skipback
    ne = new_element("skipback", "button")

    ne.softrepeat = true
    ne.content = "\238\128\132"
    ne.eventresponder["mbtn_left_down"] =
        function () mp.commandv("seek", -5, "relative", "keyframes") end
    ne.eventresponder["shift+mbtn_left_down"] =
        function () mp.commandv("frame-back-step") end
    ne.eventresponder["mbtn_right_down"] =
        function () mp.commandv("seek", -30, "relative", "keyframes") end

    --skipfrwd
    ne = new_element("skipfrwd", "button")

    ne.softrepeat = true
    ne.content = "\238\128\133"
    ne.eventresponder["mbtn_left_down"] =
        function () mp.commandv("seek", 10, "relative", "keyframes") end
    ne.eventresponder["shift+mbtn_left_down"] =
        function () mp.commandv("frame-step") end
    ne.eventresponder["mbtn_right_down"] =
        function () mp.commandv("seek", 60, "relative", "keyframes") end

    --ch_prev
    ne = new_element("ch_prev", "button")

    ne.enabled = have_ch
    ne.content = "\238\132\132"
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("add", "chapter", -1)
            show_message(get_chapterlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_chapterlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_chapterlist(), 3) end

    --ch_next
    ne = new_element("ch_next", "button")

    ne.enabled = have_ch
    ne.content = "\238\132\133"
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("add", "chapter", 1)
            show_message(get_chapterlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_chapterlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_chapterlist(), 3) end

    --
    update_tracklist()

    --cy_audio
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

    --cy_sub
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

    --tog_fs
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

    --seekbar
    ne = new_element("seekbar", "slider")

    ne.enabled = not (mp.get_property("percent-pos") == nil)
    ne.slider.markerF = function ()
        local duration = mp.get_property_number("duration", nil)
        if not (duration == nil) then
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
            possec = duration * (pos / 100)
            return mp.format_time(possec)
        else
            return ""
        end
    end
    ne.slider.seekRangesF = function()
        if user_opts.seekrangestyle == "none" then
            return nil
        end
        local cache_state = mp.get_property_native("demuxer-cache-state", nil)
        if not cache_state then
            return nil
        end
        local duration = mp.get_property_number("duration", nil)
        if (duration == nil) or duration <= 0 then
            return nil
        end
        local ranges = cache_state["seekable-ranges"]
        for _, range in pairs(ranges) do
            range["start"] = 100 * range["start"] / duration
            range["end"] = 100 * range["end"] / duration
        end
        if #ranges == 0 then
            return nil
        end
        return ranges
    end
    ne.eventresponder["mouse_move"] = --keyframe seeking when mouse is dragged
        function (element)
            -- mouse move events may pile up during seeking and may still get
            -- sent when the user is done seeking, so we need to throw away
            -- identical seeks
            local seekto = get_slider_value(element)
            if (element.state.lastseek == nil) or
                (not (element.state.lastseek == seekto)) then
                    mp.commandv("seek", seekto, "absolute-percent",
                        user_opts.seekbarkeyframes and "keyframes" or "exact")
                    element.state.lastseek = seekto
            end

        end
    ne.eventresponder["mbtn_left_down"] = --exact seeks on single clicks
        function (element) mp.commandv("seek", get_slider_value(element),
            "absolute-percent", "exact") end
    ne.eventresponder["reset"] =
        function (element) element.state.lastseek = nil end
    ne.eventresponder["mbtn_right_down"] = function (element) mp.commandv('script-message', 'Thumbnailer-toggle-osc') end
    ne.eventresponder["mbtn_right_dbl_press"] = function (element) mp.commandv('script-message', 'Thumbnailer-double') end

    -- tc_left (current pos)
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

    -- tc_right (total/remaining time)
    ne = new_element("tc_right", "button")

    ne.visible = (mp.get_property_number("duration", 0) > 0)
    ne.content = function ()
        if (state.rightTC_trem) then
            if state.tc_ms then
                return ("-"..mp.get_property_osd("playtime-remaining/full"))
            else
                return ("-"..mp.get_property_osd("playtime-remaining"))
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

    -- cache
    ne = new_element("cache", "button")

    ne.content = function ()
        local cache_state = mp.get_property_native("demuxer-cache-state", {})
        if not (cache_state["seekable-ranges"] and
            #cache_state["seekable-ranges"] > 0) then
            -- probably not a network stream
            return ""
        end
        local dmx_cache = mp.get_property_number("demuxer-cache-duration")
        if dmx_cache and (dmx_cache > state.dmx_cache * 1.1 or
                dmx_cache < state.dmx_cache * 0.9) then
            state.dmx_cache = dmx_cache
        else
            dmx_cache = state.dmx_cache
        end
        local min = math.floor(dmx_cache / 60)
        local sec = dmx_cache % 60
        return "Cache: " .. (min > 0 and
            string.format("%sm%02.0fs", min, sec) or
            string.format("%3.0fs", dmx_cache))
    end

    -- volume
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
        function () mp.commandv("cycle", "mute") end

    ne.eventresponder["wheel_up_press"] =
        function () mp.commandv("osd-auto", "add", "volume", 5) end
    ne.eventresponder["wheel_down_press"] =
        function () mp.commandv("osd-auto", "add", "volume", -5) end


    -- load layout
    layouts[user_opts.layout]()

    -- load window controls
    if user_opts.windowcontrols ~= "no" then
        window_controls(user_opts.windowcontrols,
                        user_opts.layout == "topbar")
    end

    --do something with the elements
    prepare_elements()

    if user_opts.boxvideo then
        -- check whether any margin option has a non-default value
        local margins_used = false

        for _, opt in ipairs(margins_opts) do
            if mp.get_property_number(opt[2], 0.0) ~= 0.0 then
                margins_used = true
            end
        end

        if not margins_used then
            local margins = osc_param.video_margins
            for _, opt in ipairs(margins_opts) do
                local v = margins[opt[1]]
                if v ~= 0 then
                    mp.set_property_number(opt[2], v)
                    state.using_video_margins = true
                end
            end
        end
    else
        reset_margins()
    end

end

function reset_margins()
    if state.using_video_margins then
        for _, opt in ipairs(margins_opts) do
            mp.set_property_number(opt[2], 0.0)
        end
        state.using_video_margins = false
    end
end

--
-- Other important stuff
--


function show_osc()
    -- show when disabled can happen (e.g. mouse_move) due to async/delayed unbinding
    if not state.enabled then return end

    msg.trace("show_osc")
    --remember last time of invocation (mouse move)
    state.showtime = mp.get_time()

    osc_visible(true)

    if (user_opts.fadeduration > 0) then
        state.anitype = nil
    end
end

function hide_osc()
    msg.trace("hide_osc")
    if not state.enabled then
        -- typically hide happens at render() from tick(), but now tick() is
        -- no-op and won't render again to remove the osc, so do that manually.
        state.osc_visible = false
        timer_stop()
        render_wipe()
    elseif (user_opts.fadeduration > 0) then
        if not(state.osc_visible == false) then
            state.anitype = "out"
            control_timer()
        end
    else
        osc_visible(false)
    end
end

function osc_visible(visible)
    state.osc_visible = visible
    control_timer()
end

function pause_state(name, enabled)
    state.paused = enabled
    control_timer()
end

function cache_state(name, idle)
    state.cache_idle = idle
    control_timer()
end

function control_timer()
    if (state.paused) and (state.osc_visible) and
        ( not(state.cache_idle) or not (state.anitype == nil) ) then

        timer_start()
    else
        timer_stop()
    end
end

function timer_start()
    if not (state.timer_active) then
        msg.trace("timer start")

        if (state.timer == nil) then
            -- create new timer
            state.timer = mp.add_periodic_timer(0.03, tick)
        else
            -- resume existing one
            state.timer:resume()
        end

        state.timer_active = true
    end
end

function timer_stop()
    if (state.timer_active) then
        msg.trace("timer stop")

        if not (state.timer == nil) then
            -- kill timer
            state.timer:kill()
        end

        state.timer_active = false
    end
end



function mouse_leave()
    if user_opts.hidetimeout >= 0 then
        hide_osc()
    end
    -- reset mouse position
    state.last_mouseX, state.last_mouseY = nil, nil
end

function request_init()
    state.initREQ = true
end

function render_wipe()
    msg.trace("render_wipe()")
    mp.set_osd_ass(0, 0, "{}")
end

function render()
    msg.trace("rendering")
    local current_screen_sizeX, current_screen_sizeY, aspect = mp.get_osd_size()
    local mouseX, mouseY = get_virt_mouse_pos()
    local now = mp.get_time()

    -- check if display changed, if so request reinit
    if not (state.mp_screen_sizeX == current_screen_sizeX
        and state.mp_screen_sizeY == current_screen_sizeY) then

        request_init()

        state.mp_screen_sizeX = current_screen_sizeX
        state.mp_screen_sizeY = current_screen_sizeY
    end

    -- init management
    if state.initREQ then
        osc_init()
        state.initREQ = false

        -- store initial mouse position
        if (state.last_mouseX == nil or state.last_mouseY == nil)
            and not (mouseX == nil or mouseY == nil) then

            state.last_mouseX, state.last_mouseY = mouseX, mouseY
        end
    end


    -- fade animation
    if not(state.anitype == nil) then

        if (state.anistart == nil) then
            state.anistart = now
        end

        if (now < state.anistart + (user_opts.fadeduration/1000)) then

            if (state.anitype == "in") then --fade in
                osc_visible(true)
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    255, 0, now)
            elseif (state.anitype == "out") then --fade out
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    0, 255, now)
            end

        else
            if (state.anitype == "out") then
                osc_visible(false)
            end
            state.anistart = nil
            state.animation = nil
            state.anitype =  nil
        end
    else
        state.anistart = nil
        state.animation = nil
        state.anitype =  nil
    end

    --mouse show/hide area
    for k,cords in pairs(osc_param.areas["showhide"]) do
        set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide")
    end
    for k,cords in pairs(osc_param.areas["showhide_wc"]) do
        set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide_wc")
    end
    do_enable_keybindings()

    --mouse input area
    local mouse_over_osc = false

    for _,cords in ipairs(osc_param.areas["input"]) do
        if state.osc_visible then -- activate only when OSC is actually visible
            set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "input")
        end
        if state.osc_visible ~= state.input_enabled then
            if state.osc_visible then
                mp.enable_key_bindings("input")
            else
                mp.disable_key_bindings("input")
            end
            state.input_enabled = state.osc_visible
        end

        if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
            mouse_over_osc = true
        end
    end

    if user_opts.windowcontrols ~= "no" then
        for _,cords in ipairs(osc_param.areas["window-controls"]) do
            if state.osc_visible then -- activate only when OSC is actually visible
                set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "window-controls")
                mp.enable_key_bindings("window-controls")
            else
                mp.disable_key_bindings("window-controls")
            end

            if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
                mouse_over_osc = true
            end
        end
    end

    -- autohide
    if not (state.showtime == nil) and (user_opts.hidetimeout >= 0)
        and (state.showtime + (user_opts.hidetimeout/1000) < now)
        and (state.active_element == nil) and not (mouse_over_osc) then

        hide_osc()
    end


    -- actual rendering
    local ass = assdraw.ass_new()

    -- Messages
    render_message(ass)

    -- actual OSC
    if state.osc_visible then
        render_elements(ass)
    else
    	hide_thumbnail()
    end

    -- submit
    mp.set_osd_ass(osc_param.playresy * osc_param.display_aspect,
                   osc_param.playresy, ass.text)




end

--
-- Eventhandling
--

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
                -- fire the down or press event if the element has one
                if element_has_action(elements[n], action) then
                    elements[n].eventresponder[action](elements[n])
                end

            end
        end

    elseif what == "up" then

        if elements[state.active_element] then
            local n = state.active_element

            if n == 0 then
                --click on background (does not work)
            elseif element_has_action(elements[n], action) and
                mouse_hit(elements[n]) then

                elements[n].eventresponder[action](elements[n])
            end

            --reset active element
            if element_has_action(elements[n], "reset") then
                elements[n].eventresponder["reset"](elements[n])
            end

        end
        state.active_element = nil
        state.mouse_down_counter = 0

    elseif source == "mouse_move" then

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
        tick()
    end
end

-- called by mpv on every frame
function tick()
    if (not state.enabled) then return end

    if (state.idle) then

        -- render idle message
        msg.trace("idle message")
        local icon_x, icon_y = 320 - 26, 140

        local ass = assdraw.ass_new()
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&H430142&\\1a&H00&\\bord0\\shad0\\p6}m 1605 828 b 1605 1175 1324 1456 977 1456 631 1456 349 1175 349 828 349 482 631 200 977 200 1324 200 1605 482 1605 828{\\p0}")
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&HDDDBDD&\\1a&H00&\\bord0\\shad0\\p6}m 1296 910 b 1296 1131 1117 1310 897 1310 676 1310 497 1131 497 910 497 689 676 511 897 511 1117 511 1296 689 1296 910{\\p0}")
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&H691F69&\\1a&H00&\\bord0\\shad0\\p6}m 762 1113 l 762 708 b 881 776 1000 843 1119 911 1000 978 881 1046 762 1113{\\p0}")
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&H682167&\\1a&H00&\\bord0\\shad0\\p6}m 925 42 b 463 42 87 418 87 880 87 1343 463 1718 925 1718 1388 1718 1763 1343 1763 880 1763 418 1388 42 925 42 m 925 42 m 977 200 b 1324 200 1605 482 1605 828 1605 1175 1324 1456 977 1456 631 1456 349 1175 349 828 349 482 631 200 977 200{\\p0}")
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&H753074&\\1a&H00&\\bord0\\shad0\\p6}m 977 198 b 630 198 348 480 348 828 348 1176 630 1458 977 1458 1325 1458 1607 1176 1607 828 1607 480 1325 198 977 198 m 977 198 m 977 202 b 1323 202 1604 483 1604 828 1604 1174 1323 1454 977 1454 632 1454 351 1174 351 828 351 483 632 202 977 202{\\p0}")
        ass:new_event()
        ass:pos(icon_x, icon_y)
        ass:append("{\\rDefault\\an7\\c&HE5E5E5&\\1a&H00&\\bord0\\shad0\\p6}m 895 10 b 401 10 0 410 0 905 0 1399 401 1800 895 1800 1390 1800 1790 1399 1790 905 1790 410 1390 10 895 10 m 895 10 m 925 42 b 1388 42 1763 418 1763 880 1763 1343 1388 1718 925 1718 463 1718 87 1343 87 880 87 418 463 42 925 42{\\p0}")
        ass:new_event()
        ass:pos(320, icon_y+65)
        ass:an(8)
        ass:append("Drop files or URLs to play here.")
        mp.set_osd_ass(640, 360, ass.text)

        if state.showhide_enabled then
            mp.disable_key_bindings("showhide")
            mp.disable_key_bindings("showhide_wc")
            state.showhide_enabled = false
        end


    elseif (state.fullscreen and user_opts.showfullscreen)
        or (not state.fullscreen and user_opts.showwindowed) then

        -- render the OSC
        render()
    else
        -- Flush OSD
        mp.set_osd_ass(osc_param.playresy, osc_param.playresy, "")
    end
end

function do_enable_keybindings()
    if state.enabled then
        if not state.showhide_enabled then
            mp.enable_key_bindings("showhide", "allow-vo-dragging+allow-hide-cursor")
            mp.enable_key_bindings("showhide_wc", "allow-vo-dragging+allow-hide-cursor")
        end
        state.showhide_enabled = true
    end
end

function enable_osc(enable)
    state.enabled = enable
    if enable then
        do_enable_keybindings()
    else
        hide_osc() -- acts immediately when state.enabled == false
        if state.showhide_enabled then
            mp.disable_key_bindings("showhide")
            mp.disable_key_bindings("showhide_wc")
        end
        state.showhide_enabled = false
    end
end

validate_user_opts()

mp.register_event("shutdown", reset_margins)
mp.register_event("start-file", request_init)
mp.register_event("tracks-changed", request_init)
mp.observe_property("playlist", nil, request_init)

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
        request_init()
    end
)
mp.observe_property("idle-active", "bool",
    function(name, val)
        state.idle = val
        tick()
    end
)
mp.observe_property("pause", "bool", pause_state)
mp.observe_property("cache-idle", "bool", cache_state)
mp.observe_property("vo-configured", "bool", function(name, val)
    if val then
        mp.register_event("tick", tick)
    else
        mp.unregister_event(tick)
    end
end)

-- mouse show/hide bindings
mp.set_key_bindings({
    {"mouse_move",              function(e) process_event("mouse_move", nil) end},
    {"mouse_leave",             mouse_leave},
}, "showhide", "force")
mp.set_key_bindings({
    {"mouse_move",              function(e) process_event("mouse_move", nil) end},
    {"mouse_leave",             mouse_leave},
}, "showhide_wc", "force")
do_enable_keybindings()

--mouse input bindings
mp.set_key_bindings({
    {"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
                            function(e) process_event("mbtn_left", "down")  end},
    {"shift+mbtn_left",     function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"mbtn_right",          function(e) process_event("mbtn_right", "up") end,
                            function(e) process_event("mbtn_right", "down")  end},
    -- alias to shift_mbtn_left for single-handed mouse use
    {"mbtn_mid",            function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"wheel_up",            function(e) process_event("wheel_up", "press") end},
    {"wheel_down",          function(e) process_event("wheel_down", "press") end},
    {"mbtn_left_dbl",       "ignore"},
    {"shift+mbtn_left_dbl", "ignore"},
    {"mbtn_right_dbl",      function(e) process_event("mbtn_right_dbl", "press") end},
}, "input", "force")
mp.enable_key_bindings("input")

mp.set_key_bindings({
    {"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
                            function(e) process_event("mbtn_left", "down")  end},
}, "window-controls", "force")
mp.enable_key_bindings("window-controls")

user_opts.hidetimeout_orig = user_opts.hidetimeout

function always_on(val)
    if val then
        user_opts.hidetimeout = -1 -- disable autohide
        if state.enabled then show_osc() end
    else
        user_opts.hidetimeout = user_opts.hidetimeout_orig
        if state.enabled then hide_osc() end
    end
end

-- mode can be auto/always/never/cycle
-- the modes only affect internal variables and not stored on its own.
function visibility_mode(mode, no_osd)
    if mode == "cycle" then
        if not state.enabled then
            mode = "auto"
        elseif user_opts.hidetimeout >= 0 then
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

    if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
        mp.osd_message("OSC visibility: " .. mode)
    end
end

visibility_mode(user_opts.visibility, true)
mp.register_script_message("osc-visibility", visibility_mode)
mp.add_key_binding(nil, "visibility", function() visibility_mode("cycle") end)

set_virt_mouse_area(0, 0, 0, 0, "input")
