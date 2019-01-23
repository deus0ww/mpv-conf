-- deus0ww - 2019-01-22

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'
local insert  = table.insert

local filter_list = {}

insert(filter_list, {
	name = 'Format',
	default_on_load = true,
	reset_on_load = false,
	filter_type = 'audio',
	filters = {
		'format=doublep',
	},
})

insert(filter_list, {
	name = 'ExtraStereo',
	filter_type = 'audio',
	filters = {
		'extrastereo=m=1.5',
		'extrastereo=m=2.0',
		'extrastereo=m=2.5',
	},
})

insert(filter_list, {
	name = 'Compressor',
	filter_type = 'audio',
	filters = {
		'acompressor=threshold=-16dB:ratio=4:attack=25:release=250:makeup=5dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=8:attack=25:release=250:makeup=5dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=16:attack=25:release=250:makeup=5dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=20:attack=25:release=250:makeup=5dB:knee=8dB',
	},
})

insert(filter_list, {
	name = 'Normalize',
	filter_type = 'audio',
	filters = {
		'dynaudnorm=f=1000:m=20',
	},
})

insert(filter_list, {
	name = 'ScaleTempo',
	filter_type = 'audio',
	filters = {
		'scaletempo=stride=9:overlap=0.9:search=8',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.commandv('async', 'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or '')
end)
