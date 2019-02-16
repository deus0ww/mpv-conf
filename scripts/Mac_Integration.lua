-- deus0ww - 2019-02-11

local mp      = require 'mp'
local msg     = require 'mp.msg'



-- Show File in Finder
mp.register_script_message('ShowInFinder', function()
	local path = mp.get_property_native('path', ''):gsub('edl://', ''):gsub(';/', '" /"')
	msg.debug('Show in Finder:', path)
	if path and path ~= '' then os.execute( ('open -R "%s"'):format(path) ) end
end)



-- OnTop only while playing
local PROP_ONTOP = 'ontop'
local PROP_PAUSE = 'pause'
local last_ontop = mp.get_property_native(PROP_ONTOP, false)
local last_pause = mp.get_property_native(PROP_PAUSE, false)

mp.observe_property(PROP_PAUSE, 'native', function(_, pause)
	msg.debug('Pause:', pause)
    if pause then
    	msg.debug('Paused - Disabling OnTop')
		last_ontop = mp.get_property_native(PROP_ONTOP)
		mp.set_property_native(PROP_ONTOP, false)
	else
		msg.debug('Unpaused - Restoring OnTop')
		mp.set_property_native(PROP_ONTOP, last_ontop)
    end
end)

-- Pause on Minimize
--	mp.observe_property('window-minimized', 'native', function(_, minimized)
--		msg.debug('Minimized:', minimized)
--		if minimized then
--			msg.debug('Minimized - Pausing')
--			last_pause = mp.get_property_native(PROP_PAUSE, false)
--			mp.set_property_native(PROP_PAUSE, true)
--		else
--			msg.debug('Unminimized - Restoring Pause')
--			mp.set_property_native(PROP_PAUSE, last_pause)
--		end
--	end)
