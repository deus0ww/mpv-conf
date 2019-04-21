-- deus0ww - 2019-04-21

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



local user_opts = {
	enabled = false,
}

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

local ravu_threshold = 3
local high_fps_threshold = 33
local function get_scale()        return math.min( props['osd-width'] / props['width'], props['osd-height'] / props['height'] ) end
local function use_ravu()         return get_scale() > ravu_threshold end
local function is_high_fps()      return props['container-fps'] > high_fps_threshold end
local function is_chroma_left()   return props['video-params/chroma-location'] == 'mpeg2/4/h264' end
local function is_chroma_center() return props['video-params/chroma-location'] == 'mpeg1/jpeg'   end

local function create_shaders()
	local s, ravu = {}, use_ravu()
	-- LUMA
	s[#s+1] = is_high_fps() and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	s[#s+1] = ravu          and 'ravu-zoom-r4.hook'       or 'EnhanceDetail.glsl'
	-- Chroma
	s[#s+1] = (ravu and is_chroma_left())   and 'ravu-r4-chroma-left.hook'   or nil
	s[#s+1] = (ravu and is_chroma_center()) and 'ravu-r4-chroma-center.hook' or nil
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	s[#s+1] = (not ravu) and 'SSimSuperRes.glsl' or nil
	return s
end

local function set_shaders(shaders)
	local s, _ = utils.to_string(shaders)
	if last_shaders == s then 
		msg.debug('Setting Shaders: skipped - shaders unchanged.')
		return
	end
	last_shaders = s
	
	opt.read_options(user_opts, mp.get_script_name())
	if not user_opts.enabled then
		msg.debug('Setting Shaders: skipped - disabled.')
		return
	end
	
	msg.debug('Setting Shaders:', s)
	mp.commandv('change-list', 'glsl-shaders', 'clr', '')
	for _, shader in ipairs(shaders) do
		mp.commandv('change-list', 'glsl-shaders', 'append', '~~/shaders/' .. shader)
	end
end

mp.register_event('file-loaded', function() reset() end)

local timer = mp.add_timeout(0.5, function() set_shaders(create_shaders()) end)
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
