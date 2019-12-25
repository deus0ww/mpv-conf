-- deus0ww - 2019-12-25

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'

local host_profile = {
	['WW-MP2008']  = 'ww-macpro-2008',
	['WW-MBP2009'] = 'ww-mbp-2009',
	['WW-MBP2012'] = 'ww-mbp-2012',
	['default']    = 'ww-pc',
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
	local profile  = host_profile[hostname] or host_profile['default']
	msg.debug('Hostname:', hostname, '- Profile:', profile)
	mp.commandv('apply-profile', profile)
end

apply_profile()