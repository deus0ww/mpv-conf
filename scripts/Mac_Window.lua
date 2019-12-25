-- deus0ww - 2019-12-25

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



------------------
-- User Options --
------------------
local o = {
	display_w           = 2560,
	display_h           = 1440,

	default_resize_type = 3,     -- 0=Off, 1=Absolute, 2=Percent of display, 3=Percent of display (one-axis), 4=Percent of Video
	default_resize_w    = 50, 
	default_resize_h    = 50,

	default_align       = 3,     -- Align to display edges; 0=Off, 1-9=Numpad Direction (Priority over 'Move')

	default_move_type   = 0,     -- 0=Off, 1=Absolute, 2=Percent of display
	default_move_x      = 50,
	default_move_y      = 50,
	
	async_applescript   = false, -- Run applescripts asynchronously (faster but more error-prone)
}

local menubar_h = 23   -- 22px + 1px border
local display, align_current
local function on_opts_update()
	display       = {w = o.display_w, h = o.display_h - menubar_h }
	align_current = o.default_align
end
opt.read_options(o, mp.get_script_name(), on_opts_update)
on_opts_update()


----------------
-- Properties --
----------------
local osd_w, osd_h   = 0, 0
local rotate_initial = 0
local rotate_current = 0

local function get_video_size() return { w = mp.get_property_native('video-params/dw', 0), h = mp.get_property_native('video-params/dh', 0) } end
local function is_fullscreen()  return mp.get_property_native('fullscreen', true) end
local function is_rotated()     return not ((((rotate_current - rotate_initial) % 180) ~= 0) == ((rotate_initial % 180) ~= 0)) end



-----------------
-- AppleScript --
-----------------
local as_pre  = 'tell app "System Events"'
local as_set  = 'set %s of every window of (every process whose unix id = %d) to {%d, %d}'
local as_post = 'end tell'
local as_get  = 'tell app "System Events" to get {position, size} of every window of (every process whose unix id = %d)'
local cmd     = { name = 'subprocess', capture_stdout = true, capture_stderr = true, }
local pid     = utils.getpid()

local function handle_error(desc, script, res)
	msg.warn(desc, res.stderr)
	msg.warn('Failed Command:', script)
	if res.stderr == nil then return end
	if res.stderr:find('osascript is not allowed assistive access') ~= nil then
		mp.osd_message('Moving/Resizing Failed: Assistive access denied.', 4)
	elseif res.stderr:find('Not authorized to send Apple events to System Events.') ~= nil then
		mp.osd_message('Moving/Resizing Failed: Not authorized.', 4)
	else
		mp.osd_message('Moving/Resizing Failed.')
	end
end

