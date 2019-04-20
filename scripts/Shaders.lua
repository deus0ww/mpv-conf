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
		['video-params/chroma-location'] = 'unknown',
	}
	last_shaders = ''
end
reset()

local function create_shaders()
	local p, s = watched_properties, {}
	
	-- LUMA
	if p['container-fps'] <= 30 then
		s[#s+1] = 'FSRCNNX_x2_16-0-4-1.glsl'
	else
		s[#s+1] = 'FSRCNNX_x2_8-0-4-1.glsl'
	end
	s[#s+1] = 'ravu-zoom-r4.hook'
	s[#s+1] = 'EnhanceDetail.glsl'
	
	-- Chroma
	if math.min( p['osd-width'] / p['width'], p['osd-height'] / p['height'] ) > 2 then
		if     p['video-params/chroma-location'] == 'mpeg2/4/h264' then
			s[#s+1] = 'ravu-r4-chroma-left.hook'
		elseif p['video-params/chroma-location'] == 'mpeg1/jpeg'   then
			s[#s+1] = 'ravu-r4-chroma-center.hook'
		end
	end
	s[#s+1] = 'KrigBilateral.glsl'

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
		local p = watched_properties
		if v_new == nil or v_new == p[prop] then return end
		msg.debug('Property', prop, 'changed:', p[prop], '->', v_new)
		p[prop] = v_new
		
		if  p['container-fps'] == 0 or
			p['width']         == 0 or
			p['height']        == 0 or
			p['osd-width']     == 0 or
			p['osd-height']    == 0
		then return end

		msg.debug('Resetting Timer')
		timer:kill()
		timer:resume()
	end)
end
