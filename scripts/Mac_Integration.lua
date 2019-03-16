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
