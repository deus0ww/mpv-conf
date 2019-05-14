-- deus0ww - 2019-05-14

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local user_opts = {
	enabled = false,
	set = 1,
}


------------------
--- Properties ---
------------------
local props, last_shaders
local function reset()
	props = {
		['container-fps'] = 0,
		['width'] = 0,
		['height'] = 0,
		['osd-width'] = 0,
		['osd-height'] = 0,
		['video-params/chroma-location'] = 0,
	}
	last_shaders = nil
end
reset()


---------------
--- Shaders ---
---------------
local sets = {}

local function is_high_fps()      return props['container-fps'] > 33 end
local function get_scale()        return math.min( props['osd-width'] / props['width'], props['osd-height'] / props['height'] ) end
local function is_chroma_left()   return props['video-params/chroma-location'] == 'mpeg2/4/h264' end
--local function is_chroma_center() return props['video-params/chroma-location'] == 'mpeg1/jpeg'   end
local function krigbilateral()
	local scale = get_scale()
	if is_chroma_left() then
		if scale < 1.4      then return 'KrigBilateral-05.glsl' end -- No Luma Scaler
		if scale < 2.828430 then return 'KrigBilateral-10.glsl' end -- 2x Luma Scaler (FSRCNNX)
		return 'KrigBilateral-20.glsl' -- 4x Luma Scalers (FSRCNNX + ravu_lite)
	else
		return 'KrigBilateral-00.glsl'
	end
end

sets[#sets+1] = function()
	local s = {}
	-- LUMA
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-r4.hook'
	-- Chroma
	s[#s+1] = krigbilateral()
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	return s
end

sets[#sets+1] = function()
	local s = {}
	-- LUMA
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = krigbilateral()
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	return s
end


---------------------------
--- MPV Shader Commands ---
---------------------------
local function clear_shaders()
	msg.debug('Clearing Shaders.')
	mp.commandv('change-list', 'glsl-shaders', 'clr', '')
end

local function apply_shaders(shaders)
	if not user_opts.enabled then
		msg.debug('Setting Shaders: skipped - disabled.')
		return
	end

	local s, _ = utils.to_string(shaders)
	if last_shaders == s then 
		msg.debug('Setting Shaders: skipped - shaders unchanged.')
		return
	end
	last_shaders = s

	clear_shaders()
	msg.debug('Setting Shaders:', s)
	for _, shader in ipairs(shaders) do
		mp.commandv('change-list', 'glsl-shaders', 'append', '~~/shaders/' .. shader)
	end
end

local function show_osd(no_osd)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set: %d'):format(user_opts.enabled and '☑︎' or '☐', user_opts.set))
end


-----------------
--- Listeners ---
-----------------
mp.register_event('file-loaded', function() 
	opt.read_options(user_opts, mp.get_script_name())
	reset()
end)

local timer = mp.add_timeout(1, function() apply_shaders(sets[user_opts.set]()) end)
timer:kill()
for prop, _ in pairs(props) do
	mp.observe_property(prop, 'native', function(_, v_new)
		msg.debug('Property', prop, 'changed:', props[prop], '->', v_new)
		
		if v_new == nil or v_new == props[prop] then return end
		props[prop] = v_new
		
		for _, value in pairs(props) do
			if value == 0 then return end
		end

		msg.debug('Resetting Timer')
		timer:kill()
		timer:resume()
	end)
end


----------------
--- Bindings ---
----------------
local function cycle_set_up(no_osd)
	msg.debug('Shader - Up:', user_opts.set)
	user_opts.set = (user_opts.set % #sets) + 1
	if user_opts.enabled then apply_shaders(sets[user_opts.set]()) end
	show_osd(no_osd)
end

local function cycle_set_dn(no_osd)
	msg.debug('Shader - Down:', user_opts.set)
	user_opts.set = ((user_opts.set - 2) % #sets) + 1
	if user_opts.enabled then apply_shaders(sets[user_opts.set]()) end
	show_osd(no_osd)
end

local function toggle_set(no_osd)
	msg.debug('Shader - Toggling:', user_opts.set)
	if user_opts.set == 0 then user_opts.set = 1 end
	last_shaders = nil
	if user_opts.enabled then clear_shaders() else apply_shaders(sets[user_opts.set]()) end
	user_opts.enabled = not user_opts.enabled
	show_osd(no_osd)
end

local function enable_set(no_osd)
	msg.debug('Shader - Enabling:', user_opts.set)
	user_opts.enabled = true
	last_shaders = nil
	apply_shaders(sets[user_opts.set]())
	show_osd(no_osd)
end

local function disable_set(no_osd)
	msg.debug('Shader - Disabling:', user_opts.set)
	user_opts.enabled = false
	last_shaders = nil
	clear_shaders()
	show_osd(no_osd)
end

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd == 'yes') end)
