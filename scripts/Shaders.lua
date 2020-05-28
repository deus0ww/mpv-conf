-- deus0ww - 2020-05-27

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local opts = {
	enabled          = false,    -- Master switch to enable/disable shaders
	set_timer        = 1/3,
	hifps_threshold  = 30,

	default_index    = 1,        -- Default shader set
	auto_switch      = true,     -- Auto switch shader preset base on path

	preset_1_enabled = true,     -- Enable this preset
	preset_1_path    = 'anime',  -- Path search string (Lua pattern)
	preset_1_index   = 2,        -- Shader set index to enable

	preset_2_enabled = false,
	preset_2_path    = '%[.+%]',
	preset_2_index   = 2,

	preset_3_enabled = true,
	preset_3_path    = 'cartoon',
	preset_3_index   = 2,
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
		['dwidth']              = -1,
		['dheight']             = -1,
		['osd-width']           = -1,
		['osd-height']          = -1,
		['container-fps']       = -1,
		['video-params/rotate'] = -1,
	}
end
reset()

local function is_initialized()
	return ((props['dwidth']              >  0) and
            (props['dheight']             >  0) and
            (props['osd-width']           >  0) and
            (props['osd-height']          >  0) and
            (props['container-fps']       >  0) and
            (props['video-params/rotate'] >= 0))
end


--------------------
--- Shader Utils ---
--------------------
local function default_options()
	return {
		['scale']  = 'ewa_lanczossoft',
		['cscale'] = 'ewa_lanczossoft',
		['dscale'] = 'ewa_lanczossoft',
		['sigmoid-upscaling']  = 'yes',
		['deband-grain']  = 24,
	}
end

local function is_high_fps() return props['container-fps'] > opts.hifps_threshold end
local function get_scale()
	local dwidth, dheight = props['dwidth'], props['dheight']
	if (props['video-params/rotate'] % 180) ~= 0 then dwidth, dheight = dheight, dwidth end
	local x_scale, y_scale = props['osd-width'] / dwidth, props['osd-height'] / dheight
	return (x_scale > 0 and y_scale > 0) and math.min(x_scale, y_scale) or 1
end


--------------------
--- Shader Files ---
--------------------
local shaders_path = '~~/shaders/'

-- igv's - https://gist.github.com/igv , https://github.com/igv/FSRCNN-TensorFlow
local igv_path = shaders_path .. 'igv/'
local igv = { 
	fsrcnnx_8  = igv_path .. 'FSRCNNX_x2_8-0-4-1.glsl',
	fsrcnnx_8l = igv_path .. 'FSRCNNX_x2_8-0-4-1_LineArt.glsl', 
	fsrcnnx_16 = igv_path .. 'FSRCNNX_x2_16-0-4-1.glsl',
	
	krig       = igv_path .. 'KrigBilateral.glsl',
	sssr       = igv_path .. 'SSimSuperRes.glsl',
	ssds       = igv_path .. 'SSimDownscaler.glsl',
	asharpen   = igv_path .. 'adaptive-sharpen.glsl',
}
igv.fsrcnnx = function() return (is_high_fps() or (get_scale() > 3)) and igv.fsrcnnx_8 or igv.fsrcnnx_16 end

-- RAVU - https://github.com/bjin/mpv-prescalers
local ravu_path = shaders_path .. 'ravu/'
local ravu = {
	lite_r4 = ravu_path .. 'ravu-lite-r4.hook',
	zoom_r4 = ravu_path .. 'ravu-zoom-r4.hook',
}
ravu.r4 = function() return ((get_scale() >= 4)) and ravu.lite_r4 or ravu.zoom_r4 end

