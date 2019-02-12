-- deus0ww - 2019-02-12

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'
local insert  = table.insert

local filter_list = {}

insert(filter_list, {
	name = 'Deinterlace',
	filter_type = 'video',
	filters = {
		'bwdif=parity=auto:deint=all',
    	'bwdif=parity=tff:deint=all',
    	'bwdif=parity=bff:deint=all',
	},
})

insert(filter_list, {
	name = 'PostProcess',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
		'pp=ac',
		'pp=ac/autolevels',
	},
})

insert(filter_list, {
	name = 'PostProcessDenoise',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
		'pp=tmpnoise|100|200|400',
		'pp=tmpnoise|200|400|800',
		'pp=tmpnoise|400|800|1600',
		'pp=tmpnoise|800|1600|3200',
		'pp=tmpnoise|1600|3200|6400',
	},
})

insert(filter_list, {
	name = 'Denoise',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
		'hqdn3d=luma_spatial=0.00:chroma_spatial=0.00:luma_tmp=0.01:chroma_tmp=0.01',
		'hqdn3d=luma_spatial=0.00:chroma_spatial=0.00:luma_tmp=1.00:chroma_tmp=0.75',
		'hqdn3d=luma_spatial=0.00:chroma_spatial=0.00:luma_tmp=2.00:chroma_tmp=1.50',
		'hqdn3d=luma_spatial=0.00:chroma_spatial=0.00:luma_tmp=4.00:chroma_tmp=3.00',
		'hqdn3d=luma_spatial=0.00:chroma_spatial=0.00:luma_tmp=6.00:chroma_tmp=4.50',
		'hqdn3d=luma_spatial=1.00:chroma_spatial=0.75:luma_tmp=8.00:chroma_tmp=6.00',
		'hqdn3d=luma_spatial=2.00:chroma_spatial=1.50:luma_tmp=8.00:chroma_tmp=6.00',
		'hqdn3d=luma_spatial=4.00:chroma_spatial=3.00:luma_tmp=8.00:chroma_tmp=6.00',
	},
})

insert(filter_list, {
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

insert(filter_list, {
	name = 'Invert',
	filter_type = 'video',
	filters = {
    	'negate',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.commandv('async', 'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or '')
end)
