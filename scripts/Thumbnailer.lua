-- deus0ww - 2019-03-24

local ipairs,loadfile,pairs,pcall,tonumber,tostring = ipairs,loadfile,pairs,pcall,tonumber,tostring
local debug,io,math,os,string,table,utf8 = debug,io,math,os,string,table,utf8
local min,max,floor,ceil,huge = math.min,math.max,math.floor,math.ceil,math.huge
local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'

local script_name = mp.get_script_name()

local message = {
	mpv = {
		file_loaded   = 'file-loaded',
		file_unloaded = 'end-file',
		shutdown      = 'shutdown',
	},
	worker = {
		registration  = 'tn_worker_registration',
		reset         = 'tn_worker_reset',
		queue         = 'tn_worker_queue',
		start         = 'tn_worker_start',
		progress      = 'tn_worker_progress',
		finish        = 'tn_worker_finish',
	},
	osc = {
		registration  = 'tn_osc_registration',
		reset         = 'tn_osc_reset',
		update        = 'tn_osc_update',
		finish        = 'tn_osc_finish',
	},
	debug = 'Thumbnailer-debug',

	manual_start = script_name .. '-start',
	manual_stop  = script_name .. '-stop',
	manual_show  = script_name .. '-show',
	manual_hide  = script_name .. '-hide',
	toggle_gen   = script_name .. '-toggle-gen',
	toggle_osc   = script_name .. '-toggle-osc',
	double       = script_name .. '-double',
	shrink       = script_name .. '-shrink',
	enlarge      = script_name .. '-enlarge',

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

local function is_empty(...) -- Not for tables
	if ... == nil then return true end
	for _, v in ipairs({...}) do
		if (v == nil) or (v == '') or (v == 0) then return true end
	end
	return false
end


-------------------------------------
-- External Process and Filesystem --
-------------------------------------
local function subprocess_result(sub_success, result, mpv_error, subprocess_name, start_time)
	local cmd_status, cmd_stdout, cmd_stderr, cmd_error, cmd_killed
	if result then cmd_status, cmd_stdout, cmd_stderr, cmd_error, cmd_killed = result.status, result.stdout, result.stderr, result.error_string, result.killed_by_us end
	local cmd_status_success, cmd_status_string, cmd_err_success, cmd_err_string, success
	
	if     cmd_status == 0      then cmd_status_success, cmd_status_string = true,  'ok'
	elseif is_empty(cmd_status) then cmd_status_success, cmd_status_string = true,  '_'
	elseif cmd_status == 124 or cmd_status == 137 or cmd_status == 143 then -- timer: timed-out(124), killed(128+9), or terminated(128+15)
	                                 cmd_status_success, cmd_status_string = false, 'timed out'
	else                             cmd_status_success, cmd_status_string = false, ('%d'):format(cmd_status) end
	
	if     is_empty(cmd_error)   then cmd_err_success, cmd_err_string = true,  '_'
	elseif cmd_error == 'init'   then cmd_err_success, cmd_err_string = false, 'failed to initialize'
	elseif cmd_error == 'killed' then cmd_err_success, cmd_err_string = false, cmd_killed and 'killed by us' or 'killed, but not by us'
	else                              cmd_err_success, cmd_err_string = false, cmd_error end
	
	if is_empty(cmd_stdout) then cmd_stdout = '_' end
	if is_empty(cmd_stderr) then cmd_stderr = '_' end
	subprocess_name = subprocess_name or '_'
	start_time = start_time or os.time()
	success = (sub_success == nil or sub_success) and is_empty(mpv_error) and cmd_status_success and cmd_err_success

	if success then msg.debug('Subprocess', subprocess_name, 'succeeded. | Status:', cmd_status_string, '| Time:', ('%ds'):format(os.difftime(os.time(), start_time)))
	else            msg.error('Subprocess', subprocess_name, 'failed. | Status:', cmd_status_string, '| MPV Error:', mpv_error or 'n/a', 
	                          '| Subprocess Error:', cmd_err_string, '| Stdout:', cmd_stdout, '| Stderr:', cmd_stderr) end
	return success, cmd_status_string, cmd_err_string, cmd_stdout, cmd_stderr
end

local function run_subprocess(command, name)
	if not command then return false end
	local subprocess_name, start_time = name or command[1], os.time()
	msg.debug('Subprocess', subprocess_name, 'Starting...')
	result, mpv_error = mp.command_native( {name='subprocess', args=command} )
	local success, _, _, _ = subprocess_result(nil, result, mpv_error, subprocess_name, start_time)
	return success
end

local function run_subprocess_async(command, name)
	if not command then return false end
	local subprocess_name, start_time = name or command[1], os.time()
	msg.debug('Subprocess', subprocess_name, 'Starting (async)...')
	mp.command_native_async( {name='subprocess', args=command}, function(s, r, e) subprocess_result(s, r, e, subprocess_name, start_time) end )
	return nil
end

local function join_paths(...)
	local sep = OPERATING_SYSTEM == OS_WIN and '\\' or '/'
	local result = ''
	for _, p in ipairs({...}) do
		result = (result == '') and p or result .. sep .. p
	end
	return result
end

local function file_exists(path)
	local file = io.open(path, 'rb')
	if not file then return false end
	local _, _, code = file:read(1)
	file:close()
	return code == nil
end

local function exec_exist(name)
	local delim = ':'
	if OPERATING_SYSTEM == OS_WIN then delim, name = ';', name .. '.exe' end
	local env_path = (os.getenv('PWD') or utils.getcwd()) .. delim .. os.getenv('PATH')
	for path_dir in env_path:gmatch('[^'..delim..']+') do
		if file_exists(join_paths(path_dir, name)) then return true end
	end
	return false
end

local function dir_exist(path)
	local ok, _, _ = os.rename(path .. '/', path .. '/')
	if not ok then return false end
	local file = io.open(join_paths(path, 'test'), 'w')
	if file then 
		file:close()
		return os.remove(join_paths(path, 'test'))
	end
	return false
end

local function create_dir(path)
	return run_subprocess(    OPERATING_SYSTEM == OS_WIN and {'cmd', '/c', 'mkdir', path}    or {'mkdir', '-p', path} ) and dir_exist(path)
end

local function delete_dir(path)
	if is_empty(path) then return end
	msg.warn('Deleting Dir:', path)
	return mp.command_native( OPERATING_SYSTEM == OS_WIN and {'run', 'rd', '/S', '/Q', path} or {'run', 'rm', '-r', path} )
end


--------------------
-- Data Structure --
--------------------
local initialized        = false
local default_cache_dir  = join_paths(OPERATING_SYSTEM == OS_WIN and os.getenv('TEMP') or '/tmp/', script_name)
local saved_state, state

local user_opts = {
	-- General
	auto_gen             = true,               -- Auto generate thumbnails
	auto_show            = true,               -- Show thumbnails by default
	delete_on_quit       = false,              -- Delete the thumbnail cache on quit. Use at your own risk.

	-- Paths
	cache_dir            = default_cache_dir,  -- Note: Files are not cleaned afterward, by default
	worker_script_path   = '',                 -- Only needed if the script can't auto-locate the file to load more workers

	-- Thumbnail
	dimension            = 320,                -- Max width and height before scaling
	thumbnail_count      = 192,                -- Try to create this many thumbnails within the delta limits below
	min_delta            = 1,                  -- Minimum time between thumbnails (seconds)
	max_delta            = 30,                 -- Maximum time between thumbnails (seconds)
	remote_delta_factor  = 2.0,                -- Multiply delta by this for remote streams

	-- OSC
	spacer               = 2,                  -- Size of borders and spacings
	show_progress        = 1,                  -- Display the thumbnail-ing progress. (0=never, 1=while generating, 2=always)
	scale                = 0,                  -- 0=Use OSC scaling, 1=No scaling, 2=Retina/HiDPI. For 0, it is recommended to set scalefullscreen = scalewindowed to avoid regenerations.
	centered             = false,              -- Center the thumbnail on screen

	-- Worker
	max_workers          = 4,                  -- Number of active workers. Must have at least one copy of the worker script alongside this script.
	remote_worker_factor = 1,                  -- Multiply max_workers by this for remote streams
	worker_delay         = 0.5,                -- Delay between starting workers (seconds)
	worker_timeout       = 0,                  -- Wait this long, in seconds, before killing encoder. 0=No Timeout (Linux or Mac w/ coreutils installed only)
	accurate_seek        = false,              -- Use accurate timing instead of closest keyframe for thumbnails. (Slower)
	use_ffmpeg           = false,              -- Use FFMPEG when appropriate. FFMPEG must be in PATH or in the MPV directory
	prefer_ffmpeg        = false,              -- Use FFMPEG when available
	ffmpeg_threads       = 0,                  -- Limit FFMPEG/MPV LAVC threads per worker. Also limits filter and output threads for FFMPEG.
	ffmpeg_scaler        = 'bicublin',         -- Applies to both MPV and FFMPEG. See: https://ffmpeg.org/ffmpeg-scaler.html
}

local thumbnails, thumbnails_new,thumbnails_new_count

local function reset_thumbnails()
	thumbnails           = {}
	thumbnails_new       = {}
	thumbnails_new_count = 0
end

------------
-- Worker --
------------
local workers, workers_indexed = {}, {}
local workers_started, workers_finished, workers_finished_indexed, timer_start, timer_total

local function workers_reset()
	workers_started          = false
	workers_finished         = {}
	workers_finished_indexed = {}
	timer_start              = 0
	timer_total              = 0
	for _, worker in ipairs(workers_indexed) do
		mp.command_native({'script-message-to', worker, message.worker.reset})
	end
end

local function worker_set_options()
	return {
		encoder        = (not state.is_remote and (user_opts.use_ffmpeg and exec_exist('ffmpeg') and (user_opts.prefer_ffmpeg or not state.is_slow))) and 'ffmpeg' or 'mpv',
		worker_timeout = user_opts.worker_timeout,
		accurate_seek  = user_opts.accurate_seek,
		use_ffmpeg     = user_opts.use_ffmpeg,
		ffmpeg_threads = user_opts.ffmpeg_threads,
		ffmpeg_scaler  = user_opts.ffmpeg_scaler,
	}
end

local function workers_queue()
	local worker_data = {
		state          = state,
		worker_options = worker_set_options(),
	}
	local max_delta        = state.duration / state.delta
	local worker_count     = min(#workers_indexed, state.max_workers)
	local delta_per_worker = max_delta / worker_count
	local start_time_index = 0

	for i, worker in ipairs(workers_indexed) do
		if i > worker_count then break end
		worker_data.start_time_index = start_time_index
		worker_data.delta_per_worker = (i == worker_count) and max_delta - start_time_index or delta_per_worker
		mp.command_native_async({'script-message-to', worker, message.worker.queue, format_json(worker_data)}, function() end)
		start_time_index = start_time_index + floor(delta_per_worker) + 1
	end
end

local function workers_start()
	timer_start = os.time()
	if state.cache_dir and state.cache_dir ~= '' then os.remove(join_paths(state.cache_dir, 'stop')) end
	for i, worker in ipairs(workers_indexed) do
		if i > state.max_workers then break end
		mp.add_timeout( user_opts.worker_delay * i, function() mp.command_native({'script-message-to', worker, message.worker.start}) end)
	end
	workers_started = true
end

local function workers_stop()
	if state and state.cache_dir and state.cache_dir ~= '' then
		local file = io.open(join_paths(state.cache_dir, 'stop'), 'w')
		if file then file:close() end
	end
	if timer_total and timer_start then timer_total = timer_total + os.difftime(os.time(), timer_start) end
	timer_start = 0
end

local function workers_are_stopped()
	if not initialized or not workers_started then return true end
	local file = io.open(join_paths(state.cache_dir, 'stop'), 'r')
	if not file then return false end
	file:close()
	return true
end


---------
-- OSC --
---------
local osc_name, osc_opts, osc_stats, osc_visible

local function osc_reset_stats()
	osc_stats = {
		queued         = 0,
		processing     = 0,
		ready          = 0,
		failed         = 0,
		total          = 0,
		total_expected = 0,
		percent        = 0,
		timer          = 0,
	}
end

local function osc_reset()
	osc_reset_stats()
	osc_visible = nil
	if osc_name then mp.command_native({'script-message-to', osc_name, message.osc.reset}) end
end

local function osc_set_options(is_visible)
	osc_visible = (is_visible == nil) and user_opts.auto_show or is_visible
	return {
		spacer        = user_opts.spacer,
		show_progress = user_opts.show_progress,
		scale         = state.scale,
		centered      = user_opts.centered,
		visible       = osc_visible,
	}
end

local function osc_update(ustate, uoptions, uthumbnails)
	if is_empty(osc_name) then return end
	local osc_data  = {
		state       = ustate,
		osc_options = uoptions,
		thumbnails  = uthumbnails,
	}
	if osc_data.thumbnails then
		osc_stats.timer          = timer_start == 0 and timer_total or (timer_total + os.difftime(os.time(), timer_start))
		osc_stats.total_expected = floor(state.duration / state.delta) + 1
		osc_data.osc_stats       = osc_stats
	else
		osc_data.osc_stats = nil
	end
	mp.command_native_async({'script-message-to', osc_name, message.osc.update, format_json(osc_data)}, function() end)
end

local function osc_delta_update(flush)
	if (thumbnails_new_count >= state.osc_buffer) or (thumbnails_new_count > 0 and flush) then
		osc_update(nil, nil, thumbnails_new)
		thumbnails_new = {}
		thumbnails_new_count = 0
	end
end

local osc_full_update_timer  = mp.add_periodic_timer(1.0, function() osc_update(nil, nil, thumbnails) end)
osc_full_update_timer:kill()
local osc_delta_update_timer = mp.add_periodic_timer(0.5, function() osc_delta_update(true) end)
osc_delta_update_timer:kill()

local count_existing = {
	[message.queued]     = function() osc_stats.queued     = osc_stats.queued     - 1 end,
	[message.processing] = function() osc_stats.processing = osc_stats.processing - 1 end,
	[message.failed]     = function() osc_stats.failed     = osc_stats.failed     - 1 end,
	[message.ready]      = function() osc_stats.ready      = osc_stats.ready      - 1 end,
}
local count_new = {
	[message.queued]     = function() osc_stats.queued     = osc_stats.queued     + 1 end,
	[message.processing] = function() osc_stats.processing = osc_stats.processing + 1 end,
	[message.failed]     = function() osc_stats.failed     = osc_stats.failed     + 1 end,
	[message.ready]      = function() osc_stats.ready      = osc_stats.ready      + 1 end,
}

local function osc_update_count(time_string, status)
	local osc_stats, existing = osc_stats, thumbnails[time_string]
	if existing then count_existing[existing]() else osc_stats.total = osc_stats.total + 1 end
	if status   then count_new[status]()        else osc_stats.total = osc_stats.total - 1 end
	osc_stats.percent = osc_stats.total > 0 and (osc_stats.failed + osc_stats.ready) / osc_stats.total or 0
end


----------------
-- Core Logic --
----------------
local stop_conditions

local worker_script_path

local function create_workers()
	local workers_requested = (state and state.max_workers) and state.max_workers or user_opts.max_workers
	msg.info('Workers Available:', #workers_indexed)
	msg.info('Workers Requested:', workers_requested)
	msg.info('worker_script_path:', worker_script_path)
	local missing_workers = workers_requested - #workers_indexed
	if missing_workers > 0 and worker_script_path ~= nil and worker_script_path ~= '' then
		for _ = 1, missing_workers do
			msg.info('Recruiting Worker...')
			mp.command_native({'load-script', worker_script_path})
		end
	end
end

local function hash_string(input)
	if OPERATING_SYSTEM == OS_WIN then return input end
	local command
	if     exec_exist('shasum')     then command = 'shasum -a 256'
	elseif exec_exist('gsha256sum') then command = 'gsha256sum'
	elseif exec_exist('sha256sum')  then command = 'sha256sum' end
	if not command then return input end -- checksum command unavailable
	local success, file = pcall(io.popen, 'printf "%s" "' .. input .. '" | ' .. command)
	if not (success and file) then return input end
	local line = file:read('*l')
	file:close()
	return line and line:match('%w+') or input
end

local function create_ouput_dir(subpath, dimension, rotate)
	local path = join_paths(user_opts.cache_dir, subpath, dimension, rotate)
	if not create_dir(path) then
		path = join_paths(user_opts.cache_dir, hash_string(subpath), dimension, rotate)
		if not create_dir(path) then path = nil end
	end
	return path
end

local function is_slow_source(duration)
	local demux_state   = mp.get_property_native('demuxer-cache-state', {})
	local demux_ranges  = #demux_state['seekable-ranges']
	local cache_enabled = (demux_ranges > 0) -- Using MPV's logic for enabling the cache to detect slow sources.
	local high_bitrate  = (mp.get_property_native('file-size', 0) / duration) >= (12 * 131072) -- 12 Mbps
	return cache_enabled or high_bitrate
end

local function calculate_timing(is_remote)
	local duration = mp.get_property_native('duration', 0)
	if duration == 0 then return { duration = 0, delta = huge } end
	local delta_target = (is_remote and user_opts.remote_delta_factor or 1) * (saved_state.delta_factor and saved_state.delta_factor or 1) * duration / (user_opts.thumbnail_count - 1)
	local delta = max(user_opts.min_delta, min(user_opts.max_delta, delta_target))
	return { duration = duration, delta = delta }
end

local function calculate_scale()
	if (user_opts and user_opts.scale and user_opts.scale > 0) then return user_opts.scale end
	return (saved_state.fullscreen ~= nil and saved_state.fullscreen) and osc_opts.scalefullscreen or osc_opts.scalewindowed
end

local function calculate_geometry(scale)
	local geometry = { dimension = 0, width = 0, height = 0, scale = 0, rotate = 0, is_rotated = false }
	local video_params = saved_state.video_params
	local dimension = floor(saved_state.size_factor * user_opts.dimension * scale + 0.5)
	if not video_params or is_empty(video_params.dw, video_params.dh) or dimension <= 0 then return geometry end
	local width, height = dimension, dimension
	if video_params.dw > video_params.dh then
		height = width * video_params.dh / video_params.dw
	else
		width = height * video_params.dw / video_params.dh
	end
	geometry.dimension, geometry.width, geometry.height = dimension, floor(min(width,  video_params.dw) + 0.5), floor(min(height, video_params.dh) + 0.5)
	if not video_params.rotate then return geometry end
	geometry.rotate     = (video_params.rotate - saved_state.initial_rotate) % 360
	geometry.is_rotated = not ((((video_params.rotate - saved_state.initial_rotate) % 180) ~= 0) == saved_state.meta_rotated) --xor
	return geometry
end

local function calculate_worker_limit(duration, delta, is_remote, is_slow)
	return max(floor(min(user_opts.max_workers, duration/delta) * ((is_remote or is_slow ) and user_opts.remote_worker_factor or 1) + 0.5), 1)
end

local function has_video()
	local track_list = mp.get_property_native('track-list', {})
	if is_empty(track_list) then return false end
	for _, track in ipairs(track_list) do
		if track.type == 'video' and not track.external and not track.albumart then return true end
	end
	return false
end

local function state_init()
	local input_fullpath  = saved_state.input_fullpath
	local input_filename  = saved_state.input_filename
	local cache_format    = '%.5d'
	local cache_extension = '.bgra'
    local is_remote       = input_fullpath:find('://') ~= nil
	local timing          = calculate_timing(is_remote)
	local scale           = calculate_scale()
	local geometry        = calculate_geometry(scale)
	local meta_rotated    = saved_state.meta_rotated
	local cache_dir       = create_ouput_dir(input_filename, geometry.dimension, geometry.rotate)
	local is_slow         = is_slow_source(timing.duration)
	local max_workers     = calculate_worker_limit(timing.duration, timing.delta, is_remote, is_slow)
	local worker_buffer   = (is_remote or is_slow) and 2 or 4
	local osc_buffer      = (is_remote or is_slow) and worker_buffer or worker_buffer * max_workers

	-- Global State
	state = {
		cache_dir       = cache_dir,
		cache_format    = cache_format,
		cache_extension = cache_extension,
		input_fullpath  = input_fullpath,
		input_filename  = input_filename,
		duration        = timing.duration,
		delta           = timing.delta,
		width           = geometry.width,
		height          = geometry.height,
		scale           = scale,
		rotate          = geometry.rotate,
		meta_rotated    = meta_rotated,
		is_rotated      = geometry.is_rotated,
		is_remote       = is_remote,
		is_slow         = is_slow,
		max_workers     = max_workers,
		worker_buffer   = worker_buffer,
		osc_buffer      = osc_buffer,
	}
	stop_conditions = {
		is_seekable = mp.get_property_native('seekable', true),
		has_video   = has_video() and timing.duration > 1,
	}

	if is_empty(worker_script_path) then worker_script_path = user_opts.worker_script_path end
	create_workers()
	initialized = true
end

local function saved_state_init()
	local rotate = mp.get_property_native('video-params/rotate', 0)
	saved_state = {
		input_fullpath = mp.get_property_native('path', ''),
		input_filename = mp.get_property_native('filename/no-ext', ''):sub(1, 64),
		meta_rotated   = ((rotate % 180) ~= 0),
		initial_rotate = (rotate and rotate or 0) % 360,
		delta_factor   = 1.0,
		size_factor    = 1.0,
		fullscreen     = mp.get_property_native("fullscreen", false)
	}
end

local function is_thumbnailable()
	-- Must catch all cases that's not thumbnail-able and anything else that may crash the OSC.
	if not (state and stop_conditions) then return false end
	for key, value in pairs(state) do
		if key == 'rotate'        and value then goto continue end
		if key == 'worker_buffer' and value then goto continue end
		if key == 'osc_buffer'    and value then goto continue end
		if is_empty(value) then return false end
		::continue::
	end
	for _, value in pairs(stop_conditions) do
		if not value then return false end
	end
	return true
end

local function reset_all(keep_saved, keep_osc_data)
	initialized = false
	osc_full_update_timer:kill()
	osc_delta_update_timer:kill()
	workers_stop()
	workers_reset()
	reset_thumbnails()
	opt.read_options(user_opts, script_name)
	if not keep_saved or not saved_state then saved_state_init() end
	if not keep_osc_data then osc_reset() else osc_reset_stats() end
	msg.info('Reset (' .. (keep_saved and 'Soft' or 'Hard') .. ', ' .. (keep_osc_data and 'OSC-Partial' or 'OSC-All') .. ')')
end

local function run_generation(paused)
	if not initialized or not is_thumbnailable() then return end
	if #workers_indexed < state.max_workers or not osc_name or not osc_opts then
		mp.add_timeout(0.05, function() run_generation(paused) end)
	else
		workers_queue()
		if not paused then
			workers_start()
			osc_delta_update_timer:resume()
		end
	end
end

local function stop() 
	workers_stop()
	osc_delta_update_timer:kill()
	osc_delta_update(true)
end

local function start(paused)
	if not initialized then state_init() end
	if is_thumbnailable() then
		osc_update(state, osc_set_options(osc_visible), nil)
		run_generation(paused)
	end
end

local function osc_set_visibility(is_visible)
	if is_visible and not initialized then start(true) end
	if osc_name then osc_update(nil, osc_set_options(is_visible), nil) end
end


---------------
-- Listeners --
---------------
-- Listen for Manual Start
mp.register_script_message(message.manual_start, start)

-- Listen for Manual Stop
mp.register_script_message(message.manual_stop, stop)

-- Listen for Toggle Generation
mp.register_script_message(message.toggle_gen, function() if workers_are_stopped() then start() else stop() end end)

-- Listen for Manual Show OSC
mp.register_script_message(message.manual_show, function() osc_set_visibility(true) end)

-- Listen for Manual Hide OSC
mp.register_script_message(message.manual_hide, function() osc_set_visibility(false) end)

-- Listen for Toggle Visibility
mp.register_script_message(message.toggle_osc,  function() osc_set_visibility(not osc_visible) end)

-- Listen for Double Frequency
mp.register_script_message(message.double, function()
	if not initialized or not saved_state or not saved_state.delta_factor then return end
	local target = max(0.25, saved_state.delta_factor * 0.5)
	if tostring(saved_state.delta_factor) ~= tostring(target) then
		saved_state.delta_factor = target
		reset_all(true, true)
		start()
	end
end)

local function resize(target)
	if tostring(saved_state.size_factor) ~= tostring(target) then
		saved_state.size_factor = target
		reset_all(true)
		start()
	end
end

-- Listen for Shrink
mp.register_script_message(message.shrink, function()
	if initialized and saved_state and saved_state.size_factor then resize(max(0.2, saved_state.size_factor - 0.2)) end
end)

-- Listen for Enlarge
mp.register_script_message(message.enlarge, function()
	if initialized and saved_state and saved_state.size_factor then resize(min(2.0, saved_state.size_factor + 0.2)) end
end)

-- On Video Params Change
mp.observe_property('video-params', 'native', function(_, video_params)
	if not video_params or is_empty(video_params.dw, video_params.dh) then return end
	if not saved_state or (saved_state.input_fullpath ~= mp.get_property_native('path', '')) then
		reset_all()
		saved_state.video_params   = video_params
		start(not user_opts.auto_gen)
		return
	end
	if initialized and saved_state and saved_state.video_params and saved_state.video_params.rotate and video_params.rotate and tostring(saved_state.video_params.rotate) ~= tostring(video_params.rotate) then
		reset_all(true)
		saved_state.video_params  = video_params
		start()
		return
	end
end)

-- On Fullscreen Change
mp.observe_property('fullscreen', 'native', function(_, fullscreen)
	if (fullscreen == nil) or
	   (user_opts and user_opts.scale and user_opts.scale > 0) or
	   (not osc_opts or osc_opts.scalewindowed == osc_opts.scalefullscreen) then return end
	if initialized and saved_state then
		reset_all(true)
		saved_state.fullscreen = fullscreen
		start()
		return
	end
end)

-- On Shutdown
mp.register_event(message.mpv.shutdown, function()
	if not user_opts.delete_on_quit then return end
	local path = user_opts.cache_dir
	if path:len() < script_name:len() then return end
	delete_dir(path)
end)

-- Listen for OSC Registration
mp.register_script_message(message.osc.registration, function(json)
	local osc_reg = parse_json(json)
	if osc_reg and osc_reg.script_name and osc_reg.osc_opts and not (osc_name and osc_opts) then
		osc_name = osc_reg.script_name
		osc_opts = osc_reg.osc_opts
		msg.info('OSC Registered:', utils.to_string(osc_reg))
	else
		msg.warn('OSC Not Registered:', utils.to_string(osc_reg))
	end
end)

-- Listen for OSC Finish
mp.register_script_message(message.osc.finish, function()
	msg.info('OSC: Finished.')
	osc_delta_update_timer:kill()
	osc_full_update_timer:kill()
end)

-- Listen for Worker Registration
mp.register_script_message(message.worker.registration, function(new_reg)
	local worker_reg = parse_json(new_reg)
	if worker_reg.name and not workers[worker_reg.name] then
		workers[worker_reg.name] = true
		workers_indexed[#workers_indexed + 1] = worker_reg.name
		if (is_empty(worker_script_path)) and not is_empty(worker_reg.script_path) then
			worker_script_path = worker_reg.script_path
			create_workers()
			msg.info('Worker Script Path Recieved:', worker_script_path)
		end
		msg.info('Worker Registered:', worker_reg.name)
	else
		msg.warn('Worker Not Registered:', worker_reg.name)
	end
end)

-- Listen for Worker Progress Report
mp.register_script_message(message.worker.progress, function(json)
	local new_progress = parse_json(json)
	if new_progress.input_filename ~= state.input_filename then return end
	for time_string, new_status in pairs(new_progress.thumbnail_map) do
		if thumbnails_new[time_string] ~= new_status then
			thumbnails_new[time_string] = new_status
			thumbnails_new_count = thumbnails_new_count + 1
		end
		osc_update_count(time_string, new_status)
		thumbnails[time_string] = new_status
	end
end)

-- Listen for Worker Finish
mp.register_script_message(message.worker.finish, function(json)
	local worker_stats = parse_json(json)
	if worker_stats.name and worker_stats.queued == 0 and not workers_finished[worker_stats.name] then
		workers_finished[worker_stats.name] = true
		workers_finished_indexed[#workers_finished_indexed + 1] = worker_stats.name
		msg.info('Worker Finished:', worker_stats.name, json)
	else
		msg.warn('Worker Finished (uncounted):', worker_stats.name, json)
	end
	if #workers_finished_indexed >= state.max_workers then
		msg.info('All Workers: Done.')
		osc_delta_update_timer:kill()
		osc_delta_update(true)
		osc_full_update_timer:resume()
	end
end)

-- Debug
mp.register_script_message(message.debug, function()
	msg.info('============')
	msg.info('Video Stats:')
	msg.info('============')
	msg.info('video-params', utils.to_string(mp.get_property_native('video-params', {})))
	msg.info('video-dec-params', utils.to_string(mp.get_property_native('video-dec-params', {})))
	msg.info('video-out-params', utils.to_string(mp.get_property_native('video-out-params', {})))
	
	msg.info('============================')
	msg.info('Thumbnailer Internal States:')
	msg.info('============================')
	msg.info('saved_state:', state and utils.to_string(saved_state) or 'nil')
	msg.info('state:', state and utils.to_string(state) or 'nil')
	msg.info('stop_conditions:', stop_conditions and utils.to_string(stop_conditions) or 'nil')
	msg.info('user_opts:', user_opts and utils.to_string(user_opts) or 'nil')
	msg.info('worker_script_path:', worker_script_path and worker_script_path or 'nil')
	msg.info('osc_name:', osc_name and osc_name or 'nil')
	msg.info('osc_stats:', osc_stats and utils.to_string(osc_stats) or 'nil')
	msg.info('thumbnails:', thumbnails and utils.to_string(thumbnails) or 'nil')
	msg.info('thumbnails_new:', thumbnails_new and utils.to_string(thumbnails_new) or 'nil')
	msg.info('workers:', workers and utils.to_string(workers) or 'nil')
	msg.info('workers_indexed:', workers_indexed and utils.to_string(workers_indexed) or 'nil')
	msg.info('workers_finished:', workers_finished and utils.to_string(workers_finished) or 'nil')
	msg.info('workers_finished_indexed:', workers_finished_indexed and utils.to_string(workers_finished_indexed) or 'nil')
end)