-- Anime4K - https://github.com/bloc97/Anime4K/
local anime4k_path      = shaders_path .. 'anime4k/'
local anime4k = {
	downscale           = anime4k_path .. 'Upscale/Anime4K_Auto_Downscale_Pre_x4.glsl',
	upscale_1           = anime4k_path .. 'Upscale/Anime4K_Upscale_DoG_x2.glsl',
	upscale_2           = anime4k_path .. 'Upscale/Anime4K_Upscale_Original_x2.glsl',
	upscale_3           = anime4k_path .. 'Upscale/Anime4K_Upscale_CNN_M_x2.glsl',
	upscale_4           = anime4k_path .. 'Upscale/Anime4K_Upscale_CNN_L_x2.glsl',
	upscale_5           = anime4k_path .. 'Upscale/Anime4K_Upscale_CNN_UL_x2.glsl',

	upscale_deblur_1    = anime4k_path .. 'Upscale_Deblur/Anime4K_Upscale_DoG_x2_Deblur.glsl',
	upscale_deblur_2    = anime4k_path .. 'Upscale_Deblur/Anime4K_Upscale_Original_x2_Deblur_x2.glsl',
	upscale_deblur_3    = anime4k_path .. 'Upscale_Deblur/Anime4K_Upscale_CNN_M_x2_Deblur.glsl',
	upscale_deblur_4    = anime4k_path .. 'Upscale_Deblur/Anime4K_Upscale_CNN_L_x2_Deblur.glsl',
	upscale_deblur_5    = anime4k_path .. 'Upscale_Deblur/Anime4K_Upscale_CNN_UL_x2_Deblur.glsl',

	upscale_denoise_3   = anime4k_path .. 'Upscale_Denoise/Anime4K_Upscale_CNN_M_x2_Denoise.glsl',
	upscale_denoise_4   = anime4k_path .. 'Upscale_Denoise/Anime4K_Upscale_CNN_L_x2_Denoise.glsl',
	upscale_denoise_5   = anime4k_path .. 'Upscale_Denoise/Anime4K_Upscale_CNN_UL_x2_Denoise.glsl',

	deblur_1            = anime4k_path .. 'Deblur/Anime4K_Deblur_DoG.glsl',
	deblur_2            = anime4k_path .. 'Deblur/Anime4K_Deblur_Original.glsl',
	deblur_3            = anime4k_path .. 'Deblur/Anime4K_Deblur_CNN_M.glsl',
	deblur_4            = anime4k_path .. 'Deblur/Anime4K_Deblur_CNN_L.glsl',

	denoise_mean        = anime4k_path .. 'Denoise/Anime4K_Denoise_Bilateral_Mean.glsl',
	denoise_median_luma = anime4k_path .. 'Denoise/Anime4K_Denoise_Bilateral_Mean_Luma.glsl',
	denoise_median      = anime4k_path .. 'Denoise/Anime4K_Denoise_Bilateral_Median.glsl',
	denoise_mode        = anime4k_path .. 'Denoise/Anime4K_Denoise_Bilateral_Mode.glsl',

	darklines_1         = anime4k_path .. 'Experimental_Effects/Anime4K_DarkLines_VeryFast.glsl',
	darklines_2         = anime4k_path .. 'Experimental_Effects/Anime4K_DarkLines_Fast.glsl',
	darklines_3         = anime4k_path .. 'Experimental_Effects/Anime4K_DarkLines_HQ.glsl',

	thinlines_1         = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_VeryFast.glsl',
	thinlines_2         = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_Fast.glsl',
	thinlines_3         = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_HQ.glsl',
	thinlines_3_fhd     = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_HQ_FHD.glsl',
	thinlines_3_hd      = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_HQ_HD.glsl',
	thinlines_3_sd      = anime4k_path .. 'Experimental_Effects/Anime4K_ThinLines_HQ_SD.glsl',

	reduce_1            = anime4k_path .. 'RA_Reduce/Anime4K_RA_DoG.glsl',
	reduce_3            = anime4k_path .. 'RA_Reduce/Anime4K_RA_CNN_M.glsl',
	reduce_4            = anime4k_path .. 'RA_Reduce/Anime4K_RA_CNN_L.glsl',
	reduce_5            = anime4k_path .. 'RA_Reduce/Anime4K_RA_CNN_UL.glsl',
}


-------------------
--- Shader Sets ---
-------------------
local sets = {}

