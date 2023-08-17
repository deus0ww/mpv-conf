-- deus0ww - 2023-08-05

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local opts = {
	enabled               = false,      -- Master switch to enable/disable shaders
	always_fs_scale       = true,       -- Always set scale relative to fullscreen resolution
	set_timer             = 0,

	auto_switch           = true,       -- Auto switch shader preset base on path
	default_index         = 1,          -- Default shader set

	hifps_threshold       = 31,
	lowfps_threshold      = 10,

	preset_1_enabled      = true,
	preset_1_path         = 'rendered',
	preset_1_index        = 2,

	preset_2_enabled      = true,       -- Enable this preset
	preset_2_path         = 'anime',    -- Path search string (Lua pattern)
	preset_2_index        = 3,          -- Shader set index to enable

	preset_3_enabled      = true,
	preset_3_path         = 'cartoon',
	preset_3_index        = 3,

	preset_4_enabled      = false,
	preset_4_path         = '%[.+%]',
	preset_4_index        = 3,

	preset_lowfps_enabled = true,       -- Target frame time: 90ms
	preset_lowfps_index   = 4,
	
	preset_hifps_enabled  = true,       -- Target frame time: 15ms
	preset_hifps_index    = 5,
	
	preset_rgb_enabled    = true,
	preset_rgb_index      = 6,
}

local current_index, enabled
local function on_opts_update()
	current_index  = opts.default_index
	enabled        = opts.enabled
end
opt.read_options(opts, mp.get_script_name(), on_opts_update)
on_opts_update()



------------------
--- Properties ---
------------------
local props, last_shaders
local function reset()
	props = {
		['dwidth']                   = -1,
		['dheight']                  = -1,

		['display-width']            = -1,
		['display-height']           = -1,

		['osd-dimensions/w']         = -1,
		['osd-dimensions/h']         = -1,
		['osd-dimensions/mt']        = -1,
		['osd-dimensions/mb']        = -1,
		['osd-dimensions/ml']        = -1,
		['osd-dimensions/mr']        = -1,

		['container-fps']            = -1,
		['video-params/rotate']      = -1,
		['video-params/colormatrix'] = '',
	}
end
reset()

local function is_initialized()
	return ((props['dwidth']                   >   0) and
			(props['dheight']                  >   0) and

			(props['display-width']            >   0) and
			(props['display-height']           >   0) and

			(props['osd-dimensions/w']         >   0) and
			(props['osd-dimensions/h']         >   0) and
			(props['osd-dimensions/mt']        >=  0) and
			(props['osd-dimensions/mb']        >=  0) and
			(props['osd-dimensions/ml']        >=  0) and
			(props['osd-dimensions/mr']        >=  0) and

			(props['container-fps']            >   0) and
			(props['video-params/rotate']      >=  0) and
			(props['video-params/colormatrix'] ~= '') and
			true)
end



--------------------
--- Shader Utils ---
--------------------
local function default_options()
	return {
		['sigmoid-upscaling'] = 'yes',
	}
end

local function get_fps() return math.floor(math.max(props['container-fps'], mp.get_property_native('estimated-vf-fps', 0) + 0.5 )) end

local function is_high_fps()return get_fps() >= opts.hifps_threshold  end
local function is_low_fps() return get_fps() <= opts.lowfps_threshold end
local function is_hdr()     return props['video-params/colormatrix']:find('bt.2020') ~= nil end
local function is_rgb()     return props['video-params/colormatrix']:find('rgb')     ~= nil end
local function get_scale()
	local scaled_width, scaled_height, video_width, video_height = 0, 0, props['dwidth'], props['dheight']
	if opts.always_fs_scale then
		scaled_width  = props['display-width']
		scaled_height = props['display-height'] 
		return math.min(scaled_width/video_width, scaled_height/video_height)
	else
		scaled_width  = props['osd-dimensions/w'] - props['osd-dimensions/ml'] - props['osd-dimensions/mr']
		scaled_height = props['osd-dimensions/h'] - props['osd-dimensions/mt'] - props['osd-dimensions/mb']
		return math.sqrt((scaled_width * scaled_height) / (video_width * video_height))
    end
