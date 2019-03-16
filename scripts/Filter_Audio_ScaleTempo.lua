-- deus0ww - 2019-03-16

local mp      = require 'mp'
local msg     = require 'mp.msg'

local filter_name = 'ScaleTempo'

local function show_status(filter_enabled)
	mp.osd_message(string.format('Speed: %.2f\n%s %s', mp.get_property('speed'), (filter_enabled and '☑︎' or '☐'), filter_name))
end

mp.register_script_message(filter_name .. '-enabled',  function() show_status(true)  end)
mp.register_script_message(filter_name .. '-disabled', function() show_status(false) end)

local previous_speed = mp.get_property_native('speed')

mp.observe_property('speed', 'number', function(_, speed)
	msg.debug('AutoScaleTempo - Speed Changed')
	if not speed or speed == previous_speed then return end
	previous_speed = speed
	mp.command_native_async({'script-message', filter_name .. ((speed == 1) and '-disable' or '-enable'), 'yes'}, function() end)
end)
