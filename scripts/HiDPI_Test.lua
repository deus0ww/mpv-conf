local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'

mp.register_script_message('log-hidpi-scale', function()
	local scale = mp.get_property_native('display-hidpi-scale', -1.0)
	msg.debug('HIGH_DPI_TEST - LOG HIDPI SCALE:', scale)
end)

mp.observe_property('display-hidpi-scale', 'native', function(_, scale)
	msg.debug('HIGH_DPI_TEST - OBSERVING PROPERTY CHANGE:', scale)
end)