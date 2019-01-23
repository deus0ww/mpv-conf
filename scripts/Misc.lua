-- deus0ww - 2019-01-22

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
	mp.commandv('async', 'show-text', ('%s:% 4d'):format(property:gsub("^%l", string.upper), mp.get_property_native(property)))
end
mp.register_script_message('Add', function(property, value) change_prop('add', property, value) end)
mp.register_script_message('Set', function(property, value) change_prop('set', property, value) end)



-- Cycle Video Rotation
mp.register_script_message("Video-Rotate", function(degrees) 
	change_prop('set', 'video-rotate', (degrees + mp.get_property_number("video-rotate")) % 360)
end)
