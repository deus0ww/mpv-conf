-- deus0ww - 2019-03-11

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'

-----------
-- Utils --
-----------
local function is_empty(...) -- Not for tables
	if ... == nil then return true end
	for _, v in ipairs({...}) do
		if (v == nil) or (v == '') or (v == 0) then return true end
	end
	return false
end

local function subprocess_result(sub_success, result, mpv_error)
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
	
	success = (sub_success == nil or sub_success) and is_empty(mpv_error) and cmd_status_success and cmd_err_success
	return success, cmd_status_string, cmd_err_string, cmd_stdout, cmd_stderr
end

local function run_subprocess(command, name)
	if not command then return false end
	local subprocess_name = name or command[1]
	local timer_start = os.time()
	msg.debug('Subprocess', subprocess_name, 'Starting...')
	local result, mpv_error = mp.command_native( {name='subprocess', args=command} )
	local success, cmd_status_string, cmd_err_string, cmd_stdout, cmd_stderr = subprocess_result(nil, result, mpv_error)
	if success then msg.debug('Subprocess', subprocess_name, 'succeeded. | Status:', cmd_status_string, '| Time:', ('%ds'):format(os.difftime(os.time(), timer_start)))
	else            msg.error('Subprocess', subprocess_name, 'failed. | Status:', cmd_status_string, '| MPV Error:', mpv_error or 'n/a', 
	                          '| Subprocess Error:', cmd_err_string, '| Stdout:', cmd_stdout, '| Stderr:', cmd_stderr) end
	return success
end


--------------
-- Settings --
--------------
local user_opts = {
	-- General Options
	exec       = 'subliminal',
	cache_dir  = '',
	workers    = 4,
	debug      = false,
	autostart  = false,

	-- Languages
	language_1 = 'en',
	language_2 = '',
	language_3 = '',

	-- Provider Log-ins
	addic7ed_username      = '',
	addic7ed_password      = '',
	legendastv_username    = '',
	legendastv_password    = '',
	opensubtitles_username = '',
	opensubtitles_password = '',
}


----------------
-- Subliminal --
----------------
local function add_args(args, ...)
	for _, option in ipairs({...}) do
		if is_empty(option) then return #args end
	end
	for _, option in ipairs({...}) do
		args[#args+1] = tostring(option)
	end
	return #args
end

local function create_command()
	local args = {}   -- https://subliminal.readthedocs.io/en/latest/user/cli.html
	-- General Options
	add_args(args, user_opts.exec)
	add_args(args, '--cache-dir', user_opts.cache_dir)
	add_args(args, '--addic7ed',      user_opts.addic7ed_username,      user_opts.addic7ed_password)
	add_args(args, '--legendastv',    user_opts.legendastv_username,    user_opts.legendastv_password)
	add_args(args, '--opensubtitles', user_opts.opensubtitles_username, user_opts.opensubtitles_password)
	add_args(args, user_opts.debug and '--debug' or '')
	-- Download Options
	add_args(args, 'download')
	add_args(args, '-w', user_opts.workers)
	add_args(args, '-l', user_opts.language_1)
	add_args(args, '-l', user_opts.language_2)
	add_args(args, '-l', user_opts.language_3)
	add_args(args, user_opts.debug and '-v' or '')
	-- Output
	add_args(args, mp.get_property('path', ''))
	return args
end

local function download_sub(source)
	opt.read_options(user_opts, mp.get_script_name())
	msg.debug("Subliminal subtitle download started", source)
	run_subprocess(create_command())
	mp.commandv('async', 'rescan_external_files', 'reselect') 
end


---------------
-- Listeners --
---------------
mp.register_script_message(mp.get_script_name() .. "-start", function()
	download_sub('manually.')
end)

mp.register_event('file-loaded', function()
	if user_opts.autostart then
		mp.add_timeout(1, download_sub('automatically.'))
	else
		msg.debug("Subliminal subtitle auto-download disabled.")
	end
end)
