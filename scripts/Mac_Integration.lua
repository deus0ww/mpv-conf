-- deus0ww - 2019-03-16

local mp      = require 'mp'
local msg     = require 'mp.msg'



-- Show File in Finder
mp.register_script_message('ShowInFinder', function()
	local path = mp.get_property_native('path', '')
	msg.debug('Show in Finder:', path)
	if path == '' then return end
	local cmd = {'run', 'open'}
	if path:find('http://') ~= nil or path:find('https://') ~= nil then
	elseif path:find('edl://') ~= nil then
		cmd[#cmd+1] = '-R'
		path = path:gsub('edl://', ''):gsub(';/', '" /"')
	elseif path:find('file://') ~= nil then
		cmd[#cmd+1] = '-R'
		path = path:gsub('file://', '')
	else
		cmd[#cmd+1] = '-R'
	end
	cmd[#cmd+1] = path
	mp.command_native(cmd)
end)



-- Move to Trash -- Requires: https://github.com/ali-rantakari/trash
mp.register_script_message('MoveToTrash', function()
	local path = mp.get_property_native('path', ''):gsub('edl://', ''):gsub(';/', '" /"')
	msg.debug('Moving to Trash:', path)
	if path and path ~= '' then
		mp.command_native({'run', 'trash', '-F', path})
		mp.osd_message('Trashing succeeded.')
	else
		mp.osd_message('Trashing failed.')
	end
end)



-- OnTop only while playing
local PROP_ONTOP = 'ontop'
local PROP_PAUSE = 'pause'
local last_ontop = mp.get_property_native(PROP_ONTOP, false)
local last_pause = mp.get_property_native(PROP_PAUSE, false)

mp.observe_property(PROP_ONTOP, 'native', function(_, ontop)
	mp.osd_message( (ontop and '☑︎' or '☐') .. ' On Top')
end)

mp.observe_property(PROP_PAUSE, 'native', function(_, pause)
	msg.debug('Pause:', pause)
    if pause then
		last_ontop = mp.get_property_native(PROP_ONTOP, false)
		if last_ontop then
			msg.debug('Paused - Disabling OnTop')
			mp.command('async no-osd set ontop no')
		end
	else
		if last_ontop ~= mp.get_property_native(PROP_ONTOP, false) then
			msg.debug('Unpaused - Restoring OnTop')
			mp.command('async no-osd set ontop ' .. (last_ontop and 'yes' or 'no'))
		end
    end
end)

-- Pause on Minimize
mp.observe_property('window-minimized', 'native', function(_, minimized)
	msg.debug('Minimized:', minimized)
	if minimized then
		msg.debug('Minimized - Pausing')
		last_pause = mp.get_property_native(PROP_PAUSE, false)
		mp.set_property_native(PROP_PAUSE, true)
	else
		msg.debug('Unminimized - Restoring Pause')
		mp.set_property_native(PROP_PAUSE, last_pause)
	end
end)
