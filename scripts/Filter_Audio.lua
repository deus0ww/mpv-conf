-- deus0ww - 2019-02-20

local mp      = require 'mp'
local utils   = require 'mp.utils'
local insert  = table.insert

local filter_list = {}

insert(filter_list, {
	name = 'Format',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = true,
	filters = {
		'format=doublep',
	},
})

insert(filter_list, {
	name = 'ExtraStereo',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = true,
	filters = {
		'extrastereo=m=1.25',
		'extrastereo=m=1.50',
		'extrastereo=m=1.75',
		'extrastereo=m=2.00',
	},
})

insert(filter_list, {
	name = 'Compressor',
	filter_type = 'audio',
	filters = {
		'acompressor=threshold=-16dB:ratio=04:attack=24:release=240:makeup=2dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=08:attack=24:release=240:makeup=2dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=12:attack=24:release=240:makeup=2dB:knee=8dB',
		'acompressor=threshold=-16dB:ratio=16:attack=24:release=240:makeup=2dB:knee=8dB',
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
		'scaletempo=stride=9:overlap=0.9:search=28',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.commandv('async', 'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or '')
end)
