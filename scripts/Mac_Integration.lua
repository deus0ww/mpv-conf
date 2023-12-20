-- deus0ww - 2020-12-18

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'
local opt     = require 'mp.options'

local user_opts = {
	exec_path = '',
}
opt.read_options(user_opts, mp.get_script_name())

local function subprocess(label, args)
	-- msg.debug(label..'-Arg', utils.to_string(args))
	local res, err = mp.command_native({name='subprocess', args=args, playback_only = false, capture_stdout = true, capture_stderr = true,})
	-- msg.debug(label..'-Res', utils.to_string(res))
	-- msg.debug(label..'-Err', utils.to_string(err))
	return ((err == nil) and (res.stderr == nil or res.stderr == '') and (res.error_string == nil or res.error_string == '')), res
end



-- Show Finder
mp.register_script_message('ShowFinder', function()
	subprocess('ShowFinder', {'open', '-a', 'Finder'})
end)



-- Show File in Finder
mp.register_script_message('ShowInFinder', function()
	local path = mp.get_property_native('path', '')
	msg.debug('Show in Finder:', path)
	if path == '' then return end
	local cmd = {'open'}
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
	subprocess('ShowInFinder', cmd)
end)



-- Move to Trash -- Requires: https://github.com/ali-rantakari/trash
mp.register_script_message('MoveToTrash', function()
	opt.read_options(user_opts, mp.get_script_name())
	if mp.get_property_native('demuxer-via-network', true) then
		mp.osd_message('Trashing failed: File is remote.')
		return
	end

	local path = mp.get_property_native('path', ''):gsub('edl://', ''):gsub(';/', '" /"')
	if not path or path == '' then
		mp.osd_message('Trashing failed: Invalid Path')
		return
	end

	msg.debug('Moving to Trash:', path)
	local success, res = subprocess('MoveToTrash', {user_opts.exec_path .. 'trash', '-v',path })
	mp.osd_message(success and 'Trashed' or 'Trashing failed: ' .. res.stderr)
end)



-- Open From Clipboard - One URL per line
function lines(s)
	if s:sub(-1) ~= '\n' then s = s..'\n' end
	return s:gmatch('(.-)\n')
end

mp.register_script_message('OpenFromClipboard', function()
	local osd_msg = 'Opening From Clipboard: '

	local success, res = subprocess('OpenFromClipboard', {'pbpaste'})
	if not success or res == nil or res.stdout == nil or res.stdout == '' then
		mp.osd_message(osd_msg .. 'failed.')
		return
	end

	local mode, paste = 'replace', {}
	for line in lines(res.stdout) do
		msg.debug('loadfile', line, mode)
		mp.commandv('loadfile', line, mode)
		mode = 'append'
		paste[#paste+1] = line
	end

	local msg = osd_msg
	if #paste > 0 then msg = msg .. '\n' .. paste[1] end
	if #paste > 1 then msg = msg .. (' ... and %d other URL(s).'):format(#paste-1) end
	mp.osd_message(msg, 6.0)
end)
