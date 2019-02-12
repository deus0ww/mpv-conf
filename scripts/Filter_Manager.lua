-- deus0ww - 2019-02-12

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

local function show_status(filter, no_osd)
	if not no_osd then
		local filter_string = filter.filters[filter.current_index]
		filter_string = filter_string:find('=') == nil and filter_string or filter_string:gsub('=', ' [', 1):gsub(':', ' ') .. ']'
		local index_string  = #filter.filters > 1 and (' %s'):format(filter.current_index) or ''
		mp.osd_message( ('%s %s%s:  %s'):format( (filter.enabled and '☑︎' or '☐'), filter.name, index_string, filter_string ) )
	end
	mp.commandv('async', 'script-message', filter.name .. (filter.enabled and '-enabled' or '-disabled'))
end

local cmd_prefix = 'async no-osd %s '
local cmd = {
	enable  = function(filter) mp.command((cmd_prefix .. 'add @%s:%s' ):format(type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
	disable = function(filter) mp.command((cmd_prefix .. 'add @%s:!%s'):format(type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
	add     = function(filter) mp.command((cmd_prefix .. 'add @%s:!%s'):format(type_map[filter.filter_type], filter.name, filter.filters[filter.current_index])) end,
	remove  = function(filter) mp.command((cmd_prefix .. 'del @%s'    ):format(type_map[filter.filter_type], filter.name)) end,
	clear   = function() mp.set_property_native(type_map['audio'], {}) mp.set_property_native(type_map['video'], {}) end,
}

local function apply_all()
	cmd.clear()
	for i = 1, #filter_list do
		if filter_list[i].enabled then cmd.enable(filter_list[i]) end
	end
end

local function cycle_filter_up(filter, no_osd)
	msg.debug('Filter - Up:', filter.name)
	if filter.current_index == 0 then filter.enabled = true end
	filter.current_index = (filter.current_index % #filter.filters) + 1
	apply_all()
	show_status(filter, no_osd)
end

local function cycle_filter_dn(filter, no_osd)
	msg.debug('Filter - Down:', filter.name)
	if filter.current_index == 0 then filter.enabled = true end
	filter.current_index = ((filter.current_index - 2) % #filter.filters) + 1
	apply_all()
	show_status(filter, no_osd)
end

local function toggle_filter(filter, no_osd)
	msg.debug('Filter - Toggling:', filter.name)
	if filter.current_index == 0 then filter.current_index = 1 end
	filter.enabled = not filter.enabled
	apply_all()
	show_status(filter, no_osd)
end

local function enable_filter(filter, no_osd)
	msg.debug('Filter - Enabling:', filter.name)
	filter.enabled = true
	apply_all()
	show_status(filter, no_osd)
end

local function disable_filter(filter, no_osd)
	msg.debug('Filter - Disabling:', filter.name)
	filter.enabled = false
	apply_all()
	show_status(filter, no_osd)
end

local function register_filter(filter)
	if filter.default_on_load == nil then filter.default_on_load = defaults.default_on_load end
	if filter.reset_on_load   == nil then filter.reset_on_load   = defaults.reset_on_load   end
	filter.current_index = 1
	filter.enabled = filter.default_on_load
	table.insert(filter_list, filter)
	if filter.enabled then cmd.enable(filter) else cmd.add(filter) end
	mp.register_script_message(filter.name .. '-cycle+',  function(no_osd) cycle_filter_up(filter, no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-cycle-',  function(no_osd) cycle_filter_dn(filter, no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-toggle',  function(no_osd) toggle_filter(filter,   no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-enable',  function(no_osd) enable_filter(filter,   no_osd == 'yes') end)
	mp.register_script_message(filter.name .. '-disable', function(no_osd) disable_filter(filter,  no_osd == 'yes') end)
	msg.info(filter.name, 'registered')
end

mp.register_event("file-loaded", function()
	msg.debug('Setting Filters...')
	for _, filter in ipairs(filter_list) do
		if filter.reset_on_load then
			filter.enabled = filter.default_on_load
			filter.current_index = filter.default_index and filter.default_index or 1
		end
	end
	apply_all()
end)

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
