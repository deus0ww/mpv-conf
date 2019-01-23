-- deus0ww - 2019-01-22

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

local function run_subprocess(command, name, detached)
	if is_empty(command) then return false end
	local subprocess_name, subprocess = name and name or command[1], detached and utils.subprocess_detached or utils.subprocess
	local timer_start, success, status = os.time(), false, ''
	msg.info('Subprocess -', subprocess_name, '- Starting...')
	local res = subprocess({args=command})
	if is_empty(res) then
		success, status  = true, '- Completed with Unknown Status or Was Detached'
	elseif res.status < 0 then
		success = false
		if     res.error == 'killed' then status = res.killed_by_us and '- Killed by Us' or '- Killed, but Not by Us'
		elseif res.error == 'init'   then status = '- Failed to Initialize'
		else                              status = '- Failed' end
		msg.info('Subprocess -', subprocess_name, '- Command:', utils.to_string(command))
	elseif res.status > 0 then
		success = false
		if res.status == 124 or res.status == 137 or res.status == 143 then -- timer: timed-out(124), killed(128+9), or terminated(128+15)
			 status  = '- Timed Out'
		else status  = '- Completed Abnormally' end
		msg.info('Subprocess -', subprocess_name, '- Command:', utils.to_string(command))
	else
		success, status  = true, '- Completed'
	end
	-- msg.info('Subprocess -', subprocess_name, '- Command:', utils.to_string(command))
	if res.stdout and res.stdout ~= '' then msg.info('Subprocess', subprocess_name, '- Stdout:', res.stdout) end
	msg.info('Subprocess -', subprocess_name, status, '- Status:', res.status, '- Time:', ('%ds'):format(os.difftime(os.time(), timer_start)))
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
		if option == nil or option == '' then return #args end
	end
	for _, option in ipairs({...}) do
		args[#args+1]=option
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
	add_args(args, mp.get_property('path'))
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
