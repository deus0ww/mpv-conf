-- deus0ww - 2019-04-20

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



local user_opts = {
	enabled = false,
}

local watched_properties, last_shaders
local function reset()
	watched_properties = {
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

local ravu_limit = 3
local high_fps_threshold = 33
local function get_scale(p) return math.min( p['osd-width'] / p['width'], p['osd-height'] / p['height'] ) end
local function use_ravu(p) return get_scale(p) >= ravu_limit end
local function is_high_fps(p) return p['container-fps'] > high_fps_threshold end
local function is_chroma_left(p)   return p['video-params/chroma-location'] == 'mpeg2/4/h264' end
local function is_chroma_center(p) return p['video-params/chroma-location'] == 'mpeg1/jpeg'   end

local function create_shaders()
	local p, s = watched_properties, {}
	local scale, ravu = get_scale(p), use_ravu(p)

	-- LUMA
	s[#s+1] = is_high_fps(p) and 'FSRCNNX_x2_8-0-4-1.glsl' or 'FSRCNNX_x2_16-0-4-1.glsl'
	if ravu then s[#s+1] = 'ravu-zoom-r4.hook' end
	s[#s+1] = 'EnhanceDetail.glsl'
	-- Chroma
	if ravu and is_chroma_left(p)   then s[#s+1] = 'ravu-r4-chroma-left.hook'   end
	if ravu and is_chroma_center(p) then s[#s+1] = 'ravu-r4-chroma-center.hook' end
	s[#s+1] = 'KrigBilateral.glsl'
	-- RGB
	if not ravu then s[#s+1] = 'SSimSuperRes.glsl' end

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
for prop, _ in pairs(watched_properties) do
	mp.observe_property(prop, 'native', function(_, v_new)
		msg.debug('Property', prop, 'changed:', watched_properties[prop], '->', v_new)
		
		if v_new == nil or v_new == watched_properties[prop] then return end
		watched_properties[prop] = v_new
		
		for _, value in pairs(watched_properties) do
			if value == 0 then return end
		end

		msg.debug('Resetting Timer')
		timer:kill()
		timer:resume()
	end)
end
