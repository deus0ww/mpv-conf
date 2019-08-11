-- deus0ww - 2019-08-12

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



------------------
-- User Options --
------------------
local opts = {
	screen_width          = 2560,
	screen_height         = 1440,
	scale_factor          = 1,	   -- 1=Non-Retina, 2=Retina

	default_resize_type   = 2,     -- 0=Off, 1=Absolute, 2=Percent of Screen, 3=Percent of Video
	default_resize_width  = 50, 
	default_resize_height = 50,

	default_align         = 3,     -- Align to screen edges; 0=Off, 1-9=Numpad Direction (Priority over 'Move')

	default_move_type     = 2,     -- 0=Off, 1=Absolute, 2=Percent of Screen
	default_move_x        = 50,
	default_move_y        = 50,
}
opt.read_options(opts, mp.get_script_name())



------------
-- Global --
------------
local path_base = (debug.getinfo(1).short_src):gsub('.lua', '')
local path_resize_script = path_base .. '_Resize.scpt'
local path_move_script   = path_base .. '_Move.scpt'
local pid = utils.getpid()
msg.debug('Resize Script:', path_resize_script)
msg.debug('Move Script:', path_move_script)
msg.debug('MPV PID:', pid)

local function sanitize(input, min, max, default, no_rounding)
	if type(input) ~= 'number' then input = (tonumber(input) or default or 0) end
	if min then input = math.max(input, min) end
	if max then input = math.min(input, max) end
	return no_rounding and input or (input < 0 and math.ceil(input - 0.5) or math.floor(input + 0.5))
end

local resized_width  = 0
local resized_height = 0

local fullscreen   = false
local osd_width    = 0
local osd_height   = 0
local video_width  = 0
local video_height = 0
local rotate_initial = 0
local rotate_current = 0

mp.observe_property('fullscreen', 'native', function(_, fs)     fullscreen = fs or false end)
mp.observe_property('osd-width',  'native', function(_, width)  osd_width  = width  and (width  / opts.scale_factor) or 0 end)
mp.observe_property('osd-height', 'native', function(_, height) osd_height = height and (height / opts.scale_factor) or 0 end)
mp.observe_property('video-params/rotate', 'native', function(_, rotate) rotate_current = rotate or 0 end)
mp.observe_property('video-params/dw',     'native', function(_, width)  video_width    = width  or 0 end)
mp.observe_property('video-params/dh',     'native', function(_, height) video_height   = height or 0 end)

local function is_rotated()
	return not ((((rotate_current - rotate_initial) % 180) ~= 0) == ((rotate_initial % 180) ~= 0))
end

local function is_same_size(width_1, height_1, width_2, height_2)
	return ((math.abs(width_1 - width_2) + math.abs(height_1 - height_2)) < 2)
end



-------------------
-- Resize Window --
-------------------
local function do_resize(width, height)
	if fullscreen then return end
	resized_width, resized_height = width, height
	msg.debug('Resizing window to', width, height)
	mp.command_native({name='subprocess', args={'osascript', path_resize_script, tostring(pid), tostring(width), tostring(height)}})
end

-- Resize - Absolute Size
local function resize(width, height)
	msg.debug('Trying to resize window to', width, height)
	if video_width <= 0 or video_height <= 0 then return end
	width  = sanitize(width,  0, opts.screen_width,  0)
	height = sanitize(height, 0, opts.screen_height, 0)
	local aspect = is_rotated() and video_height / video_width or video_width / video_height
	if width  <= 0 then width  = math.floor(height * aspect + 0.5) end
	if height <= 0 then height = math.floor(width  / aspect + 0.5) end
	--if is_rotated() then width, height = height, width end
	do_resize(width, height)
end
mp.register_script_message('Resize', resize)

-- Resize - Percent of Screen Size
local function resize_percent_screen(percent)
	msg.debug('Trying to resize window to', percent, '% of screen')
	percent = sanitize(percent, 0, 100, 100, true) / 100
	local aspect = is_rotated() and video_height / video_width or video_width / video_height
	if (opts.screen_width / opts.screen_height) > aspect then
		resize(0, opts.screen_height * percent)
	else
		resize(opts.screen_width * percent, 0)
	end
end
mp.register_script_message('Resize%Screen', resize_percent_screen)

