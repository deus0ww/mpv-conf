local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'



local function show_value(label, value)
	msg.debug(label .. ': ', value)
	mp.osd_message(label .. ': ' .. utils.to_string(value))
end

local get = mp.get_property_native



mp.register_script_message('get-audio-device-list', function()
	show_value('audio-device-list', utils.to_string(get('audio-device-list', {})))
end)

mp.register_script_message('get-hidpi-scale', function()
	show_value('display-hidpi-scale', get('display-hidpi-scale', -1.0))
end)

mp.register_script_message('get-path', function()
	show_value('get-path: ', get('path', 'x'))
end)

mp.register_script_message('get-extension', function()
	show_value('get-extension: ', get('filename', 'x'):match("^.+%.(.+)$"))
end)

mp.register_script_message('get-protocol', function()
	show_value('get-protocol: ', (get('path', 'x'):match("^(.+)://.+") or ''))
end)

mp.register_script_message('get-demuxer-via-network', function()
	show_value('get-demuxer-via-network: ', (get('demuxer-via-network') and 'yes' or 'no'))
end)

mp.register_script_message('get-sub-lang', function()
	local test = (function()
		for _, track in ipairs(get('track-list', {})) do
			if track.lang and track.type == 'sub' and (tostring(track.id) == tostring(get('sid','')) or (tostring(get('sid','')) == 'auto' and track.default)) then
				return track.lang:lower()
			end
			msg.debug(track.lang, track.type == 'sub', tostring(track.id) == sid)
		end
		return ''
	end)()
	show_value('get-sub-lang', test)
end)

mp.register_script_message('get-sub-type', function()
	local test = (function()
		for _, track in ipairs(get('track-list', {})) do
			if track.codec and track.type == 'sub' and (tostring(track.id) == tostring(get('sid','')) or (tostring(get('sid','')) == 'auto' and track.default)) then
				return track.codec:lower()
			end
		end
		return ''
	end)()
	show_value('get-sub-type', test)
end)
