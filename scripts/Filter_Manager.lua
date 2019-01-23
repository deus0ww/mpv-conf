-- deus0ww - 2019-01-22

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'

local function parse_json(json)
	local tab, err, _ = utils.parse_json(json, true)
	if err then msg.error('Parsing JSON failed:', err) end
	if tab then return tab else return {} end
end

local filter_list = {}
local type_map    = { video = 'vf', audio = 'af' }
local defaults    = { default_on_load = false, reset_on_load = true }

local function announce_status(filter, no_osd)
	if not no_osd      then mp.osd_message(string.format('%s %s %i: %s',(filter.enabled and '☑︎' or '☐'), filter.name, filter.current_index, filter.filters[filter.current_index])) end
	mp.commandv('async', 'script-message', filter.name .. (filter.enabled and '-enabled' or '-disabled'))
end

local command = {
	add     = function(filter) mp.command(string.format('async no-osd %s add @%s:!%s', type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
	remove  = function(filter) mp.command(string.format('async no-osd %s del @%s',     type_map[filter.filter_type], filter.name)) end,
	enable  = function(filter) mp.command(string.format('async no-osd %s add @%s:%s',  type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
	disable = function(filter) mp.command(string.format('async no-osd %s add @%s:!%s', type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
}

local function enable_filter(filter, no_osd)
	filter.enabled = true
	command.enable(filter)
	announce_status(filter, no_osd)
end

local function disable_filter(filter, no_osd)
	filter.enabled = false
	command.disable(filter)
	announce_status(filter, no_osd)
end

local function cycle_filter_up(filter, no_osd)
	if filter.current_index == 0 then filter.enabled = true end
	filter.current_index = (filter.current_index % #filter.filters) + 1
	if filter.enabled then command.enable(filter) end
	announce_status(filter, no_osd)
end

local function cycle_filter_dn(filter, no_osd)
	if filter.current_index == 0 then filter.enabled = true end
	filter.current_index = ((filter.current_index - 2) % #filter.filters) + 1
	if filter.enabled then command.enable(filter) end
	announce_status(filter, no_osd)
end

local function toggle_filter(filter, no_osd)
	if filter.current_index == 0 then filter.current_index = 1 end
	if filter.enabled then command.disable(filter) else command.enable(filter) end
	filter.enabled = not filter.enabled
	announce_status(filter, no_osd)
end

mp.observe_property('video-params', 'native', function()
	for _, filter in ipairs(filter_list) do
		if filter.reset_on_load then
			if filter.enabled ~= filter.default_on_load then toggle_filter(filter) end
			filter.current_index = 1
		end
	end
end)

local function register_filter(filter)
	if filter.default_on_load == nil then filter.default_on_load = defaults.default_on_load end
	if filter.reset_on_load   == nil then filter.reset_on_load   = defaults.reset_on_load   end
	filter.current_index = 1
	filter.enabled = filter.default_on_load
	table.insert(filter_list, filter)
	if filter.enabled then command.enable(filter) else command.add(filter) end
	mp.register_script_message(filter.name .. '-cycle+',  function(no_osd) cycle_filter_up(filter, no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-cycle-',  function(no_osd) cycle_filter_dn(filter, no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-toggle',  function(no_osd) toggle_filter(filter,   no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-enable',  function(no_osd) enable_filter(filter,   no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-disable', function(no_osd) disable_filter(filter,  no_osd == 'yes') end)
	msg.info(filter.name, 'registered')
end

mp.register_script_message('Filter_Registration', function(json)
	if not json then return end
	register_filter(parse_json(json))
end)

mp.register_script_message('Filters_Registration', function(json)
	if not json then return end
	local filters = parse_json(json)
	for _, filter in ipairs (filters) do
		register_filter(filter)
	end
end)

mp.commandv('async', 'script-message', 'Filter_Registration_Request', mp.get_script_name())