-- Resize - Percent of Video Size
local function resize_percent(percent)
	msg.debug('Trying to resize window to', percent, '%')
	percent = sanitize(percent, 0, 100, 100, true) / 100
	local width, height = video_width * percent, video_height * percent
	if is_rotated() then width, height = height, width end
	resize(width, height)
end
mp.register_script_message('Resize%', resize_percent)



-----------------
-- Move Window --
-----------------
local function do_move(x, y)
	if fullscreen then return end
	msg.debug('Moving window to', x, y)
	mp.command_native({name='subprocess', args={'osascript', path_move_script, tostring(pid), tostring(x), tostring(y)}})
end

-- Move - Coordinate
local function move_window(x, y)
	msg.debug('Trying to move window to', x, y)
	if x == nil and y == nil then return end
	x = sanitize(x, 0, opts.screen_width,  0)
	y = sanitize(y, 0, opts.screen_height, 0)
	do_move(x, y)
end
mp.register_script_message('Move', move_window)

-- Resize - Percent of Screen
local function move_percent_screen(percent_x, percent_y)
	msg.debug('Trying to move window to', percent_x, percent_y, '% of screen')
	percent_x = sanitize(percent_x, -100, 100, 50, true) / 100
	percent_y = sanitize(percent_y, -100, 100, 50, true) / 100
	local x = percent_x > 0 and (percent_x * opts.screen_width)  or ((1 + percent_x) * opts.screen_width)
	local y = percent_y > 0 and (percent_x * opts.screen_height) or ((1 + percent_y) * opts.screen_height)
	move_window(x, y)
end
mp.register_script_message('Move%Screen', move_percent_screen)

-- Move - Align
local function align(a)
	msg.debug('Trying to align window to', a)
	a = sanitize(a, 1, 9, 5)
	local x, y = 0, 0
	if a == 1 or a == 4 or a == 7 then x = 0 end
	if a == 2 or a == 5 or a == 8 then x = (opts.screen_width - osd_width) / 2 end
	if a == 3 or a == 6 or a == 9 then x = (opts.screen_width - osd_width) end
	if a == 7 or a == 8 or a == 9 then y = 0 end
	if a == 4 or a == 5 or a == 6 then y = (opts.screen_height - osd_height) / 2 end
	if a == 1 or a == 2 or a == 3 then y = (opts.screen_height - osd_height) end
	move_window(x, y)
end
mp.register_script_message('Align', align)



------------------
-- Set Defaults --
------------------
local default_resize = { resize, resize_percent_screen, resize_percent }
local function set_default_resize()
	if video_width == 0 or not video_height == 0 then
		msg.debug('Waiting for video-params')
		mp.add_timeout(0.050, set_default_resize)
	else
		msg.debug('Default Resizing')
		if opts.default_resize_type ~= 0 then
			default_resize[sanitize(opts.default_resize_type, 1, 3, 1)](opts.default_resize_width, opts.default_resize_height)
		end
	end
end

local default_move = { move_window, move_percent_screen }
local function set_default_move()
	if osd_width == 0 or osd_height == 0 or not is_same_size(resized_width, resized_height, osd_width, osd_height) then
		msg.debug('Waiting for osd size')
		msg.debug('osd:', osd_width, osd_height, 'resized:', resized_width, resized_height)
		mp.add_timeout(0.050, set_default_move)
	else
		msg.debug('Default Moving')
		if opts.default_align ~= 0 then
			align(opts.default_align)
		elseif opts.default_move_type ~= 0 then
			default_move[sanitize(opts.default_move_type, 1, 2, 1)](opts.default_move_x, opts.default_move_y)
		end
	end
end

local function set_defaults()
	if fullscreen then return end
	set_default_resize()
	set_default_move()
end

local function reset_and_set_defaults()
	resized_width, resized_height = 0, 0
	rotate_initial = mp.get_property_native('video-params/rotate', 0)
	set_defaults()
end

mp.register_event('file-loaded', function() mp.add_timeout(0.050, reset_and_set_defaults) end)
mp.register_script_message('Defaults', set_defaults)
mp.observe_property('video-params/rotate', 'native', function(_, rotate) 
	if not rotate then return end
	mp.add_timeout(0.050, set_defaults)
end)
