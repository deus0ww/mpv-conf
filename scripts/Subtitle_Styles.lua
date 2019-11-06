-- deus0ww - 2019-11-06

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

local codec_type = {
	dvb_subtitle = 'bitmap',
	dvd_subtitle = 'bitmap',
	hdmv_pgs_subtitle = 'bitmap',
}
setmetatable(codec_type, {__index = function() return 'text' end})

local codec_profile = {
	bitmap = 'ww-subtitle-bitmap',
	text   = 'ww-subtitle-text',
}

local function get_sub_language(track_list, sid)
	for _, track in ipairs(track_list) do
		if track.type == 'sub' and track.lang and track.lang ~= '' and
		   (sid == track.id or (sid == 'auto' and track.default)) then
			for code, desc in pairs(language_codes) do
				if desc:find(track.lang:lower()) ~= nil then
					return code
				end
			end
		end
	end
	return 'und'
end

local function get_sub_type(track_list, sid)
	for _, track in ipairs(track_list) do
		if track.type == 'sub' and track.codec and track.codec ~= '' and
		   (sid == track.id or (sid == 'auto' and track.default)) then
		   return codec_type[track.codec:lower()]
		end
	end
end

mp.observe_property('sid', 'native', function(_, sid)
	if not sid or sid == 'no' then return end
	local track_list = mp.get_property_native('track-list', {})
	if #track_list <= 0 then return end
	
	-- Set Language Style
	local track_lang = get_sub_language(track_list, sid)
	local profile_lang = language_profiles[track_lang]
	mp.commandv('apply-profile', profile_lang)
	
	-- Set Codec Style
	local track_type = get_sub_type(track_list, sid)
	local profile_type = codec_profile[track_type]
	mp.commandv('apply-profile', profile_type)
	
	msg.debug(('SID: %s, Language: %s, Type: %s, Profiles: %s, %s'):format(sid, track_lang, track_type, profile_lang, profile_type))
end)