-- deus0ww - 2020-12-31

local mp      = require 'mp'
local msg     = require 'mp.msg'



-- Cycling OSD without 'always'
local osc_vis, alt_vis = 'auto', 'never'
mp.register_script_message('OSC-vis-cycle', function()
	osc_vis, alt_vis = alt_vis, osc_vis
	mp.command_native({'script-message', 'osc-visibility', osc_vis})
end)



-- Property Changer
local function title_case(first, rest) return first:upper()..rest:lower() end
local function change_prop(action, property, value)
	mp.command_native_async({action, property, tostring(value)}, function()
		mp.osd_message(('%s:% 4d'):format(property:gsub("(%a)([%w_']*)", title_case), mp.get_property_native(property, 0)))
	end)
end
mp.register_script_message('Add', function(property, value) change_prop('add', property, value) end)
mp.register_script_message('Set', function(property, value) change_prop('set', property, value) end)



-- Cycle Video Rotation
mp.register_script_message('Video-Rotate', function(degrees)
	change_prop('set', 'video-rotate', (degrees + mp.get_property_number('video-rotate', 0)) % 360)
end)



-- Show Play/Pause
local display = mp.get_property_osd('osd-ass-cc/0', '') ..
                '{\\1a&H20&\\3a&H20&\\bord1\\blur0.5\\fs20\\fnmpv-osd-symbols}%s' ..
                mp.get_property_osd('osd-ass-cc/1', '')
mp.observe_property('pause', 'native', function(_, pause)
	if pause == nil then return end
	mp.osd_message(display:format(pause and '\238\128\130' or '\238\132\129'), pause and 1.0 or 0.5)
end)



-- OnTop only while playing
local last_ontop = mp.get_property_native('ontop', false)
mp.observe_property('ontop', 'native', function(_, ontop)
	if ontop == nil or ontop == last_ontop then return end
	last_ontop = ontop
	mp.osd_message( (ontop and '■' or '□') .. ' On Top')
end)

local paused_ontop = last_ontop
mp.observe_property('pause', 'native', function(_, pause)
	msg.debug('Pause:', pause)
    if pause then
		paused_ontop = mp.get_property_native('ontop', false)
		if paused_ontop then
			msg.debug('Paused - Disabling OnTop')
			mp.command('async no-osd set ontop no')
		end
	else
		if paused_ontop ~= mp.get_property_native('ontop', false) then
			msg.debug('Unpaused - Restoring OnTop')
			mp.command('async no-osd set ontop ' .. (paused_ontop and 'yes' or 'no'))
		end
    end
end)



-- Pause on Minimize
local start_paused = mp.get_property_native('pause', false)
local was_paused   = start_paused
mp.observe_property('window-minimized', 'native', function(_, minimized)
	msg.debug('Minimized:', minimized)
	if minimized then
		msg.debug('Minimized - Pausing. Previously:', was_paused)
		was_paused = mp.get_property_native('pause', false)
		mp.set_property_native('pause', true)
	else
		msg.debug('Unminimized - Restoring Pause:', was_paused)
		mp.set_property_native('pause', was_paused)
	end
end)
mp.register_event('file-loaded', function()
	was_paused = start_paused
	if mp.get_property_native('window-minimized', false) then
		mp.set_property_native('pause', true)
	else
		mp.set_property_native('pause', start_paused)
	end
end)



-- Format Interpolation OSD Message
local last_interpolation = mp.get_property_native('interpolation', false)
mp.observe_property('interpolation', 'native', function(_, interpolation)
	if interpolation == nil or interpolation == last_interpolation then return end
	last_interpolation = interpolation
	local tscale = mp.get_property_native('tscale', 'na')
	local window = mp.get_property_native('tscale-window', 'na')
	local radius = mp.get_property_native('tscale-radius', 0)
	local clamp  = mp.get_property_native('tscale-clamp', 1.0)
	tscale = tscale ~= '' and tscale or 'na'
	window = window ~= '' and window or 'na'
	radius = radius ~= 0  and tostring(radius) or 'default'
	mp.osd_message( ('%s Interpolation: [Filter=%s  Window=%s Radius=%s Clamp=%d]'):format((interpolation and '■' or '□'), tscale, window, radius, clamp) )
end)



-- Workaround for setting default volume
mp.register_event('file-loaded', function()
	local vol
	mp.add_timeout(0.05, function()
		msg.debug('Resetting Volume')
		vol = mp.get_property_native('volume')
		mp.set_property_native('volume', vol - 5)
		mp.set_property_native('volume', vol)
	end)
end)
