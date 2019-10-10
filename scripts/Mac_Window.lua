-- deus0ww - 2019-10-06

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



------------------
-- User Options --
------------------
local opts = {
	display_w           = 2560,
	display_h           = 1440,
	scale_factor        = 1,	 -- 1=Non-Retina, 2=Retina

	default_resize_type = 3,     -- 0=Off, 1=Absolute, 2=Percent of display, 3=Percent of display (one-axis), 4=Percent of Video
	default_resize_w    = 50, 
	default_resize_h    = 50,

	default_align       = 3,     -- Align to display edges; 0=Off, 1-9=Numpad Direction (Priority over 'Move')

	default_move_type   = 0,     -- 0=Off, 1=Absolute, 2=Percent of display
	default_move_x      = 50,
	default_move_y      = 50,
	
	check_position      = false, -- Reduces movement but slower
	async_applescript   = true,  -- Run applescripts asynchronously (faster but more error-prone)
}
opt.read_options(opts, mp.get_script_name())



----------------
-- Properties --
----------------
local menubar_h      = 23   -- 22px + 1px border
local display        = {w = opts.display_w, h = opts.display_h - menubar_h }
local align_current  = opts.default_align

local rotate_initial = 0
local rotate_current = 0

local function get_video_size() return { w = mp.get_property_native('video-params/dw', 0), h = mp.get_property_native('video-params/dh', 0) } end
local function is_fullscreen()  return mp.get_property_native('fullscreen', true) end
local function is_rotated()     return not ((((rotate_current - rotate_initial) % 180) ~= 0) == ((rotate_initial % 180) ~= 0)) end



-----------------
-- AppleScript --
-----------------
local as_set = 'tell app "System Events" to set %s of window 1 of (process 1 whose unix id = %d) to {%d, %d}'
local as_get = 'tell app "System Events" to get %s of window 1 of (process 1 whose unix id = %d)'
local cmd    = { name = 'subprocess', args = {'osascript', '-e'}, capture_stdout = true, capture_stderr = true, }
local pid    = utils.getpid()

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

local function run_get(property)
	msg.debug('Getting:', property, 'PID:', pid)
	local script = as_get:format(property, pid)
	cmd.args[3] = script
	local res = mp.command_native(cmd)
	if res.status < 0 or #res.error_string > 0 or #res.stderr > 0 or #res.stdout == 0 then
		handle_error('Getting ' .. property .. ' failed.', script, res)
		return {-1, -1}
	end
	local v = {}
	for num in res.stdout:gmatch('[^,%s]+') do
		v[#v+1] = tonumber(num) or -1
	end
	msg.debug(utils.to_string(v))
	return v
end

local function run_set(property, arg1, arg2)
	msg.debug('Setting:', property, arg1, arg2, 'PID:', pid)
	local script = as_set:format(property, pid, arg1, arg2)
	cmd.args[3] = script
	if opts.async_applescript then
		mp.command_native_async(cmd, function(_, res, _) if (#res.stderr > 0) then handle_error('Setting ' .. property .. ' failed.', script, res) end end)
	else
		local res = mp.command_native(cmd)
		if res.status < 0 or #res.error_string > 0 or #res.stderr > 0 then
			handle_error('Setting ' .. property .. ' failed.', script, res)
		end
	end
end



---------------------
-- Getters/Setters --
---------------------
local function get_position()
	if opts.check_position then
		local u = run_get('position')
		return { x = u[1], y = u[2] }
	else
		return { x = -1, y = -1 }
	end
end

local function get_size()
	local osd_w, osd_h = mp.get_osd_size()
	if osd_w and osd_w > 0 and osd_h and osd_h > 0 then
		msg.debug('Getting: OSD Size')
		return { w = (osd_w / opts.scale_factor), h = (osd_h / opts.scale_factor) }
	else
		local v = run_get('size')
		return { w = v[1], h = v[2] }
	end
end

local function get_position_and_size()
	local u, v = get_position(), get_size()
	local z = { x = u.x, y = u.y, w = v.w, h = v.h }
	msg.debug('Current Window:', utils.to_string(z))
	return z
end

local function set_position(x, y) 
	msg.debug('Trying to set position:', x, y)
	if is_fullscreen() then
		msg.debug('Aborted - In Fullscreen')
	else
		run_set('position', x, y + menubar_h)
	end
end

local function set_size(w, h)
	msg.debug('Trying to set size:', w, h)
	if is_fullscreen() then
		msg.debug('Aborted - In Fullscreen')
	else
		run_set('size', w, h)
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
	x, y, w, h = sanitize_all(x, y, w, h)
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
local function change_window(current, target)
	msg.debug('Changing Window - Current:', utils.to_string(current))
	msg.debug('Changing Window - Target: ', utils.to_string(target))
	-- Move first if expanding
	if (current.x ~= target.x or current.y ~= target.y) and
	   (current.w  < target.w or current.w  < target.w) then
		set_position(target.x, target.y)
	end
	
	-- Resize
	if (current.w ~= target.w or current.h ~= target.h) then set_size(target.w, target.h) end
	
	-- Move after if shrinking or not resizing
	if (current.x ~= target.x or current.y ~= target.y) and
	   (current.w >= target.w or current.w >= target.w) then
		set_position(target.x, target.y)
	end
end

local function get_current_state()
	local current = get_position_and_size()
	local target  = { x = current.x, y = current.y, w = current.w, h = current.h }
	return current, target
end

local function move_on_screen() -- Make sure the window is completely on screen
	msg.debug(' === Moving on Screen ===')
	local current, target = get_current_state()
	target.x, target.y = move_absolute(current.x, current.y, target.w, target.h)
	change_window(current, target)
end

local function resize(w, h, resize_type)
	if opts.check_position then move_on_screen() end
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
	align_current  = opts.default_align
	local resize_type = sanitize(opts.default_resize_type, 0, 3, 1)
	local move_type   = sanitize(opts.default_move_type,   0, 2, 1)
	
	if resize_type == 0 then
		align(align_current)
	else
		resize(opts.default_resize_w, opts.default_resize_h, default_resize[resize_type])
	end
	if opts.default_align == 0 and move_type ~= 0 then
		move(opts.default_move_x, opts.default_move_y, default_move[move_type])
	end
end

local function on_file_loaded()
	reset_rotation()
	set_defaults()
end

mp.register_event('file-loaded', function() mp.add_timeout(0.25, on_file_loaded) end)

mp.register_script_message('Defaults', set_defaults)

mp.observe_property('video-params/rotate', 'native', function(_, rotate)
	if not rotate or rotate == rotate_current then return end
	rotate_current = rotate
	mp.add_timeout(0.25, set_defaults)
end)
