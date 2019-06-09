-- deus0ww - 2019-06-08

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local user_opts = {
	enabled = false,
	set = 1,
	path = '/Users/Shared/Library/mpv/shaders/', -- Should be the same as '~~/shaders/' expanded
}


-------------
--- Utils ---
-------------
local function file_exists(path)
	local file = io.open(path, 'rb')
	if not file then return false end
	local _, _, code = file:read(1)
	file:close()
	return code == nil
end


------------------
--- Properties ---
------------------
local props, last_shaders
local function reset()
	props = {
		['width'] = '',
		['height'] = '',
		['osd-width'] = 0,
		['osd-height'] = 0,
		['container-fps'] = '',
		['video-params/rotate'] = '',
		['video-params/pixelformat'] = '',
		['video-params/chroma-location'] = '',
	}
	last_shaders = nil
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
local rotated_offset = { [-360] = {x = -0.5,  y =  0.0 },
					     [-270] = {x =  0.0,  y = -0.5 },
					     [-180] = {x =  0.5,  y =  0.0 },
					     [ -90] = {x =  0.0,  y =  0.5 },
					     [   0] = {x = -0.5,  y =  0.0 },
					     [  90] = {x =  0.0,  y = -0.5 },
					     [ 180] = {x =  0.5,  y =  0.0 },
					     [ 270] = {x =  0.0,  y =  0.5 },
					     [ 360] = {x = -0.5,  y =  0.0 }, }

local function is_high_fps()          return props['container-fps'] > 33 end
local function is_chroma_subsampled() return props['video-params/pixelformat']:find('444') == nil end
local function is_chroma_left()       return props['video-params/chroma-location'] == 'mpeg2/4/h264' end
--local function is_chroma_center()     return props['video-params/chroma-location'] == 'mpeg1/jpeg'   end
local function get_rotated_offset()   return rotated_offset[props['video-params/rotate']] end
local function get_scale()
	local width, height = props['width'], props['height']
	if (props['video-params/rotate'] % 180) ~= 0 then width, height = height, width end
	return math.min( mp.get_property_native('osd-width', 0) / width, mp.get_property_native('osd-height', 0) / height )
end

local output_subdir = 'KrigBilateral/'
local output_format = 'KrigBilateral%+.1f%+.1f.glsl'
local mkdir_cmd     = 'mkdir -p %s'
local sed_cmd       = 'sed -e \"s|\\${X_OFFSET}|%+.1f|\" -e \"s|\\${Y_OFFSET}|%+.1f|\" %s > %s'

local function krigbilateral(has_prescalers)
	local offset
	if is_chroma_left() and is_chroma_subsampled() then
		local scale, prescale = get_scale(), 1
		if has_prescalers then
			if     scale > 2.82843024 then prescale = 4 -- FSRCNNX + RAVU
		 -- elseif scale > 2.12132269 then prescale = 3 -- Disabled: no 3x prescaler
			elseif scale > 1.4        then prescale = 2 -- FSRCNNX
			else                           prescale = 1 end
		end
		local rotated_offset = get_rotated_offset()
		offset = { x = rotated_offset.x * prescale, y = rotated_offset.y * prescale }
	else
		offset = { x = 0, y = 0 }
	end

	local output = output_format:format(offset.x, offset.y)
	local output_fullpath = user_opts.path .. output_subdir .. output
	if not file_exists(output_fullpath) then
		local success1, success2, result
		success1, result = pcall(io.popen, mkdir_cmd:format(user_opts.path .. output_subdir))
		if success1 then result:close() end
		success2, result = pcall(io.popen, sed_cmd:format(offset.x, offset.y, user_opts.path .. 'KrigBilateral.glsl', output_fullpath))
		if success2 then result:close() end
		
		if (success1 and success2) then
			msg.debug('Creating KrigBilateral Shader:', output_fullpath)
		else
			msg.debug('Creating KrigBilateral Shader: failed')
			return ''
		end
	else
		msg.debug('Using KrigBilateral Shader:', output_fullpath)
	end
	return output_subdir .. output
end


-------------------
--- Shader Sets ---
-------------------
local sets = {}

--	sets[#sets+1] = function()
--		local s = {}
--		-- Chroma
--		s[#s+1] = krigbilateral(true)
--		s[#s+1] = 'KrigBilateral-auto.glsl'
--		return { shaders = s, label = 'Krig' }
--	end

sets[#sets+1] = function()
	local s = {}
	-- LUMA
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = 'KrigBilateral-auto.glsl'
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	return { shaders = s, label = 'FSRCNNX + RAVU-Lite + Krig + SSimSR/DS' }
end

sets[#sets+1] = function()
	local s = {}
	-- LUMA
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = 'ravu-lite-r4.hook'
	-- Chroma
	s[#s+1] = krigbilateral(true)
	-- RGB
	s[#s+1] = 'SSimSuperRes.glsl'
	s[#s+1] = 'SSimDownscaler.glsl'
	return { shaders = s, label = 'FSRCNNX + RAVU + Krig + SSimSR/DS' }
end


--------------------
--- MPV Commands ---
--------------------
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
		if shader and shader ~= '' then mp.commandv('change-list', 'glsl-shaders', 'append', '~~/shaders/' .. shader) end
	end
end

local function show_osd(no_osd, label)
	if no_osd then return end
	mp.osd_message(('%s Shaders Set %d: %s'):format(user_opts.enabled and '☑︎' or '☐', user_opts.set, label or 'n/a'))
end


--------------------------
--- Observers & Events ---
--------------------------
mp.register_event('file-loaded', function() 
	opt.read_options(user_opts, mp.get_script_name())
	reset()
end)

local timer = mp.add_timeout(1, function() apply_shaders(sets[user_opts.set]().shaders) end)
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
	msg.debug('Shader - Up:', user_opts.set)
	if not is_initialized() then return end
	user_opts.set = (user_opts.set % #sets) + 1
	local shaders = sets[user_opts.set]()
	if user_opts.enabled then apply_shaders(shaders.shaders) end
	show_osd(no_osd, shaders.label)
end

local function cycle_set_dn(no_osd)
	msg.debug('Shader - Down:', user_opts.set)
	if not is_initialized() then return end
	user_opts.set = ((user_opts.set - 2) % #sets) + 1
	local shaders = sets[user_opts.set]()
	if user_opts.enabled then apply_shaders(shaders.shaders) end
	show_osd(no_osd, shaders.label)
end

local function toggle_set(no_osd)
	msg.debug('Shader - Toggling:', user_opts.set)
	if not is_initialized() then return end
	if user_opts.set == 0 then user_opts.set = 1 end
	last_shaders = nil
	local shaders = sets[user_opts.set]()
	if user_opts.enabled then clear_shaders() else apply_shaders(shaders.shaders) end
	user_opts.enabled = not user_opts.enabled
	show_osd(no_osd, shaders.label)
end

local function enable_set(no_osd)
	msg.debug('Shader - Enabling:', user_opts.set)
	if not is_initialized() then return end
	user_opts.enabled = true
	last_shaders = nil
	local shaders = sets[user_opts.set]()
	apply_shaders(shaders.shaders)
	show_osd(no_osd, shaders.label)
end

local function disable_set(no_osd)
	msg.debug('Shader - Disabling:', user_opts.set)
	if not is_initialized() then return end
	user_opts.enabled = false
	last_shaders = nil
	local shaders = sets[user_opts.set]()
	clear_shaders()
	show_osd(no_osd, shaders.label)
end

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd == 'yes') end)
