-- deus0ww - 2022-12-12

local mp      = require 'mp'
local utils   = require 'mp.utils'

local filter_list = {}
local function add(filter) filter_list[#filter_list+1] = filter end

add({
	name = 'Deinterlace',
	filter_type = 'video',
	filters = {
	-- Too Slow:     nnedi

	-- https://ffmpeg.org/ffmpeg-filters.html#bwdif
		-- mode: send_frame, send_field 	(send_field)
		-- parity: ttf, bff, auto			(auto)
		-- deint: all, interlaced			(all)
	-- https://ffmpeg.org/ffmpeg-filters.html#fieldmatch
		-- order: ttf, bff, auto			(auto)
		-- mode: pc, pc_n, pc_u, pc_n_ub, pcn, pcn_ub	(pc_n)
		-- combmatch: none, sc, full		(sc)
	-- https://ffmpeg.org/ffmpeg-filters.html#mpdecimate
		'bwdif=mode=send_frame',
		'lavfi=graph=[fieldmatch=mode=pc_n_ub:combmatch=full,bwdif=mode=send_frame]',
		'lavfi=graph=[fieldmatch=mode=pc_n_ub:combmatch=full,bwdif=mode=send_frame,mpdecimate]',
		'bwdif',
		'lavfi=graph=[fieldmatch=mode=pc_n_ub:combmatch=full,bwdif]',
		'lavfi=graph=[fieldmatch=mode=pc_n_ub:combmatch=full,bwdif,mpdecimate]',
	},
})

add({
	name = 'PostProcess',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#pp
		'pp=ac',
		'pp=ac/autolevels',
	},
})

add({
	name = 'DenoiseVideo',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#median
	-- http://avisynth.nl/index.php/RemoveGrain
	-- http://web.archive.org/web/20130615165406/http://doom10.org/index.php?topic=2185.0
		'removegrain=18',
		'removegrain=17',
		'removegrain=22',
	},
})

add({
	name = 'TempDenoiseVideo',
	filter_type = 'video',
	reset_on_load = false,
	filters = {
	-- Too Blurry:   hqdn3d
	-- Too Slow:     bm3d, dctdnoiz, fftdnoiz, nlmeans, owdenoise, vaguedenoiser

	-- https://ffmpeg.org/ffmpeg-filters.html#atadenoise
		-- 0a, 1a, 2a: threshold A			(0.02)			(0 - 0.3)
		-- 0b, 1b, 2b: threshold B			(0.04)			(0 - 5)
		-- s: Frames for averaging			(9)				(5 - 129 odd-only)
		-- a: (p)arallel, (s)erial			(p)
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.02'):gsub('B', '0.04'):gsub('S', '5')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.02'):gsub('B', '0.04'):gsub('S', '7')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.02'):gsub('B', '0.04'):gsub('S', '9')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.04'):gsub('B', '0.08'):gsub('S', '5')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.04'):gsub('B', '0.16'):gsub('S', '7')),
		(('atadenoise=0a=A:0b=B:1a=A:1b=B:2a=A:2b=B:s=S'):gsub('A', '0.04'):gsub('B', '0.16'):gsub('S', '9')),
	},
})

add({
	name = 'Noise',
	filter_type = 'video',
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#noise
		-- alls, c#s: Noise strength		(0)				(0, 100)
		-- allf, c#f: (a)verage, (p)attern, (t)temporal, (u)niform
		'noise=c0_strength=02:all_flags=t',
		'noise=c0_strength=03:all_flags=t',
		'noise=c0_strength=04:all_flags=t',
		'noise=c0_strength=05:all_flags=t',
		'noise=c0_strength=06:all_flags=t',
		'noise=c0_strength=07:all_flags=t',
		'noise=c0_strength=08:all_flags=t',
	},
})

add({
	name = 'Invert',
	filter_type = 'video',
	filters = {
	-- https://ffmpeg.org/ffmpeg-filters.html#negate
    	'negate',
	},
})

mp.register_script_message('Filter_Registration_Request', function(origin)
	local filter_json, _ = utils.format_json(filter_list)
	mp.command_native({'script-message-to', origin, 'Filters_Registration', filter_json and filter_json or ''})
end)