local function run_set(x, y, w, h)
	msg.debug('Setting:', utils.to_string({{x=x, y=y}, {w=w, h=h}, pid=pid}))
	if is_fullscreen() then
		msg.debug('Aborted - In Fullscreen')
		return
	end
	local args = {'osascript'}
	args[#args+1] = '-e'
	args[#args+1] = as_pre
	if ((x and x > 0) and (y and y > 0)) then
		args[#args+1] = '-e'
		args[#args+1] = as_set:format('position', pid, x, y)
	end
	if ((w and w > 0) and (h and h > 0)) then
		args[#args+1] = '-e'
		args[#args+1] = as_set:format('size', pid, w, h)
	end
	args[#args+1] = '-e'
	args[#args+1] = as_post
	cmd.args = args
	if o.async_applescript then
		mp.command_native_async(cmd, function(_, res, _) 
			if (#res.stderr > 0) then
				handle_error('Setting window state failed.', utils.to_string(args), res)
			end
		end)
	else
		local res = mp.command_native(cmd)
		if res.status < 0 or #res.error_string > 0 or #res.stderr > 0 then
			handle_error('Setting window state failed.', utils.to_string(args), res)
		end
	end
end

local function run_get()
	msg.debug('Getting position and size. PID:', pid)
	local args = {'osascript'}
	args[#args+1] = '-e'
	args[#args+1] = as_get:format(pid)
	cmd.args = args
	local res = mp.command_native(cmd)
	if res.status < 0 or #res.error_string > 0 or #res.stderr > 0 or #res.stdout == 0 then
		handle_error('Getting window state failed.', utils.to_string(args), res)
		return { x = -1, y = -1, w = -1, h = -1 }
	end
	local u = {}
	for num in res.stdout:gmatch('[^,%s]+') do
		u[#u+1] = tonumber(num) or -1
	end
	local v = { x = u[1], y = u[2], w = u[3], h = u[4] }
	msg.debug(utils.to_string(v))
	return v
end

local function run_get_simple()
	if ((osd_w and osd_w > 0) and (osd_h and osd_h > 0)) then
		local hidpi_scale = mp.get_property_native('display-hidpi-scale', 1.0)
		msg.debug('Getting Size: OSD - Scale:', hidpi_scale)
		return { x = -1, y = -1, w = (osd_w / hidpi_scale), h = (osd_h / hidpi_scale) }
	else
		msg.debug('Getting Size: AppleScript')
		return run_get()
	end
end



------------
-- Global --
------------
local function sanitize(input, min, max, default, no_rounding)
	if type(input) ~= 'number' then input = (tonumber(input) or default or 0) end
	if min then input = math.max(input, min) end
	if max then input = math.min(input, max) end
	return no_rounding and input or (input < 0 and math.ceil(input - 0.5) or math.floor(input + 0.5))
end

local function sanitize_all(x, y, w, h)
	x = x and sanitize(x, 0, display.w, 0) or nil
	y = y and sanitize(y, 0, display.h, 0) or nil
	w = w and sanitize(w, 0, display.w, 0) or nil
	h = h and sanitize(h, 0, display.h, 0) or nil
	return x, y, w, h
end



-------------------
-- Resize Window --
-------------------
-- Resize - Absolute Size
local function resize_absolute(w, h)
	msg.debug('Target Size:', w, h)
	local _, _, w, h = sanitize_all(nil, nil, w, h)
	local video = get_video_size()
	local aspect = is_rotated() and video.h / video.w or video.w / video.h
	if (w / h) > aspect then
		w = math.floor(h * aspect + 0.5)
	else
		h = math.floor(w / aspect + 0.5)
	end
	msg.debug('Target Size:', w, h)
	return w, h
end

-- Resize - Percent of display Size
local function resize_percent_display(px, py)
	msg.debug('Target Size:', px, py, '% of display')
	px = sanitize(px, 0, 100, 100, true) / 100
	py = sanitize(py, 0, 100, 100, true) / 100
	return resize_absolute(display.w * px, display.h * py)
end

-- Resize - Percent of display Size (one-axis)
local function resize_percent_display_oneaxis(percent)
	msg.debug('Target Size:', percent, '%', '(one-axis)')
	local video = get_video_size()
	local aspect = is_rotated() and video.h / video.w or video.w / video.h
	if aspect > 1 then
		return resize_percent_display(100, percent)
	else
		return resize_percent_display(percent, 100)
	end
end

-- Resize - Percent of Video Size
local function resize_percent(percent)
	msg.debug('Target Size:', percent, '%')
	percent = sanitize(percent, 0, 800, 100, true) / 100
	local video = get_video_size()
	local w, h = video.w * percent, video.h * percent
	if is_rotated() then w, h = h, w end
	return resize_absolute(w, h)
end



-----------------
-- Move Window --
-----------------
-- Move - Absolute Coordinate
local function move_absolute(x, y, w, h)
	msg.debug('Target Position:', x, y)
	x, y, w, h = sanitize_all(x, y, w, h)
	x = math.min(display.w - w, x)
	y = math.min(display.h - h, y)
	x, y, w, h = sanitize_all(x, y + menubar_h, w, h)
	msg.debug('Target Position:', x, y)
	return x, y
end

-- Move - Percent of display
local function move_percent_display(px, py, w, h)
	msg.debug('Target Position:', px, py, '% of display')
	px = sanitize(px, -100, 100, 50, true) / 100
	py = sanitize(py, -100, 100, 50, true) / 100
	local x = px > 0 and (px * display.w) or ((1 + px) * display.w)
	local y = py > 0 and (px * display.h) or ((1 + py) * display.h)
	return move_absolute(x, y, w, h)
end

-- Move - Align
local function move_align(a, w, h)
	msg.debug('Target Position:', a, '(Alignment)')
	if a == 0 then return end
	a = sanitize(a, 1, 9, 5)
	local x, y = 0, 0
	if a == 1 or a == 4 or a == 7 then x = 0 end
	if a == 2 or a == 5 or a == 8 then x = (display.w - w) / 2 end
	if a == 3 or a == 6 or a == 9 then x = (display.w - w) end
	if a == 7 or a == 8 or a == 9 then y = 0 end
	if a == 4 or a == 5 or a == 6 then y = (display.h - h) / 2 end
	if a == 1 or a == 2 or a == 3 then y = (display.h - h) end
	return move_absolute(x, y, w, h)
end



----------
-- Core --
----------
local function window_changed(a, b) return ((a.w ~= b.w) or (a.h ~= b.h) or (a.x ~= b.x) or (a.y ~= b.y)) end

local function get_current_state()
	local current = run_get_simple()
	local target  = { x = current.x, y = current.y, w = current.w, h = current.h }
	return current, target
end

local function change_window_once(current, target)
	if (window_changed(current, target) and not is_fullscreen()) then
		run_set(target.x, target.y, target.w, target.h)
	else
		msg.debug('Aborting - Unchanged or in fullscreen')
	end
end

local function change_window(current, target)
	msg.debug('Changing Window (attempt 1) - Current:', utils.to_string(current), '| Target: ', utils.to_string(target))
	change_window_once(current, target)
	
	current = run_get()
	msg.debug('Changing Window (attempt 2) - Current:', utils.to_string(current), '| Target: ', utils.to_string(target))
	change_window_once(current, target)
end

local function resize(w, h, resize_type)
	msg.debug(' === Resizing ===')
	local current, target = get_current_state()
	target.w, target.h = resize_type(w, h)
	if align_current ~= 0 then
		target.x, target.y = move_align(align_current, target.w, target.h)
	else
		target.x, target.y = move_absolute(current.x, current.y, target.w, target.h)
	end
	change_window(current, target)
end

local function move(x, y, move_type)
	msg.debug(' === Moving ===')
	local current, target = get_current_state()
	target.x, target.y = move_type(x, y, current.w, current.h)
	change_window(current, target)
end

local function align(a)
	msg.debug(' === Align ===')
	local current, target = get_current_state()
	align_current = a
	target.x, target.y = move_align(a, current.w, current.h)
	change_window(current, target)
end



--------------
-- Bindings --
--------------
mp.register_script_message('Resize',         function(w, h) resize(w, h, resize_absolute) end)
mp.register_script_message('Resize%Display', function(w, h) resize(w, h, resize_percent_display) end)
mp.register_script_message('Resize%Area',    function(w, h) resize(w, h, resize_percent_display_oneaxis) end)
mp.register_script_message('Resize%',        function(w, h) resize(w, h, resize_percent) end)

mp.register_script_message('Move',           function(x, y) move(x, y, move_absolute) end)
mp.register_script_message('Move%Display',   function(x, y) move(x, y, resize_percent_display) end)
mp.register_script_message('Align',          align)



------------------
-- Set Defaults --
------------------
local default_resize = { resize_absolute, resize_percent_display, resize_percent_display_oneaxis, resize_percent }
local default_move   = { move_absolute, move_percent_display }

local function reset_rotation()
	rotate_initial = mp.get_property_native('video-params/rotate', 0)
	rotate_current = rotate_initial
end

local function set_defaults()
	if is_fullscreen() then return end
	align_current  = o.default_align
	local resize_type = sanitize(o.default_resize_type, 0, 3, 1)
	local move_type   = sanitize(o.default_move_type,   0, 2, 1)
	
	if resize_type == 0 then
		align(align_current)
	else
		resize(o.default_resize_w, o.default_resize_h, default_resize[resize_type])
	end
	if o.default_align == 0 and move_type ~= 0 then
		move(o.default_move_x, o.default_move_y, default_move[move_type])
	end
end
mp.register_script_message('Defaults', set_defaults)

local timer
mp.register_event('file-loaded', function()
	reset_rotation()
	if timer then timer:kill() end
	timer = mp.add_periodic_timer(0.05, function()
		if is_fullscreen() then
			timer:kill()
			msg.debug('Fullscreen - Aborting')
		elseif ((osd_w and osd_w > 0) and (osd_h and osd_h > 0)) then
			timer:kill()
			msg.debug('OSD - Ready')
			set_defaults()
		else
			msg.debug('OSD - Waiting: ', osd_w, osd_h)
		end
	end)
end)

mp.observe_property('osd-width',  'native', function(_, w) osd_w = w end)
mp.observe_property('osd-height', 'native', function(_, h) osd_h = h end)
mp.observe_property('video-params/rotate', 'native', function(_, rotate)
	if not rotate or rotate == rotate_current or is_fullscreen() then return end
	rotate_current = rotate
	set_defaults()
end)
