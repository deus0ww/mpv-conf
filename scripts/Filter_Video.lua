-- deus0ww - 2019-06-26

local mp      = require 'mp'
local utils   = require 'mp.utils'

local filter_list = {}
local function add(filter) filter_list[#filter_list+1] = filter end

add({
	name = 'Deinterlace',
	filter_type = 'video',
	filters = {
		'bwdif=parity=auto:deint=all',
    	'bwdif=parity=tff:deint=all',
    	'bwdif=parity=bff:deint=all',
	},
})

add({
	name = 'PostProcess',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
		'pp=ac',
		'pp=ac/autolevels',
	},
})

add({
	name = 'DenoiseVideo',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
		'atadenoise=0a=0.02:1b=0.02:2b=0.02:s=5',
		'atadenoise=0a=0.04:1b=0.04:2b=0.04:s=5',
		'atadenoise=0a=0.08:1b=0.08:2b=0.08:s=7',
		-- Not Temporal: removegrain
		-- Too Blurred:  hqdn3d
		-- Too Slow:     bm3d, dctdnoiz, fftdnoiz, nlmeans, owdenoise, vaguedenoiser
	},
})

add({
	name = 'Noise',
	filter_type = 'video',
	filters = {
		'noise=c0_strength=04:all_flags=t',
		'noise=c0_strength=06:all_flags=t',
		'noise=c0_strength=08:all_flags=t',
		'noise=c0_strength=12:all_flags=t',
		'noise=c0_strength=16:all_flags=t',
		'noise=c0_strength=24:all_flags=t',
		'noise=c0_strength=32:all_flags=t',
	},
})

add({
	name = 'Invert',
	filter_type = 'video',
	filters = {
    	'negate',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.command_native({'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or ''})
end)
