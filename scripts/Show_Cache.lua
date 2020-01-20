-- deus0ww - 2020-01-21

local mp      = require 'mp'
local msg     = require 'mp.msg'



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
	                         and ('■ Cache: %.2d/%.2d MiB (%dm%.2ds)   '):format(demux_fwd, demux_total, math.floor(demux_duration / 60), math.floor(demux_duration % 60))
	                         or   '□ Cache'
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
