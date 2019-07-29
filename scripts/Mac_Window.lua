-- deus0ww - 2019-07-29

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'



local user_opts = {
	screen_width          = 2560,
	screen_height         = 1440,
	
	default_resize_type   = 2,     -- 0=Off, 1=Absolute, 2=Percent of Screen, 3=Percent of Video
	default_resize_width  = 50, 
	default_resize_height = 50,

	default_align         = 3,     -- Align to screen edges; 0=Off, 1-9=Numpad Direction (Priority over 'Move')

	default_move_type     = 2,     -- 0=Off, 1=Absolute, 2=Percent of Screen
	default_move_x        = 50,
	default_move_y        = 50,
	
	delay                 = 0.250  -- Time (sec) to wait between resizing and moving the window
}
opt.read_options(user_opts, mp.get_script_name())

local path_base = (debug.getinfo(1).short_src):gsub('.lua', '')
local path_resize_script = path_base .. '_Resize.scpt'
local path_move_script   = path_base .. '_Move.scpt'
msg.debug('Resize Script:', path_resize_script)
msg.debug('Move Script:',   path_move_script)

local video_width  = 0
local video_height = 0
local osd_width    = 0
local osd_height   = 0

local function sanitize(input, min, max, default, no_rounding)
	if type(input) ~= 'number' then input = (tonumber(input) or default or 0) end
	if min then input = math.max(input, min) end
	if max then input = math.min(input, max) end
	return no_rounding and input or (input < 0 and math.ceil(input - 0.5) or math.floor(input + 0.5))
end



-------------------
-- Resize Window --
-------------------
local function do_resize(width, height)
	msg.debug('Resizing window to', width, height)
	mp.command_native({name='subprocess', args={'osascript', path_resize_script, 'mpv', tostring(width), tostring(height)}})
end

-- Resize - Absolute Size
local function resize(width, height)
	msg.debug('Trying to resize window to', width, height)
	if video_width <= 0 or video_height <= 0 then return end
	width  = sanitize(width,  0, user_opts.screen_width,  0)
	height = sanitize(height, 0, user_opts.screen_height, 0)
	local aspect = video_width / video_height
	if width  <= 0 then width  = math.floor(height * aspect + 0.5) end
	if height <= 0 then height = math.floor(width  / aspect + 0.5) end
	do_resize(width, height)
end
mp.register_script_message('Resize', resize)

-- Resize - Percent of Screen Size
local function resize_percent_screen(percent)
	msg.debug('Trying to resize window to', percent, '% of screen')
	percent = sanitize(percent, 0, 100, 100, true) / 100
	resize(user_opts.screen_width * percent, user_opts.screen_height * percent)
end
mp.register_script_message('Resize%Screen', resize_percent_screen)

-- Resize - Percent of Video Size
local function resize_percent(percent)
	msg.debug('Trying to resize window to', percent, '%')
	percent = sanitize(percent, 0, 100, 100, true) / 100
	resize(video_width * percent, video_height * percent)
end
mp.register_script_message('Resize%', resize_percent)



-----------------
-- Move Window --
-----------------
local function do_move(x, y)
	msg.debug('Moving window to', x, y)
	mp.command_native({name='subprocess', args={'osascript', path_move_script, 'mpv', tostring(x), tostring(y)}})
end

-- Move - Coordinate
local function move_window(x, y)
	msg.debug('Trying to move window to', x, y)
	if x == nil and y == nil then return end
	x = sanitize(x, 0, user_opts.screen_width,  0)
	y = sanitize(y, 0, user_opts.screen_height, 0)
	do_move(x, y)
end
mp.register_script_message('Move', move_window)

-- Resize - Percent of Screen
local function move_percent_screen(percent_x, percent_y)
	msg.debug('Trying to move window to', percent_x, percent_y, '% of screen')
	percent_x = sanitize(percent_x, -100, 100, 50, true) / 100
	percent_y = sanitize(percent_y, -100, 100, 50, true) / 100
	local x = percent_x > 0 and (percent_x * user_opts.screen_width)  or ((1 + percent_x) * user_opts.screen_width)
	local y = percent_y > 0 and (percent_x * user_opts.screen_height) or ((1 + percent_y) * user_opts.screen_height)
	move_window(x, y)
end
mp.register_script_message('Move%Screen', move_percent_screen)

-- Move - Align
local function align(a)
	msg.debug('Trying to align window to', a)
	a = sanitize(a, 1, 9, 5)
	local x, y = 0, 0
	if a == 1 or a == 4 or a == 7 then x = 0 end
	if a == 2 or a == 5 or a == 8 then x = (user_opts.screen_width - osd_width) / 2 end
	if a == 3 or a == 6 or a == 9 then x = (user_opts.screen_width - osd_width) end
	if a == 7 or a == 8 or a == 9 then y = 0 end
	if a == 4 or a == 5 or a == 6 then y = (user_opts.screen_height - osd_height) / 2 end
	if a == 1 or a == 2 or a == 3 then y = (user_opts.screen_height - osd_height) end
	move_window(x, y)
end
mp.register_script_message('Align', align)



-------------
-- On Load --
-------------
local default_move = { move_window, move_percent_screen }
local function set_default_move()
	osd_width, osd_height = mp.get_osd_size()
	if osd_width == 0 or osd_height == 0 then
		msg.debug('Waiting for osd size')
		mp.add_timeout(0.050, set_default_move)
	else
		msg.debug('Default Moving')
		local o = user_opts
		if o.default_align ~= 0 then
			align(o.default_align)
		elseif o.default_move_type ~= 0 then
			default_move[sanitize(o.default_move_type, 1, 2, 1)](o.default_move_x, o.default_move_y)
		end
	end
end

local default_resize = { resize, resize_percent_screen, resize_percent }
local function set_default_resize()
	local video_params = mp.get_property_native('video-params', {})
	video_width  = video_params.dw or 0
	video_height = video_params.dh or 0
	if video_width == 0 or not video_height == 0 then
		msg.debug('Waiting for video-params')
		mp.add_timeout(0.050, set_default_resize)
	else
		msg.debug('Default Resizing')
		local o = user_opts
		if o.default_resize_type ~= 0 then
			default_resize[sanitize(o.default_resize_type, 1, 3, 1)](o.default_resize_width, o.default_resize_height)
			mp.add_timeout(o.delay, set_default_move)
		else
			set_default_move()
		end
	end
end

mp.register_event('file-loaded', set_default_resize)
