-- deus0ww - 2020-03-12

-- Requires:
--   - macOS >= 10.9
--   - Tag: https://github.com/jdberry/tag/


local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'


--------------
-- Tag Info --
--------------
local tag_order = { '1', '2', '3', '4', '5', '6', '7' }
local tag_color = {
	['1'] = '2521FB',
	['2'] = '0982FD',
	['3'] = '09C4FE',
	['4'] = '2BD756',
	['5'] = 'F69B1D',
	['6'] = 'DA56BE',
	['7'] = '7F7B7B', 
}


-------------
-- Display --
-------------
local ass_start  = mp.get_property_osd('osd-ass-cc/0', '')
local ass_stop   = mp.get_property_osd('osd-ass-cc/1', '')
local ass_format = '{\\1cH&%s&\\3c&H%s&\\4c&H000000&\\1a&H%s&\\3a&H%s&\\4a&H90&\\bord2\\shad0.01\\fs80}•'
local function show_tags(tags)
	if not tags then return end
	local tag_string, color = '{\\an8}', 'FFFFFF'
	for _, tag in ipairs(tag_order) do
		color = tag_color[tag]
		tag_string = tag_string .. ( tags[tag] and (ass_format):format(color, color, '20', '20') or (ass_format):format(color, color, 'D0', '90') )
	end
	mp.osd_message(ass_start .. tag_string .. ass_stop)
end


-----------------------
-- Tag Cmd Execution --
-----------------------
local function file_exists(path)
	local file = io.open(path, 'rb')
	if not file then return false end
	local _, _, code = file:read(1)
	file:close()
	return code == nil
end

function lines(s)
	if s:sub(-1) ~= '\n' then s = s..'\n' end
	return s:gmatch('(.-)\n')
end

local function run_tag(cmd)
	if not file_exists(cmd[#cmd]) then return end
	local res = mp.command_native({name='subprocess', args=cmd, playback_only = true, capture_stdout = true, capture_stderr = true,})
	msg.debug('Command:', utils.to_string(cmd), '|', 'Results:', utils.to_string(res))
	local results = {}
	if (res and res.stdout) then for line in lines(res.stdout) do results[line] = true end end
	return results
end

local function add_tag(path, tag)  return run_tag({'tag', '-a', tag, path}) end
local function del_tag(path, tag)  return run_tag({'tag', '-r', tag, path}) end
local function read_tag(path)      return run_tag({'tag', '-l', '-N', '-g', path}) end


------------------
-- MPV Triggers --
------------------
local path = ''
mp.register_event('file-loaded', function()
	path = mp.get_property_native('path', '')
	msg.debug('Tagger Loaded:', path)
end)

mp.register_script_message('Tag-add', function(tag)
	msg.debug('Tag Add:', tag)
	if not tag or tag == '' then return end
	local current_tags = read_tag(path)
	if current_tags and not current_tags[tag] then add_tag(path, tag) end
	show_tags(read_tag(path))
end)

mp.register_script_message('Tag-del', function(tag)
	msg.debug('Tag Delete:', tag)
	if not tag or tag == '' then return end
	local current_tags = read_tag(path)
	if tag == '\\*' or (current_tags and current_tags[tag]) then del_tag(path, tag) end
	show_tags(read_tag(path))
end)

mp.register_script_message('Tag-toggle', function(tag)
	msg.debug('Tag Toggling:', tag)
	if not tag or tag == '' then return end
	local current_tags = read_tag(path)
	if current_tags and current_tags[tag] then del_tag(path, tag) else add_tag(path, tag) end
	show_tags(read_tag(path))
end)

mp.register_script_message('Tag-show', function()
	msg.debug('Tag Show')
	show_tags(read_tag(path))
end)
