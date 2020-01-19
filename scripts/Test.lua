local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



mp.register_script_message('log-audio-device-list', function()
	msg.debug('audio-device-list', utils.to_string(mp.get_property_native('audio-device-list', {})))
end)

mp.register_script_message('log-hidpi-scale', function()
	msg.debug('display-hidpi-scale', mp.get_property_native('display-hidpi-scale', -1.0))
end)

mp.observe_property('display-hidpi-scale', 'native', function(name, scale)
	msg.debug(name, scale)
end)
