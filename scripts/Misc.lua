-- deus0ww - 2019-02-26

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'



-- Cycling OSD without 'always'
local osc_vis, alt_vis = 'auto', 'never'
mp.register_script_message('OSC-vis-cycle', function()
	osc_vis, alt_vis = alt_vis, osc_vis
	mp.commandv('async', 'script-message', 'osc-visibility', osc_vis)
end)



-- Property Changer
local function change_prop(action, property, value)
	mp.commandv('async', 'no-osd', action, property, value)
	mp.commandv('async', 'show-text', ('%s:% 4d'):format(property:gsub('^%l', string.upper), mp.get_property_native(property, 0)))
end
mp.register_script_message('Add', function(property, value) change_prop('add', property, value) end)
mp.register_script_message('Set', function(property, value) change_prop('set', property, value) end)



-- Cycle Video Rotation
mp.register_script_message('Video-Rotate', function(degrees) 
	change_prop('set', 'video-rotate', (degrees + mp.get_property_number('video-rotate', 0)) % 360)
end)



-- Show Cache Sizes
local mark = { auto = '☐', yes = '☑︎', no = '☒' }

local function show_cache_status()
	local cache            = mp.get_property('cache', '')
	local cache_used       = math.floor( (mp.get_property_native('cache-used', 0) / 1024) + 0.5 )
	local cache_size       = math.floor( (mp.get_property_native('cache-size', 0) / 1024) + 0.5 )
	local cache_speed      = math.floor(  mp.get_property_native('cache-speed', 0) + 0.5 )
	local demux_state      = mp.get_property_native('demuxer-cache-state', {})
	local demux_fwd        = math.floor( ((demux_state and demux_state['fw-bytes'])    and demux_state['fw-bytes']    or 0) / 1048576 + 0.5 )
	local demux_total      = math.floor( ((demux_state and demux_state['total-bytes']) and demux_state['total-bytes'] or 0) / 1048576 + 0.5 )
	local demux_duration   = math.floor(  mp.get_property_native('demuxer-cache-duration', 0) + 0.5 )
	local demux_network    = mp.get_property_native('demuxer-via-network', false)
	local paused_for_cache = mp.get_property_native('paused-for-cache', false)
	local buffering_state  = math.floor( mp.get_property_native('cache-buffering-state', 0) + 0.5 )
	
	local cache_string     = ('%s Cache: %.2d/%.2d MiB   '):format(mark[cache], cache_used, cache_size)
	local demux_string     = ('Demuxer: %.2d/%.2d MiB (%dm%.2ds)   '):format(demux_fwd, demux_total, math.floor(demux_duration / 60), math.floor(demux_duration % 60))
	local speed_string     = demux_network and ((cache_speed < 1048576) and ('Speed: %s KB/s   '):format(math.floor(cache_speed / 1024)) or ('Speed: %s MB/s   '):format(math.floor(cache_speed / 1048576))) or ''
	local pause_string     = paused_for_cache and ('Paused for buffering... %d%%   '):format(buffering_state) or ''
	
	mp.osd_message( cache_string .. demux_string  .. speed_string .. pause_string)
end
mp.register_script_message('Show-Cache', show_cache_status)
mp.observe_property('cache-buffering-state', 'native', function() if mp.get_property_native('paused-for-cache', false) then show_cache_status() end end)
