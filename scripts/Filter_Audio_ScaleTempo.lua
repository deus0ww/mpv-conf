-- deus0ww - 2022-08-18

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'

local filter_name = 'ScaleTempo'

local function show_status(filter_enabled)
	local filter_params = 'none'
	for _, f in ipairs(mp.get_property_native('af')) do
		if f.label == filter_name then
			filter_params = f.name .. ' ' .. utils.to_string(f.params):gsub('{', '['):gsub('}', ']'):gsub(' = ', '='):gsub('"', ''):gsub(',', '')
			break
		end
	end
	mp.osd_message(string.format('Speed: %.2f\n%s %s:  %s', mp.get_property('speed'), (filter_enabled and '■' or '□'), filter_name, filter_params))
end

mp.register_script_message(filter_name .. '-enabled',  function()
	mp.commandv('set', 'audio-pitch-correction', 'yes')
	show_status(true)
end)
mp.register_script_message(filter_name .. '-disabled', function()
	mp.commandv('set', 'audio-pitch-correction', 'no')
	show_status(false)
end)

local previous_speed = mp.get_property_native('speed')

mp.observe_property('speed', 'number', function(_, speed)
	if not speed or speed == previous_speed then return end
	msg.debug('AutoScaleTempo - Speed Changed - ', speed)
	previous_speed = speed
	mp.command_native({'script-message', filter_name .. ((speed == 1) and '-disable' or '-enable'), 'yes'})
end)
