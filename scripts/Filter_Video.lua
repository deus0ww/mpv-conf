-- deus0ww - 2019-10-31

local mp      = require 'mp'
local utils   = require 'mp.utils'

local filter_list = {}
local function add(filter) filter_list[#filter_list+1] = filter end

add({
	name = 'Deinterlace',
	filter_type = 'video',
	filters = {
		'bwdif=mode=0:deint=all:parity=auto',
		'bwdif=mode=1:deint=all:parity=auto',
    	'bwdif=mode=0:deint=all:parity=tff',
    	'bwdif=mode=1:deint=all:parity=tff',
    	'bwdif=mode=0:deint=all:parity=bff',
    	'bwdif=mode=1:deint=all:parity=bff',
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
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.02'):gsub('B', '0.04'):gsub('S', '5')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.04'):gsub('B', '0.08'):gsub('S', '5')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.08'):gsub('B', '0.16'):gsub('S', '7')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.16'):gsub('B', '0.32'):gsub('S', '9')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.32'):gsub('B', '0.64'):gsub('S', '11')),
	},
})
-- Too Blurred:  hqdn3d
-- Not Temporal: removegrain
-- Not Realtime: bm3d, dctdnoiz, fftdnoiz, nlmeans, owdenoise, vaguedenoiser

add({
	name = 'Noise',
	filter_type = 'video',
	filters = {
		'noise=c0_strength=02:all_flags=t',
		'noise=c0_strength=04:all_flags=t',
		'noise=c0_strength=06:all_flags=t',
		'noise=c0_strength=08:all_flags=t',
		'noise=c0_strength=12:all_flags=t',
		'noise=c0_strength=16:all_flags=t',
		'noise=c0_strength=24:all_flags=t',
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
