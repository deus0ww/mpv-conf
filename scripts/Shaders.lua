-- deus0ww - 2019-11-01

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local o = {
	enabled          = false,    -- Master switch to enable/disable shaders

	default_index    = 1,        -- Default shader set
	auto_switch      = true,     -- Auto switch shader preset base on path
	
	preset_1_enabled = true,     -- Enable this preset
	preset_1_path    = 'anime',  -- Path search string
	preset_1_index   = 2,        -- Shader set index to enable
	
	preset_2_enabled = false,
	preset_2_path    = '',
	preset_2_index   = 1,
	
	preset_3_enabled = false,
	preset_3_path    = '',
	preset_3_index   = 1,
}
opt.read_options(o, mp.get_script_name())


------------------
--- Properties ---
------------------
local current_set, enabled = o.default_index, o.enabled
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


-------------------
--- Shader Sets ---
-------------------
local sets = {}

sets[#sets+1] = function()
	local s = {}
	-- Luma
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	s[#s+1] = 'adaptive-sharpen.glsl'
	return { shaders = s, label = 'FSRCNNX + RAVU-Lite + Krig + SSimSR/DS + AdaptiveSharpen' }
end

sets[#sets+1] = function()
	local s, label = {}
	-- Luma
	if get_scale() <= 2 then
		s[#s+1] = 'Anime4K_Adaptive_v1.0RC2.glsl'
		s[#s+1] = 'FSRCNNX_x2_8-0-4-1.glsl'
		label   = 'Anime4K + FSRCNNX'
	else
		s[#s+1] = 'FSRCNNX_x2_8-0-4-1.glsl'
		s[#s+1] = 'Anime4K_Adaptive_v1.0RC2.glsl'
		s[#s+1] = 'ravu-lite-r4.hook'
		label   = 'FSRCNNX + Anime4K + RAVU-Lite'
	end
	-- Chroma
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	s[#s+1] = 'adaptive-sharpen.glsl'
	return { shaders = s, label = label .. ' + Krig + SSimSR/DS + AdaptiveSharpen' }
end

sets[#sets+1] = function()
	local s = {}
	-- Luma
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	return { shaders = s, label = 'FSRCNNX + RAVU-Lite + Krig + SSimSR/DS' }
end


--------------------
--- MPV Commands ---
--------------------
local function show_osd(no_osd, label)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set %d: %s'):format(enabled and '☑︎' or '☐', current_set, label or 'n/a'), 6)
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
	local shaders = sets[current_set]()
	show_osd(no_osd, shaders.label)
	if last_shaders == nil then
		msg.debug('Clearing Shaders: skipped - no shader found.')
		return
	end
	last_shaders = nil
	mpv_clear_shaders()
end

local function set_shaders(no_osd)
	local shaders = sets[current_set]()
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
	mpv_set_shaders(shaders.shaders)
end


--------------------------
--- Observers & Events ---
--------------------------
mp.register_event('file-loaded', function()
	reset()
	if not o.auto_switch then return end
	local path = mp.get_property_native('path', ''):lower()
	current_set = o.default_index
	if o.preset_1_enabled and path:find(o.preset_1_path) ~= nil then current_set = o.preset_1_index end
	if o.preset_2_enabled and path:find(o.preset_2_path) ~= nil then current_set = o.preset_2_index end
	if o.preset_3_enabled and path:find(o.preset_3_path) ~= nil then current_set = o.preset_3_index end
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
	msg.debug('Shader - Up:', current_set)
	if not is_initialized() then return end
	current_set = (current_set % #sets) + 1
	set_shaders(no_osd)
end

local function cycle_set_dn(no_osd)
	msg.debug('Shader - Down:', current_set)
	if not is_initialized() then return end
	current_set = ((current_set - 2) % #sets) + 1
	set_shaders(no_osd)
end

local function toggle_set(no_osd)
	msg.debug('Shader - Toggling:', current_set)
	if not is_initialized() then return end
	enabled = not enabled
	if enabled then set_shaders(no_osd) else clear_shaders(no_osd) end
end

local function enable_set(no_osd)
	msg.debug('Shader - Enabling:', current_set)
	if not is_initialized() then return end
	enabled = true
	set_shaders(no_osd)
end

local function disable_set(no_osd)
	msg.debug('Shader - Disabling:', current_set)
	if not is_initialized() then return end
	enabled = false
	clear_shaders(no_osd)
end

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd  == 'yes') end)