sets[#sets+1] = function()
	local s, o = {}, default_options()
	-- Luma
	s[#s+1] = igv.fsrcnnx()
	s[#s+1] = ravu.r4()
	-- Chroma
	s[#s+1] = igv.krig
	-- RGB
	s[#s+1] = igv.asharpen
	-- Options
	o['deband-grain'] = 32
	o['sigmoid-upscaling']  = 'no'  -- For adaptive-sharpen.glsl
	return { shaders = s, options = o, label = 'FSRCNNX + RAVU + Krig + SSimSR + AdaptiveSharpen' }
end

sets[#sets+1] = function() -- FSRCNNX + Anime4K3 Enhance & Deblur
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = igv.krig
	if scale <= 2 then
		s[#s+1] = anime4k.denoise_median_luma
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_fhd
	elseif scale < 4 then
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_hd
		s[#s+1] = anime4k.upscale_deblur_3
	else
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_sd
		s[#s+1] = anime4k.upscale_deblur_3
	end
	o['deband-grain'] = 16
	return { shaders = s, options = o, label = 'FSRCNNX-LineArt + Krig + Anime4K3 Enhance & Deblur' }
end

sets[#sets+1] = function() -- FSRCNNX + Anime4K3 Deblur)
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = igv.krig
	if scale <= 2 then
		s[#s+1] = anime4k.denoise_median_luma
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_4
	elseif scale < 4 then
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_4
		s[#s+1] = anime4k.upscale_deblur_4
	else
		s[#s+1] = igv.fsrcnnx_8l
		s[#s+1] = anime4k.deblur_4
		s[#s+1] = anime4k.upscale_deblur_4
	end
	o['deband-grain'] = 16
	return { shaders = s, options = o, label = 'FSRCNNX-LineArt + Krig + Anime4K3 Deblur' }
end

sets[#sets+1] = function() -- Anime4K3 Enhance & Deblur
	local s, o, scale = {}, default_options(), get_scale()
	s[#s+1] = igv.krig
	if scale <= 2 then
		s[#s+1] = anime4k.denoise_mode
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_fhd
		s[#s+1] = anime4k.upscale_deblur_4
	elseif scale < 4 then
		s[#s+1] = anime4k.upscale_denoise_3
		s[#s+1] = anime4k.downscale
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_hd
		s[#s+1] = anime4k.upscale_deblur_3
	else
		s[#s+1] = anime4k.upscale_denoise_4
		s[#s+1] = anime4k.deblur_3
		s[#s+1] = anime4k.darklines_3
		s[#s+1] = anime4k.thinlines_3_sd
		s[#s+1] = anime4k.upscale_deblur_3
	end
	o['deband-grain'] = 16
	return { shaders = s, options = o, label = 'Krig + Anime4K3 Enhance & Deblur' }
end

--sets[#sets+1] = function() -- Anime4K3 (Improve perceptual quality + deblur)
--	local s, o, scale = {}, default_options(), get_scale()
--	s[#s+1] = igv.krig
--	if scale <= 2 then
--		s[#s+1] = anime4k.denoise
--		s[#s+1] = anime4k.deblur_1
--		s[#s+1] = anime4k.darklines_3
--		s[#s+1] = anime4k.thinlines_3
--		s[#s+1] = anime4k.upscale_deblur_3
--	else
--		s[#s+1] = anime4k.upscale_denoise_3
--		s[#s+1] = anime4k.downscale
--		s[#s+1] = anime4k.deblur_1
--		s[#s+1] = anime4k.darklines_3
--		s[#s+1] = anime4k.thinlines_3
--		s[#s+1] = anime4k.upscale_deblur_3
--	end
--	return { shaders = s, options = o, label = 'Anime4K3 (Enhance & Deblur) + Krig' }
--end
--
--sets[#sets+1] = function() -- Anime4K3 (Improve perceptual quality)
--	local s, o, scale = {}, default_options(), get_scale()
--	s[#s+1] = igv.krig
--	if scale <= 2 then
--		s[#s+1] = anime4k.denoise
--		s[#s+1] = anime4k.darklines_3
--		s[#s+1] = anime4k.thinlines_3
--		s[#s+1] = anime4k.upscale_deblur_3
--	else
--		s[#s+1] = anime4k.upscale_denoise_3
--		s[#s+1] = anime4k.downscale
--		s[#s+1] = anime4k.darklines_3
--		s[#s+1] = anime4k.thinlines_3
--		s[#s+1] = anime4k.upscale_deblur_3
--	end
--	return { shaders = s, options = o, label = 'Anime4K3 (Enhance) + Krig' }
--end
--
--sets[#sets+1] = function() -- Anime4K3 (Remain as faithful to the original while enhancing details)
--	local s, o, scale = {}, default_options(), get_scale()
--	s[#s+1] = igv.krig
--	if scale <= 2 then
--		s[#s+1] = anime4k.denoise
--		s[#s+1] = anime4k.upscale_deblur_3
--	else
--		s[#s+1] = anime4k.upscale_denoise_3
--		s[#s+1] = anime4k.downscale
--		s[#s+1] = anime4k.upscale_deblur_3
--	end
--	return { shaders = s, options = o, label = 'Anime4K3 (Faithful) + Krig' }
--end


--------------------
--- MPV Commands ---
--------------------
local function show_osd(no_osd, label)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set %d: %s'):format(enabled and '■' or '□', current_index, label or 'n/a'), 6)
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
	mpv_clear_shaders()
	msg.debug('Setting Shaders:', utils.to_string(shaders))
	for _, shader in ipairs(shaders) do
		if shader and shader ~= '' then mp.commandv('change-list', 'glsl-shaders', 'append', shader) end
	end
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

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd  == 'yes') end)
