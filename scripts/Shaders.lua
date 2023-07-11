-- deus0ww - 2023-07-11

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local opts = {
	enabled          = false,    -- Master switch to enable/disable shaders
	set_timer        = 0,
	hifps_threshold  = 31,

	default_index    = 1,        -- Default shader set
	auto_switch      = true,     -- Auto switch shader preset base on path

	always_fs_scale  = true,     -- Always set scale relative to fullscreen resolution

	preset_1_enabled = true,     -- Enable this preset
	preset_1_path    = 'anime',  -- Path search string (Lua pattern)
	preset_1_index   = 3,        -- Shader set index to enable

	preset_2_enabled = true,
	preset_2_path    = 'cartoon',
	preset_2_index   = 3,

	preset_3_enabled = false,
	preset_3_path    = '%[.+%]',
	preset_3_index   = 3,
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
		['dscale'] = 'haasnsoft',
		['sigmoid-upscaling'] = 'yes',
	}
end

local function is_high_fps()
	return props['container-fps']    > opts.hifps_threshold or 
		   (mp.get_property_native('estimated-vf-fps') or 0) > opts.hifps_threshold
end
local function is_low_fps() return props['container-fps'] > 0 and not is_high_fps() end
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
local a4k             = {
	denoise_1         = a4k_path .. 'Anime4K_Denoise_Heavy_CNN_L_low.glsl',
	denoise_2         = a4k_path .. 'Anime4K_Denoise_Heavy_CNN_L_mid.glsl',
	denoise_3         = a4k_path .. 'Anime4K_Denoise_Heavy_CNN_L_high.glsl',
	denoise_4         = a4k_path .. 'Anime4K_Denoise_Heavy_CNN_L.glsl',

	restore_1         = a4k_path .. 'Anime4K_Restore_CNN_S.glsl',
	restore_2         = a4k_path .. 'Anime4K_Restore_CNN_M.glsl',
	restore_3         = a4k_path .. 'Anime4K_Restore_CNN_L.glsl',
	restore_1s        = a4k_path .. 'Anime4K_Restore_CNN_Soft_S.glsl',
	restore_2s        = a4k_path .. 'Anime4K_Restore_CNN_Soft_M.glsl',
	restore_3s        = a4k_path .. 'Anime4K_Restore_CNN_Soft_L.glsl',
}

-- Contrast Adaptive Sharpening
local cas_path        = shaders_path .. 'cas/'
local cas             = {
	luma              = cas_path .. 'CAS_luma.glsl',
	rgb               = cas_path .. 'CAS_rgb.glsl',
}

-- igv's - https://gist.github.com/igv , https://github.com/igv/FSRCNN-TensorFlow
local igv_path        = shaders_path .. 'igv/'
local igv             = { 
	fsrcnnx_8         = igv_path .. 'FSRCNNX_x2_8-0-4-1.glsl',
	fsrcnnx_8l        = igv_path .. 'FSRCNNX_x2_8-0-4-1_LineArt.glsl', 
	fsrcnnx_16        = igv_path .. 'FSRCNNX_x2_16-0-4-1.glsl',
	fsrcnnx_16e       = igv_path .. 'FSRCNNX_x2_16-0-4-1_enhance.glsl',
	fsrcnnx_16l       = igv_path .. 'FSRCNNX_x2_16-0-4-1_anime_enhance.glsl',
	
	krig              = igv_path .. 'KrigBilateral.glsl',
	sssr              = igv_path .. 'SSimSuperRes.glsl',
	ssds              = igv_path .. 'SSimDownscaler.glsl',
	asharpen          = igv_path .. 'adaptive-sharpen.glsl',
	asharpen_luma_low = igv_path .. 'adaptive-sharpen_luma_low.glsl',
	asharpen_luma_high= igv_path .. 'adaptive-sharpen_luma_high.glsl',
}

-- agyild's - https://gist.github.com/agyild
local amd_path        = shaders_path .. 'agyild/amd/'
local amd             = {
	cas               = amd_path .. 'CAS.glsl',
	cas_scaled        = amd_path .. 'CAS-scaled.glsl',
	fsr               = amd_path .. 'FSR.glsl',
	fsr_easu          = amd_path .. 'FSR_EASU.glsl',
	fsr_rcas_low      = amd_path .. 'FSR_RCAS_low.glsl',
	fsr_rcas_mid      = amd_path .. 'FSR_RCAS_mid.glsl',
	fsr_rcas_high     = amd_path .. 'FSR_RCAS_high.glsl',
}

