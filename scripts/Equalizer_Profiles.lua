-- deus0ww - 2019-02-07

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'

local user_opts = {
	reset_on_load = true,
}
opt.read_options(user_opts, mp.get_script_name())

local eqs    = { 'brightness', 'contrast', 'gamma', 'hue', 'saturation' }
local lables = { brightness = 'Brightness', contrast = 'Contrast', gamma = 'Gamma', hue = 'Hue', saturation = 'Saturation' }

local profiles = { current_index = 1, last_index = 1, limit = 1 }

local function reset_profile(profile)
	for _, eq in pairs(eqs) do
		profile[eq] = 0
	end
end

local function reset_all()
	for i = 0, profiles.limit do 
		if not profiles[i] then profiles[i] = {} end
		reset_profile(profiles[i])
	end
	profiles.current_index = 1
	profiles.last_index    = 1
end
reset_all()

local function show_status(profile, eq)
	local id_string = ('%s EQ %d'):format(((profiles.current_index ~= 0) and '☑︎' or '☐'), profiles.current_index == 0 and profiles.last_index or profiles.current_index)
	local eq_string = eq and ('%s %+.2d'):format(lables[eq], profile[eq])
						 or  ('Brightness %+.2d, Contrast %+.2d, Gamma %+.2d, Hue %+.2d, Saturation %+.2d'):format(profile.brightness, profile.contrast, profile.gamma, profile.hue, profile.saturation)
	mp.osd_message(('%s: %s'):format(id_string, eq_string))
end

local function apply_profile(profile, eq)
	if eq then  -- Set one value
		mp.set_property_number(eq, profile[eq] and profile[eq] or 0)
	else        -- Set all values
		for _, eqx in pairs(eqs) do
			mp.set_property_number(eqx, profile[eqx] and profile[eqx] or 0)
		end
	end
end

mp.register_script_message('Eq-cycle-', function()
	msg.debug('EQ - Profile Down')
	profiles.current_index = ((profiles.current_index - 2) % profiles.limit) + 1
	local profile = profiles[profiles.current_index]
	apply_profile(profile)
	show_status(profile)
end)

mp.register_script_message('Eq-cycle+', function()
	msg.debug('EQ - Profile Up')
	profiles.current_index = (profiles.current_index % profiles.limit) + 1
	local profile = profiles[profiles.current_index]
	apply_profile(profile)
	show_status(profile)
end)

mp.register_script_message('Eq-toggle', function()
	msg.debug('EQ - Toggling')
	if profiles.current_index ~= 0 then
		profiles.last_index = profiles.current_index
		profiles.current_index = 0
	else
		profiles.current_index = profiles.last_index
	end
	local profile = profiles[profiles.current_index]
	apply_profile(profile)
	show_status(profile)
end)

mp.register_script_message('Eq-reset', function()
	msg.debug('EQ - Reseting')
	if profiles.current_index == 0 then profiles.current_index = profiles.last_index end
	local profile = profiles[profiles.current_index]
	reset_profile(profile)
	apply_profile(profile)
	show_status(profile)
end)

mp.register_event("file-loaded", function()
	local profile = profiles[profiles.current_index]
	if user_opts.reset_on_load then
		msg.debug('EQ - Reseting on Load')
		reset_all()
		apply_profile(profile)
	else
		msg.debug('EQ - Reloading')
		apply_profile(profile)
		show_status(profile)
	end
end)

local function on_eq_set(eq, value)
	msg.debug('EQ - Set:', eq, value)
	profiles[profiles.current_index][eq] = math.min(math.max(value, -100), 100)
	local profile = profiles[profiles.current_index]
	apply_profile(profile)
	show_status(profile, eq)
end

local function on_eq_change(eq, amount)
	msg.debug('EQ - Change:', eq, amount)
	if profiles.current_index == 0 then profiles.current_index = profiles.last_index end
	on_eq_set(eq, profiles[profiles.current_index][eq] + amount)
end

for _, eq in pairs(eqs) do
	mp.register_script_message('Eq-' .. eq,           function(amount) on_eq_change(eq, amount) end)
	mp.register_script_message('Eq-' .. eq .. '-set', function(value)  on_eq_set   (eq, value)  end)
end
