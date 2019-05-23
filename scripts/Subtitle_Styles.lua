-- deus0ww - 2019-05-23

local mp      = require 'mp'
local msg     = require 'mp.msg'

-- Language Definitions: [language key] = descriptive search string. Must be lowercase; should have 'und' as the last entry.
local language_codes = {
	eng  = 'english',
	jpn  = 'japanese,jpn',
	tha  = 'thai',
	und  = 'unknown,undetermined',
}

local language_profiles = {
	eng = 'ww-subtitle-english',
	tha = 'ww-subtitle-thai',
	und = 'ww-subtitle-english',
}

local function get_sub_language(track_list, sid)
	for _, track in ipairs(track_list) do
		msg.error('track.default', track.default, 'track.lang', track.lang)
		if track.type == 'sub' and track.lang and track.lang ~= '' and
		   (sid == track.id or (sid == 'auto' and track.default)) then
			for lang, _ in pairs(language_codes) do
				if language_codes[lang]:find(track.lang:lower()) ~= nil then
					return lang
				end
			end
		end
	end
	return 'und'
end

mp.observe_property('sid', 'native', function(_, sid)
	if not sid or sid == 'no' then return end
	local track_list = mp.get_property_native('track-list', {})
	if #track_list <= 0 then return end
	local track_lang = get_sub_language(track_list, sid)
	local profile = language_profiles[track_lang]
	msg.debug(('SID: %s, Language: %s, Profile: %s'):format(sid, track_lang, profile))
	mp.commandv('apply-profile', profile)
end)