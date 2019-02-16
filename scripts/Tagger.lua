-- deus0ww - 2019-02-16

-- Requires:
--   - macOS >= 10.9
--   - Tag: https://github.com/jdberry/tag/
--   - Lua io.popen support



local mp      = require 'mp'
local assdraw = require 'mp.assdraw'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'



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

local ass_start  = mp.get_property_osd('osd-ass-cc/0', '')
local ass_stop   = mp.get_property_osd('osd-ass-cc/1', '')
local ass_format = '{\\1c&%s&\\3c&%s&\\4c&000000&\\1a&H%s&\\3a&%s&\\4a&90&\\bord2\\shad0.01\\fs80}•'
local function show_tags(tags)
	local tag_string, color = '{\\an8}', 'FFFFFF'
	for _, tag in ipairs(tag_order) do
		color = tag_color[tag]
		tag_string = tag_string .. ( tags[tag] and (ass_format):format(color, color, '20', '20') or (ass_format):format(color, color, 'D0', '90') )
	end
	mp.osd_message(ass_start .. tag_string .. ass_stop)
end



local function run_tag(cmd)
	msg.debug('Command:', cmd)
	local result = io.popen(cmd)
	if result then result:close() end
end

local function add_tag(path, tag) run_tag('tag -a ' .. tag .. ' ' .. path) end
local function del_tag(path, tag) run_tag('tag -r ' .. tag .. ' ' .. path) end

local function read_tag(path)
	local cmd = 'tag -l -N -g ' .. path
	msg.debug('Command:', cmd)
	local result = io.popen(cmd)
	local tags = {}
	if not result then return tags end
	for tag in result:lines() do
		tags[tag] = true
	end
	result:close()
	msg.debug('Read Tags:', utils.to_string(tags))
	return tags
end



local path = ''
mp.register_event('file-loaded', function()
	msg.debug('Tag Add:', tag)
	path = ('"%s"'):format(mp.get_property_native('path', ''))
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
	msg.debug('Tag Show', tag)
	show_tags(read_tag(path))
end)