end
local function format_status()
	local temp = (opts.always_fs_scale and 'FS ' or '') .. ('Scale: %.3f'):format(get_scale())
	if is_high_fps() then temp = temp .. ' HighFPS' end
	if is_low_fps()  then temp = temp .. ' LowFPS'  end
	if is_hdr()      then temp = temp .. ' HDR' end
	if is_rgb()      then temp = temp .. ' RGB' end
	return temp
end



--------------------
--- Shader Files ---
--------------------
local shaders_path = '~~/shaders/'

-- Anime4K - https://github.com/bloc97/Anime4K/
local a4k_path        = shaders_path .. 'anime4k/'
local restore         = {
	r1                = a4k_path .. 'Anime4K_Restore_CNN_S.glsl',
	r2                = a4k_path .. 'Anime4K_Restore_CNN_M.glsl',
	r3                = a4k_path .. 'Anime4K_Restore_CNN_L.glsl',
	r4                = a4k_path .. 'Anime4K_Restore_CNN_VL.glsl',
	r1s               = a4k_path .. 'Anime4K_Restore_CNN_Soft_S.glsl',
	r2s               = a4k_path .. 'Anime4K_Restore_CNN_Soft_M.glsl',
	r3s               = a4k_path .. 'Anime4K_Restore_CNN_Soft_L.glsl',
	r4s               = a4k_path .. 'Anime4K_Restore_CNN_Soft_VL.glsl',
}

-- FSR by agyild - https://gist.github.com/agyild
local fsr_path        = shaders_path .. 'fsr/'
local fsr             = {
	fsr               = fsr_path .. 'FSR.glsl',
	easu              = fsr_path .. 'FSR_EASU.glsl',
	rcas_low          = fsr_path .. 'FSR_RCAS_low.glsl',
	rcas_high         = fsr_path .. 'FSR_RCAS_high.glsl',
}

-- FSRCNNX by igv - https://github.com/igv/FSRCNN-TensorFlow
local fsrcnnx_path    = shaders_path .. 'fsrcnnx/'
local fsrcnnx         = {
	r8                = fsrcnnx_path .. 'FSRCNNX_x2_8-0-4-1.glsl',
	r8l               = fsrcnnx_path .. 'FSRCNNX_x2_8-0-4-1_LineArt.glsl', 
	r16               = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1.glsl',
	r16e              = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1_enhance.glsl',
	r16l              = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1_anime_enhance.glsl',
}

-- RAVU by bjin - https://github.com/bjin/mpv-prescalers
local ravu_luma_path  = shaders_path .. 'ravu/luma/'
local ravu_rgb_path   = shaders_path .. 'ravu/rgb/'
local ravu            = {
	lite              = {
		r2            = ravu_luma_path .. 'ravu-lite-r2.hook',
		r3            = ravu_luma_path .. 'ravu-lite-r3.hook',
		r4            = ravu_luma_path .. 'ravu-lite-r4.hook',
		r2s           = ravu_luma_path .. 'ravu-lite-ar-r2.hook',
		r3s           = ravu_luma_path .. 'ravu-lite-ar-r3.hook',
		r4s           = ravu_luma_path .. 'ravu-lite-ar-r4.hook',
	},
	zoom              = {
		r2            = ravu_luma_path .. 'ravu-zoom-r2.hook',
		r3            = ravu_luma_path .. 'ravu-zoom-r3.hook',
		r2s           = ravu_luma_path .. 'ravu-zoom-ar-r2.hook',
		r3s           = ravu_luma_path .. 'ravu-zoom-ar-r3.hook',
		rgb_r2        = ravu_rgb_path  .. 'ravu-zoom-r2-rgb.hook',
		rgb_r3        = ravu_rgb_path  .. 'ravu-zoom-r3-rgb.hook',
		rgb_r2s       = ravu_rgb_path  .. 'ravu-zoom-ar-r2-rgb.hook',
		rgb_r3s       = ravu_rgb_path  .. 'ravu-zoom-ar-r3-rgb.hook',
	},
}

-- igv's - https://gist.github.com/igv
local igv_path        = shaders_path .. 'igv/'
local igv             = {
	sssr              = igv_path .. 'SSimSuperRes.glsl',
	ssds              = igv_path .. 'SSimDownscaler.glsl',
	as_rgb            = igv_path .. 'adaptive-sharpen.glsl',
	as_luma           = igv_path .. 'adaptive-sharpen_luma.glsl',
}

