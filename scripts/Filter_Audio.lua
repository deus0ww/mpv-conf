-- deus0ww - 2020-02-15

local mp      = require 'mp'
local utils   = require 'mp.utils'

local filter_list = {}
local function add(filter) filter_list[#filter_list+1] = filter end

add({
	name = 'Format',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = true,
	filters = {
	-- https://mpv.io/manual/master/#audio-filters-format
		'format=float:srate=96000',
	},
})

add({
	name = 'VoicePass',
	filter_type = 'audio',
	reset_on_load = true,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#highpass
	-- https://ffmpeg.org/ffmpeg-filters.html#lowpass
		-- f: Frequency in Hz. 				(3000)
		-- p: Number of poles.				(2)
		-- t: Type band-width of filter.
		-- w: Band-width.					(0.707q)
		-- n: Normalize						(disabled)
		'lavfi=graph=[lowpass=frequency=8400,highpass=frequency=120]',
		'lavfi=graph=[lowpass=frequency=7200,highpass=frequency=240]',
		'lavfi=graph=[lowpass=frequency=6000,highpass=frequency=360]',
		'lavfi=graph=[lowpass=frequency=4800,highpass=frequency=480]',
	},
})

add({
	name = 'DenoiseAudio',
	filter_type = 'audio',
	reset_on_load = true,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#anlmdn
		-- s: Strength.						(0.00001)		(0.00001 - 10)
		-- p: Patch radius duration.		(0.002)			(0.001 - 0.1 s)
		-- r: Research radius duration.		(0.006)			(0.002 - 0.3 s)
		-- m: Smooth factor.				(11)			(1 - 15)
		'anlmdn=s=0.01:m=15',
		'anlmdn=s=0.10:m=15',
		
	-- https://ffmpeg.org/ffmpeg-filters.html#afftdn
		--'afftdn=nr=12:nf=-48',
		--'afftdn=nr=18:nf=-42',
		--'afftdn=nr=24:nf=-36',
		--'afftdn=nr=30:nf=-36',
		--'afftdn=nr=36:nf=-36',
	},
})

add({
	name = 'Crystalizer',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = false,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#crystalizer
		-- i: Intensity of effect.			(2)				(0.0 - 10.0)
		-- c: Enable Clipping.				(enabled)
		'crystalizer=i=0.5',
		'crystalizer=i=1.0',
		'crystalizer=i=2.0',
		'crystalizer=i=4.0',
	},
})

add({
	name = 'Compressor',
	filter_type = 'audio',
	reset_on_load = false,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#compand
		-- attack/decays					(0.3/0.8)		(ms)
		-- soft-knee: Curve radius			(0.01)			(dB)
		'compand=attacks=0.050:decays=0.300:soft-knee=8:points=-80/-80|-20/-20|020/0', --  2:1
		'compand=attacks=0.050:decays=0.300:soft-knee=8:points=-80/-80|-20/-20|060/0', --  4:1
		'compand=attacks=0.050:decays=0.300:soft-knee=8:points=-80/-80|-20/-20|140/0', --  8:1
		'compand=attacks=0.050:decays=0.300:soft-knee=8:points=-80/-80|-20/-20|300/0', -- 16:1
	},
})

add({
	name = 'Downmix',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = false,
	filters = { 
	-- https://ffmpeg.org/ffmpeg-filters.html#pan
		-- -3dB=0.707, -6dB=0.500, -9dB=0.353, -12dB=0.250, -15dB=0.177
		'pan="stereo| FL < 0.707*FC + 1.000*FL + 0.500*SL + 0.500*BL + 0.500*LFE | FR < 0.707*FC + 1.000*FR + 0.500*SR + 0.500*BR + 0.500*LFE"',
		'pan="stereo| FL < 0.707*FC + 1.000*FL + 0.707*SL + 0.707*BL + 0.500*LFE | FR < 0.707*FC + 1.000*FR + 0.707*SR + 0.707*BR + 0.500*LFE"', -- ATSC + LFE
		'pan="stereo| FL < 0.707*FC + 1.000*FL + 0.707*SL + 0.707*BL + 0.000*LFE | FR < 0.707*FC + 1.000*FR + 0.707*SR + 0.707*BR + 0.000*LFE"', -- ATSC
		'pan="stereo| FL < 1.000*FC + 0.707*FL + 0.500*SL + 0.500*BL + 0.000*LFE | FR < 1.000*FC + 0.707*FR + 0.500*SR + 0.500*BR + 0.000*LFE"', -- Nightmode
		
	-- https://ffmpeg.org/ffmpeg-filters.html#sofalizer
		'sofalizer=sofa=/Users/Shared/Library/mpv/sofa/ClubFritz7.sofa:interpolate=yes',
		
	-- https://ffmpeg.org/ffmpeg-filters.html#bs2b
		'bs2b=profile=jmeier',
	},
})

add({
	name = 'Normalize',
	filter_type = 'audio',
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#dynaudnorm
		-- f: Frame length.					(500)			(10 - 8000 ms)
		-- g: Gaussian window size.			(31)			(3 - 301 odd-only)
		-- p: Target Peak					(0.95)
		-- m: Max gain factor				(10)			(1.0 - 100.0)
		-- r: Target RMS					(0.0)			(0.0 - 1.0)
		'dynaudnorm=framelen=250:gausssize=11:maxgain=12:peak=0.8:targetrms=0.8',
	},
})

add({
	name = 'ExtraStereo',
	filter_type = 'audio',
	default_on_load = true,
	reset_on_load = false,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#extrastereo
		-- m: Difference coefficient.		(2.5)
		'extrastereo=m=1.25',
		'extrastereo=m=1.50',
		'extrastereo=m=1.75',
		'extrastereo=m=2.00',
	},
})

add({
	name = 'ScaleTempo',
	filter_type = 'audio',
	filters = {
	-- https://mpv.io/manual/master/#audio-filters-scaletempo[
		'scaletempo=stride=9:overlap=0.9:search=28',
		
	-- https://mpv.io/manual/master/#audio-filters-rubberband
		'rubberband=pitch=quality:transients=crisp',
		'rubberband=pitch=quality:transients=mixed',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.command_native({'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or ''})
end)
