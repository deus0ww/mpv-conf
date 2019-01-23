-- deus0ww - 2019-01-22

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'

local eqs    = { 'brightness', 'contrast', 'gamma', 'hue', 'saturation' }
local lables = { brightness = 'Brightness', contrast = 'Contrast', gamma = 'Gamma', hue = 'Hue', saturation = 'Saturation' }

local profiles = { current_index = 1, last_index = 1, limit = 1 }
for i = 0, profiles.limit do 
	profiles[i] = {}
	for _, eq in pairs(eqs) do
		profiles[i][eq] = 0
	end	
end

local function show_status(eq)
	local profile = profiles[profiles.current_index]
	local id_string = ('%s EQ %d'):format(((profiles.current_index ~= 0) and '☑︎' or '☐'), profiles.current_index == 0 and profiles.last_index or profiles.current_index)
	local eq_string = eq and ('%s %+.2d'):format(lables[eq], profile[eq])
						 or  ('Brightness %+.2d, Contrast %+.2d, Gamma %+.2d, Hue %+.2d, Saturation %+.2d'):format(profile.brightness, profile.contrast, profile.gamma, profile.hue, profile.saturation)
	mp.osd_message(('%s: %s'):format(id_string, eq_string))
end

local function set_eq()
	for _, eq in ipairs(eqs) do
		mp.set_property_number(eq, profiles[profiles.current_index][eq])
	end
end

mp.register_script_message('Eq-cycle-', function()
	profiles.current_index = ((profiles.current_index - 2) % profiles.limit) + 1
	set_eq()
	show_status()
end)

mp.register_script_message('Eq-cycle+', function()
	profiles.current_index = (profiles.current_index % profiles.limit) + 1
	set_eq()
	show_status()
end)

mp.register_script_message('Eq-toggle', function()
	if profiles.current_index ~= 0 then
		profiles.last_index = profiles.current_index
		profiles.current_index = 0
	else
		profiles.current_index = profiles.last_index
	end
	set_eq()
	show_status()
end)

mp.register_script_message('Eq-reset', function()
	if profiles.current_index == 0 then profiles.current_index = profiles.last_index end
	for _, eq in pairs(eqs) do
		profiles[profiles.current_index][eq] = 0
	end
	set_eq()
	show_status()
end)

local function on_eq_set(eq, value)
	profiles[profiles.current_index][eq] = math.min(math.max(value, -100), 100)
	set_eq()
	show_status(eq)
end

local function on_eq_change(eq, amount)
	msg.info('eq:', eq, 'amount:', amount)
	if profiles.current_index == 0 then profiles.current_index = profiles.last_index end
	on_eq_set(eq, profiles[profiles.current_index][eq] + amount)
end

for _, eq in ipairs(eqs) do
	mp.register_script_message('Eq-' .. eq,           function(amount) on_eq_change(eq, amount) end)
	mp.register_script_message('Eq-' .. eq .. '-set', function(value)  on_eq_set   (eq, value)  end)
end
