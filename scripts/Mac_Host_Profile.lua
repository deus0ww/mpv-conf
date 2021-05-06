-- deus0ww - 2021-05-07

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
	local res = mp.command_native({ name = 'subprocess', args = {'uname', '-s'}, playback_only = false, capture_stdout = true, capture_stderr = true, })
	return (res and res.stdout and res.stdout:lower():find('darwin') ~= nil) and OS_MAC or OS_NIX
end
local OPERATING_SYSTEM = get_os()

local host_profile = {
	['WW-MP2008']  = 'ww-macpro-2008',
	['WW-MBP2009'] = 'ww-mbp-2009',
	['WW-MBP2012'] = 'ww-mbp-2012',
	['WW-MINI']    = 'ww-mini',
	['MAC']        = 'ww-mac',
	['WIN']        = 'ww-pc',
	['NIX']        = 'ww-nix',
	['NA']         = 'ww-nix',
}

local function get_hostname()
	local res = mp.command_native({ name = 'subprocess', args = {'hostname', '-s'}, playback_only = false, capture_stdout = true, capture_stderr = true, })
	return (res and res.stdout) and res.stdout:match("([^\r\n]*)[\r\n]?") or 'NA'
end
local HOSTNAME = get_hostname()

local function apply_profile()
	local profile  = host_profile[HOSTNAME] or host_profile[OPERATING_SYSTEM] or host_profile['NA']
	msg.debug('Hostname:', HOSTNAME, '- OS:', OPERATING_SYSTEM,'- Profile:', profile)
	mp.commandv('apply-profile', profile)
end
apply_profile()