-- bjin's - https://github.com/bjin/mpv-prescalers
local ravu_path       = shaders_path .. 'ravu/'
local ravu            = {
	lite_r2           = ravu_path .. 'ravu-lite-r2.hook',
	lite_r3           = ravu_path .. 'ravu-lite-r3.hook',
	lite_r4           = ravu_path .. 'ravu-lite-r4.hook',
	zoom_r2           = ravu_path .. 'ravu-zoom-r2.hook',
	zoom_r3           = ravu_path .. 'ravu-zoom-r3.hook',
}



-------------------
--- Shader Sets ---
-------------------
local sets = {}

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale() + 0.1
	if is_high_fps() then scale = math.max(0, scale - 1.5) end
	s[#s+1] = ({nil,      a4k.restore_1s, a4k.restore_2s, a4k.restore_2s, a4k.restore_2s, a4k.restore_3s })[math.min(math.floor(scale), 6)]
	s[#s+1] = ({nil,      ravu.lite_r4,   ravu.lite_r4,   igv.fsrcnnx_8,  igv.fsrcnnx_8,  igv.fsrcnnx_16 })[math.min(math.floor(scale), 6)]
	s[#s+1] = ({igv.krig, igv.krig,       igv.krig,       igv.krig,       igv.krig,       igv.krig       })[math.min(math.floor(scale), 6)]
	s[#s+1] = amd.fsr_easu
	s[#s+1] = amd.fsr_rcas_high
	s[#s+1] = is_rgb() and igv.asharpen or nil
	return { shaders = s, options = o, label = 'Live - FSRCNNX/RAVU + FSR_EASU + RCAS(high)' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale() + 0.1
	if is_high_fps() then scale = math.max(0, scale - 1.5) end
	s[#s+1] = ({nil,      a4k.restore_2s, a4k.restore_1s, a4k.restore_2s, a4k.restore_2s, a4k.restore_3s })[math.min(math.floor(scale), 6)]
	s[#s+1] = ({nil,      ravu.lite_r4,   ravu.lite_r4,   igv.fsrcnnx_8,  igv.fsrcnnx_8,  igv.fsrcnnx_16e})[math.min(math.floor(scale), 6)]
	s[#s+1] = ({igv.krig, igv.krig,       igv.krig,       igv.krig,       igv.krig,       igv.krig       })[math.min(math.floor(scale), 6)]
	s[#s+1] = amd.fsr_easu
	s[#s+1] = scale > 1.5 and igv.asharpen_luma_low or nil
	s[#s+1] = scale > 2.5 and amd.fsr_rcas_mid or nil
	s[#s+1] = is_rgb() and igv.asharpen or nil
	return { shaders = s, options = o, label = 'Rendered - FSRCNNX/RAVU + FSR_EASU + AS(low) + RCAS(mid)' }
end

sets[#sets+1] = function()
	local s, o, scale = {}, default_options(), get_scale() + 0.1
	if is_high_fps() then scale = math.max(0, scale - 1.5) end
	s[#s+1] = ({nil,      a4k.restore_1s, a4k.restore_2s, a4k.restore_2s, a4k.restore_2s, a4k.restore_3s })[math.min(math.floor(scale), 6)]
	s[#s+1] = ({nil,      ravu.lite_r4,   ravu.lite_r4,   igv.fsrcnnx_8l, igv.fsrcnnx_8l, igv.fsrcnnx_16l})[math.min(math.floor(scale), 6)]
	s[#s+1] = ({igv.krig, igv.krig,       igv.krig,       igv.krig,       igv.krig,       igv.krig       })[math.min(math.floor(scale), 6)]
	s[#s+1] = amd.fsr_easu
	s[#s+1] = scale > 1.5 and igv.asharpen_luma_high or nil
	s[#s+1] = is_rgb() and igv.asharpen or nil
	return { shaders = s, options = o, label = 'Drawn - FSRCNNX/RAVU + FSR_EASU + AS(high)' }
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
local timer = mp.add_timeout(opts.set_timer, function() set_shaders(true) end)
timer:kill()
local function observe_prop(k, v)
	-- msg.debug(k, props[k], '->', utils.to_string(v))
	props[k] = v or -1
	
	if is_initialized() then
		msg.debug('Resetting Timer')
		timer:kill()
		timer:resume()
	end
end

local function set_default_index()
	if not opts.auto_switch then return end
	local path = mp.get_property_native('path', ''):lower()
	current_index = opts.default_index
	if opts.preset_1_enabled and path:find(opts.preset_1_path) ~= nil then current_index = opts.preset_1_index end
	if opts.preset_2_enabled and path:find(opts.preset_2_path) ~= nil then current_index = opts.preset_2_index end
	if opts.preset_3_enabled and path:find(opts.preset_3_path) ~= nil then current_index = opts.preset_3_index end
end

local function start()
	reset()
	set_default_index()
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
