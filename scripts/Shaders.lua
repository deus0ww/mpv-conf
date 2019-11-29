-- deus0ww - 2019-11-29

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local opts = {
	enabled          = false,    -- Master switch to enable/disable shaders

	default_index    = 1,        -- Default shader set
	auto_switch      = true,     -- Auto switch shader preset base on path
	
	preset_1_enabled = true,     -- Enable this preset
	preset_1_path    = 'anime',  -- Path search string (Lua pattern)
	preset_1_index   = 2,        -- Shader set index to enable
	
	preset_2_enabled = true,
	preset_2_path    = '%[.+%]',
	preset_2_index   = 2,
	
	preset_3_enabled = false,
	preset_3_path    = 'cartoon',
	preset_3_index   = 3,
}
opt.read_options(opts, mp.get_script_name())


------------------
--- Properties ---
------------------
local current_index, enabled = opts.default_index, opts.enabled
local props, last_shaders
local function reset()
	props = {
		['width']               = '',
		['height']              = '',
		['osd-width']           = 0,
		['osd-height']          = 0,
		['container-fps']       = '',
		['video-params/rotate'] = '',
	}
end
reset()

local function is_initialized()
	for _, value in pairs(props) do
		if value == '' then return false end
	end
	return true
end


--------------------
--- Shader Utils ---
--------------------
local function is_high_fps() return props['container-fps'] > 33 end
local function get_scale()
	local width, height = props['width'], props['height']
	if (props['video-params/rotate'] % 180) ~= 0 then width, height = height, width end
	return math.min( mp.get_property_native('osd-width', 0) / width, mp.get_property_native('osd-height', 0) / height )
end
local function default_options()
	return {
		['scale']  = 'ewa_lanczossharp',
		['cscale'] = 'ewa_robidouxsharp',
		['dscale'] = 'ewa_robidouxsharp',
		['linear-downscaling'] = 'yes',
		['sigmoid-upscaling']  = 'yes',
	}
end


-------------------
--- Shader Sets ---
-------------------
local sets = {}

sets[#sets+1] = function()
	local s, o = {}, default_options()
	-- Luma
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	s[#s+1] = 'adaptive-sharpen.glsl'
	-- Options
	o['dscale'] = 'ewa_robidoux'    -- For SSimDownscaler.glsl
	o['linear-downscaling'] = 'no'  -- For SSimDownscaler.glsl
	o['sigmoid-upscaling']  = 'no'  -- For adaptive-sharpen.glsl
	
	return { shaders = s, options = o, label = 'FSRCNNX + RAVU-Lite + Krig + SSimSR/DS + AdaptiveSharpen' }
end

sets[#sets+1] = function()
	local s, o, scale, label = {}, default_options(), get_scale()
	if scale < 1 then
		s[#s+1] = 'SSimDownscaler.glsl'
		o['dscale'] = 'ewa_robidoux'    -- For SSimDownscaler.glsl
		o['linear-downscaling'] = 'no'  -- For SSimDownscaler.glsl
		label   = 'Krig + SSimDS + AdaptiveSharpen'
	elseif scale <= 2 then
		s[#s+1] = 'Anime4K_Adaptive_v1.0RC2.glsl'
		s[#s+1] = 'FSRCNNX_x2_8-0-4-1.glsl'
		label   = 'Anime4K + FSRCNNX + Krig + AdaptiveSharpen'
	else
		s[#s+1] = 'FSRCNNX_x2_8-0-4-1.glsl'
		s[#s+1] = 'SSimSuperRes.glsl'
		s[#s+1] = 'Anime4K_Adaptive_v1.0RC2.glsl'
		s[#s+1] = 'ravu-lite-r4.hook'
		label   = 'FSRCNNX + Anime4K + RAVU-Lite + Krig + SSimSR + AdaptiveSharpen'
	end
	s[#s+1] = 'KrigBilateral.glsl'
	s[#s+1] = 'adaptive-sharpen.glsl'
	
	o['sigmoid-upscaling']  = 'no'  -- For adaptive-sharpen.glsl
	
	return { shaders = s, options = o, label = label }
end

sets[#sets+1] = function()
	local s, o = {}, default_options()
	-- Luma
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	-- Options
	o['dscale'] = 'ewa_robidoux'    -- For SSimDownscaler.glsl
	o['linear-downscaling'] = 'no'  -- For SSimDownscaler.glsl
	
	return { shaders = s, options = o, label = 'FSRCNNX + RAVU-Lite + Krig + SSimSR/DS' }
end


--------------------
--- MPV Commands ---
--------------------
local function show_osd(no_osd, label)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set %d: %s'):format(enabled and '☑︎' or '☐', current_index, label or 'n/a'), 6)
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
		if shader and shader ~= '' then mp.commandv('change-list', 'glsl-shaders', 'append', '~~/shaders/' .. shader) end
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
mp.register_event('file-loaded', function()
	reset()
	if not opts.auto_switch then return end
	local path = mp.get_property_native('path', ''):lower()
	current_index = opts.default_index
	if opts.preset_1_enabled and path:find(opts.preset_1_path) ~= nil then current_index = opts.preset_1_index end
	if opts.preset_2_enabled and path:find(opts.preset_2_path) ~= nil then current_index = opts.preset_2_index end
	if opts.preset_3_enabled and path:find(opts.preset_3_path) ~= nil then current_index = opts.preset_3_index end
end)

local timer = mp.add_timeout(1, function() set_shaders(true) end)
timer:kill()
for prop, _ in pairs(props) do
	mp.observe_property(prop, 'native', function(_, v_new)
		msg.debug('Property', prop, 'changed:', (props[prop] ~= '') and props[prop] or 'n/a', '->', v_new)
		
		if v_new == nil or v_new == props[prop] then return end
		props[prop] = v_new
		
		if is_initialized() then
			msg.debug('Resetting Timer')
			timer:kill()
			timer:resume()
		end
	end)
end


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
	if enabled then set_shaders(no_osd) else clear_shaders(no_osd) end
end

local function enable_set(no_osd)
	msg.debug('Shader - Enabling:', current_index)
	if not is_initialized() then return end
	enabled = true
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