-- Chroma Scalers by Artoriuz + igv - https://github.com/Artoriuz/glsl-joint-bilateral
local bilateral_path  = shaders_path .. 'bilateral/'
local bilateral       = {
	r1                = bilateral_path .. 'FastBilateral.glsl',
	r2                = bilateral_path .. 'JointBilateral.glsl',
	r3                = bilateral_path .. 'KrigBilateral.glsl',
}



-------------------
--- Shader Sets ---
-------------------
local sets = {}

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = ({nil,          nil,          nil,          restore.r1s, restore.r2s,  restore.r3s })[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ({nil,          fsrcnnx.r8,   fsrcnnx.r8,   fsrcnnx.r8,  fsrcnnx.r16,  fsrcnnx.r16 })[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ravu.zoom.r3s
	s[#s+1] = igv.as_luma
	s[#s+1] = ({bilateral.r2, bilateral.r1, bilateral.r1, bilateral.r2 })[math.min(math.floor(scale + 0.1), 4)]
	return { shaders = s, options = o, label = 'Live - FSRCNNX + RAVU_ZOOM + AS' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = ({nil,          nil,          nil,          restore.r1s, restore.r2s,  restore.r3s })[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ({nil,          fsrcnnx.r8,   fsrcnnx.r8,   fsrcnnx.r8,  fsrcnnx.r16e, fsrcnnx.r16e})[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ravu.zoom.r3s
	s[#s+1] = igv.as_luma
	s[#s+1] = ({bilateral.r2, bilateral.r1, bilateral.r1, bilateral.r2 })[math.min(math.floor(scale + 0.1), 4)]
	return { shaders = s, options = o, label = 'Rendered - FSRCNNX + RAVU_ZOOM + AS' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = ({nil,          nil,          nil,          restore.r1s, restore.r2s,  restore.r3s })[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ({nil,          fsrcnnx.r8l,  fsrcnnx.r8l,  fsrcnnx.r8l, fsrcnnx.r16l, fsrcnnx.r16l})[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ravu.zoom.r3s
	s[#s+1] = igv.as_luma
	s[#s+1] = ({bilateral.r2, bilateral.r1, bilateral.r1, bilateral.r2 })[math.min(math.floor(scale + 0.1), 4)]
	return { shaders = s, options = o, label = 'Drawn - FSRCNNX + RAVU_ZOOM + AS' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = fsrcnnx.r16
	s[#s+1] = ravu.zoom.r3s
	s[#s+1] = igv.as_luma
	s[#s+1] = bilateral.r3
	return { shaders = s, options = o, label = 'LowFPS - FSRCNNX + RAVU_ZOOM + AS' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = ({nil, ravu.lite.r2s, nil, fsrcnnx.r8, fsrcnnx.r8, fsrcnnx.r8 })[math.min(math.floor(scale + 0.1), 6)]
	s[#s+1] = ravu.zoom.r2s
	return { shaders = s, options = o, label = 'HighFPS - FSRCNNXRAVU_LITE + RAVU_ZOOM' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = ravu.zoom.rgb_r3s
	s[#s+1] = igv.as_rgb
	return { shaders = s, options = o, label = 'RGB - AS(low)' }
end



--------------------
--- MPV Commands ---
--------------------
local function show_osd(no_osd, label)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set %d: %s'):format(enabled and '■' or '□', current_index, (label or 'n/a') .. ' [' .. format_status() .. ']'), 6)
end

local function mpv_set_options(options)
	msg.debug('Setting Options:', utils.to_string(options))
	for name, value in pairs(options) do
		mp.commandv('set', name, value)
	end
end

local function mpv_clear_options()
	mpv_set_options(default_options())
end

local function mpv_clear_shaders()
	msg.debug('Clearing Shaders.')
	mp.commandv('change-list', 'glsl-shaders', 'clr', '')
end

local function mpv_set_shaders(shaders)
	msg.debug(format_status())
	msg.debug('Setting Shaders:', utils.to_string(shaders))
	mp.commandv('change-list', 'glsl-shaders', 'set', table.concat(shaders, ':'))
end

local function clear_shaders(no_osd)
	if not is_initialized() then 
		msg.debug('Setting Shaders: skipped - properties not available.')
		return
	end
	local shaders = sets[current_index]()
	show_osd(no_osd, shaders.label)
	if last_shaders == nil then
		msg.debug('Clearing Shaders: skipped - no shader found.')
		return
	end
	last_shaders = nil
	mpv_clear_options()
	mpv_clear_shaders()
end

local function set_shaders(no_osd)
	if not is_initialized() then 
		msg.debug('Setting Shaders: skipped - properties not available.')
		return
	end
	local shaders = sets[current_index]()
	show_osd(no_osd, shaders.label)
	if not enabled then
		msg.debug('Setting Shaders: skipped - disabled.')
		return
	end
	local s, _ = utils.to_string(shaders)
	if last_shaders == s then 
		msg.debug('Setting Shaders: skipped - shaders unchanged.')
		return
	end
	last_shaders = s
	mpv_set_options(shaders.options)
	mpv_set_shaders(shaders.shaders)
end



--------------------------
--- Observers & Events ---
--------------------------
local function set_default_index()
	if not opts.auto_switch then return end
	local path = mp.get_property_native('path', ''):lower()
	current_index = opts.default_index
	if opts.preset_4_enabled and path:find(opts.preset_4_path) ~= nil then current_index = opts.preset_4_index end
	if opts.preset_3_enabled and path:find(opts.preset_3_path) ~= nil then current_index = opts.preset_3_index end
	if opts.preset_2_enabled and path:find(opts.preset_2_path) ~= nil then current_index = opts.preset_2_index end
	if opts.preset_1_enabled and path:find(opts.preset_1_path) ~= nil then current_index = opts.preset_1_index end
	if opts.preset_lowfps_enabled and is_low_fps()  then current_index = opts.preset_lowfps_index end
	if opts.preset_rgb_enabled    and is_rgb()      then current_index = opts.preset_rgb_index    end
	if opts.preset_hifps_enabled  and is_high_fps() then current_index = opts.preset_hifps_index  end
end

local timer = mp.add_timeout(opts.set_timer, function() set_shaders(true) end)
timer:kill()
local firstrun = true
local function observe_prop(k, v)
	-- msg.debug(k, props[k], '->', utils.to_string(v))
	props[k] = v or -1
	
	if is_initialized() then
		if firstrun then set_default_index(); firstrun = false end
		msg.debug('Resetting Timer')
		timer:kill()
		timer:resume()
	end
end


local function start()
	reset()
	firstrun = true
	for prop, _ in pairs(props) do
		mp.observe_property(prop, 'native', observe_prop)
	end
end
mp.register_event('file-loaded', start)



----------------
--- Bindings ---
----------------
local function cycle_set_up(no_osd)
	msg.debug('Shader - Up:', current_index)
	if not is_initialized() then return end
	current_index = (current_index % #sets) + 1
	set_shaders(no_osd)
end

local function cycle_set_dn(no_osd)
	msg.debug('Shader - Down:', current_index)
	if not is_initialized() then return end
	current_index = ((current_index - 2) % #sets) + 1
	set_shaders(no_osd)
end

local function toggle_set(no_osd)
	msg.debug('Shader - Toggling:', current_index)
	if not is_initialized() then return end
	enabled = not enabled
	set_default_index()
	if enabled then set_shaders(no_osd) else clear_shaders(no_osd) end
end

local function enable_set(no_osd)
	msg.debug('Shader - Enabling:', current_index)
	if not is_initialized() then return end
	enabled = true
	set_default_index()
	set_shaders(no_osd)
end

local function disable_set(no_osd)
	msg.debug('Shader - Disabling:', current_index)
	if not is_initialized() then return end
	enabled = false
	clear_shaders(no_osd)
end

local function show_set(no_osd)
	msg.debug('Shader - Showing:', current_index)
	if not is_initialized() then return end
	show_osd(no_osd, sets[current_index]().label)
end

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd  == 'yes') end)
mp.register_script_message('Shaders-show',    function(no_osd) show_set(no_osd     == 'yes') end)
