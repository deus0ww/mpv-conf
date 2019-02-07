-- deus0ww - 2019-02-07

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'



-- Show File in Finder
mp.register_script_message('ShowInFinder', function()
	local path = mp.get_property('path', ''):gsub('edl://', ''):gsub(';/', '" /"')
	msg.debug('Show in Finder:', path)
	if path and path ~= '' then os.execute( ('open -R "%s"'):format(path) ) end
end)



-- OnTop only while playing
local PROP_ONTOP = 'ontop'
local PROP_PAUSE = 'pause'
local ontop      = mp.get_property(PROP_ONTOP)
local paused     = mp.get_property_bool(PROP_PAUSE)

mp.observe_property(PROP_PAUSE, 'bool', function(paused)
    if paused then
		ontop = mp.get_property(PROP_ONTOP)
		mp.set_property(PROP_ONTOP, 'no')
	else
		mp.set_property(PROP_ONTOP, ontop)
    end
end)

mp.observe_property(PROP_ONTOP, 'bool', function(current_ontop)
	if paused and current_ontop then ontop = current_ontop end
end)



-- Pause on Minimize
--	mp.observe_property('window-minimized', 'bool', function(minimized)
--		if minimized then
--			paused = mp.get_property_bool(PROP_PAUSE)
--			mp.set_property_bool(PROP_PAUSE, 'yes')
--		else
--			mp.set_property_bool(PROP_PAUSE, paused)
--		end
--	end)
