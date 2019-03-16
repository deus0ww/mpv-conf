-- deus0ww - 2019-03-16

local mp      = require 'mp'

local filter_name, lowpass_name, highpass_name = 'VoicePass', 'LowPass', 'HighPass'

local state = { lowpass_string  = nil, lowpass_new = false,
				highpass_string = nil, highpass_new = false, }

local function format_filter_string(filter_string)
	return filter_string:find('=') == nil and filter_string or filter_string:gsub('=', ' [', 1):gsub(':', ' ') .. ']'
end

local function show_status()
	local lowpass_string  = format_filter_string(state.lowpass_string)
	local highpass_string = format_filter_string(state.highpass_string)
	if lowpass_string == '' and highpass_string == '' then
		mp.osd_message('☐ VoiceBandPass')
	else
		mp.osd_message('☑︎ VoiceBandPass:  ' .. highpass_string .. '  ' .. lowpass_string)
	end
end

local function register_script()
	for _, cmd in ipairs({ '-cycle+', '-cycle-', '-toggle', '-enable', '-disable' }) do
		mp.register_script_message(filter_name .. cmd,  function() 
			mp.command_native({'script-message', lowpass_name  .. cmd, 'yes'})
			mp.command_native({'script-message', lowpass_name  .. '-status', 'yes'})
			mp.command_native({'script-message', highpass_name .. cmd, 'yes'})
			mp.command_native({'script-message', highpass_name .. '-status', 'yes'})
		end)
	end
	mp.register_script_message(lowpass_name  .. '-state', function(lowpass_string)  state.lowpass_string,  state.lowpass_new  = lowpass_string,  true end)
	mp.register_script_message(highpass_name .. '-state', function(highpass_string) state.highpass_string, state.highpass_new = highpass_string, true end)
end
register_script()

mp.register_idle(function()
	if state and state.lowpass_new and state.highpass_new then
		state.lowpass_new = false
		state.highpass_new = false
		show_status()
	end
end)
