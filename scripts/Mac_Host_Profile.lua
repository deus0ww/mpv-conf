-- deus0ww - 2020-01-31

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'

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

local host_profile = {
	['WW-MP2008']  = 'ww-macpro-2008',
	['WW-MBP2009'] = 'ww-mbp-2009',
	['WW-MBP2012'] = 'ww-mbp-2012',
	['MAC']        = 'ww-mac',
	['WIN']        = 'ww-pc',
	['NIX']        = 'ww-nix',
	['NA']         = 'ww-nix',
}

local cmd_get_hostname = { name = 'subprocess', args = {'hostname', '-s'}, playback_only = false, capture_stdout = true, capture_stderr = true, }

local function get_hostname()
	local res = mp.command_native(cmd_get_hostname)
	if res.status < 0 or #res.error_string > 0 or #res.stderr > 0 or #res.stdout == 0 then
		msg.debug('Command "hostname" failed. Command:', utils.to_string(cmd_get_hostname), 'Result:', utils.to_string(res)) 
		return 'NA'
	end
	return res.stdout:match("([^\r\n]*)[\r\n]?")
end

local function apply_profile()
	local hostname = get_hostname()
	local profile  = host_profile[hostname] or host_profile[OPERATING_SYSTEM] or host_profile['NA']
	msg.debug('Hostname:', hostname, '- OS:', OPERATING_SYSTEM,'- Profile:', profile)
	mp.commandv('apply-profile', profile)
end

apply_profile()