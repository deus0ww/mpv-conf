-- deus0ww - 2019-03-24

local mp      = require 'mp'
local msg     = require 'mp.msg'



-- Cycling OSD without 'always'
local osc_vis, alt_vis = 'auto', 'never'
mp.register_script_message('OSC-vis-cycle', function()
	osc_vis, alt_vis = alt_vis, osc_vis
	mp.command_native({'script-message', 'osc-visibility', osc_vis})
end)



-- Property Changer
local function change_prop(action, property, value)
	mp.command_native_async({action, property, tostring(value)}, function() mp.osd_message(('%s:% 4d'):format(property:gsub('^%l', string.upper), mp.get_property_native(property, 0))) end)
end
mp.register_script_message('Add', function(property, value) change_prop('add', property, value) end)
mp.register_script_message('Set', function(property, value) change_prop('set', property, value) end)



-- Cycle Video Rotation
mp.register_script_message('Video-Rotate', function(degrees) 
	change_prop('set', 'video-rotate', (degrees + mp.get_property_number('video-rotate', 0)) % 360)
end)



-- Show Play/Pause
local display = mp.get_property_osd('osd-ass-cc/0', '') ..
                '{\\1a&H80&\\3a&H80&\\bord2\\blur2\\fs20\\fnmpv-osd-symbols}%s' ..
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
	mp.osd_message( (ontop and '☑︎' or '☐') .. ' On Top')
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
local last_pause = mp.get_property_native('pause', false)
mp.observe_property('window-minimized', 'native', function(_, minimized)
	msg.debug('Minimized:', minimized)
	if minimized then
		msg.debug('Minimized - Pausing')
		last_pause = mp.get_property_native('pause', false)
		mp.set_property_native('pause', true)
	else
		msg.debug('Unminimized - Restoring Pause')
		mp.set_property_native('pause', last_pause)
	end
end)



-- Format Interpolation OSD Message
local last_interpolation = mp.get_property_native('interpolation', false)
mp.observe_property('interpolation', 'native', function(_, interpolation)
	if interpolation == nil or interpolation == last_interpolation then return end
	last_interpolation = interpolation
	mp.osd_message( (interpolation and '☑︎' or '☐') .. ' Interpolation')
end)



-- Show Cache Sizes
local function show_cache_status()
	local cache_speed      = math.floor(  mp.get_property_native('cache-speed', 0) + 0.5 )
	local demux_state      = mp.get_property_native('demuxer-cache-state', {})
	local demux_fwd        = math.floor( ((demux_state and demux_state['fw-bytes'])    and demux_state['fw-bytes']    or 0) / 1048576 + 0.5 )
	local demux_total      = math.floor( ((demux_state and demux_state['total-bytes']) and demux_state['total-bytes'] or 0) / 1048576 + 0.5 )
	local demux_ranges     = demux_state['seekable-ranges'] and #demux_state['seekable-ranges'] or 0
	local demux_duration   = math.floor(  mp.get_property_native('demuxer-cache-duration', 0) + 0.5 )
	local demux_network    = mp.get_property_native('demuxer-via-network', false)
	local paused_for_cache = mp.get_property_native('paused-for-cache', false)
	local buffering_state  = math.floor( mp.get_property_native('cache-buffering-state', 0) + 0.5 )
	
	local demux_string     = demux_ranges > 0
	                         and ('☑︎ Cache: %.2d/%.2d MiB (%dm%.2ds)   '):format(demux_fwd, demux_total, math.floor(demux_duration / 60), math.floor(demux_duration % 60))
	                         or   '☐ Cache'
	local speed_string     = demux_network
	                         and ((cache_speed < 1048576) 
	                             and ('Speed: %s KB/s   '):format(math.floor(cache_speed / 1024))
	                             or  ('Speed: %s MB/s   '):format(math.floor(cache_speed / 1048576)))
	                         or  ''
	local pause_string     = paused_for_cache
	                         and ('Paused for buffering... %d%%   '):format(buffering_state)
	                         or  ''
	
	mp.osd_message( demux_string  .. speed_string .. pause_string)
end
mp.register_script_message('Show-Cache', show_cache_status)
mp.observe_property('cache-buffering-state', 'native', function() if mp.get_property_native('paused-for-cache', false) then show_cache_status() end end)
