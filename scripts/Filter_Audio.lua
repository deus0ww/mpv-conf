-- deus0ww - 2019-03-16

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
		'format=doublep:srate=96000:channels=stereo',
	},
})

insert(filter_list, {
	name = 'DenoiseAudio',
	filter_type = 'audio',
	reset_on_load = true,
	filters = {
		'afftdn=nr=12:nf=-42',
		'afftdn=nr=18:nf=-36',
		'afftdn=nr=24:nf=-30',
	},
})

insert(filter_list, {
	name = 'HighPass',
	filter_type = 'audio',
	reset_on_load = true,
	filters = {
		'highpass=f=100',
		'highpass=f=200',
		'highpass=f=300',
	},
})

insert(filter_list, {
	name = 'LowPass',
	filter_type = 'audio',
	reset_on_load = true,
	filters = {
		'lowpass=f=6000',
		'lowpass=f=4500',
		'lowpass=f=3000',
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
		'acompressor=threshold=-25dB:ratio=02:attack=50:release=300:makeup=2dB:knee=10dB',
		'acompressor=threshold=-25dB:ratio=04:attack=50:release=300:makeup=2dB:knee=10dB',
		'acompressor=threshold=-25dB:ratio=08:attack=50:release=300:makeup=2dB:knee=10dB',
		'acompressor=threshold=-25dB:ratio=16:attack=50:release=300:makeup=2dB:knee=10dB',
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
	mp.command_native({'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or ''})
end)
