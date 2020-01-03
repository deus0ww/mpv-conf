-- deus0ww - 2020-01-03

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
	und = 'ww-subtitle-thai',
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
	return 'text'
end

local last = { profile_lang = 'eng', profile_type = 'text', }
local function set_profile(track_lang, track_type)
	local profile_lang, profile_type = language_profiles[track_lang], codec_profile[track_type]
	if last.profile_lang ~= profile_lang then
		last.profile_lang = profile_lang
		msg.debug('Applying Profile:', profile_lang)
		mp.commandv('apply-profile', profile_lang)
	else
		msg.debug('Skipping Profile:', profile_lang)
	end
	if last.profile_type ~= profile_type then
		last.profile_type = profile_type
		msg.debug('Applying Profile:', profile_type)
		mp.commandv('apply-profile', profile_type)
	else
		msg.debug('Skipping Profile:', profile_type)
	end
end

local p = {
	['sid'] = 0,
	['track-list'] = {},
	['sub-visibility'] = false,
}

local function on_change(k, v)
	if     k == 'sid'            then p['sid']            = v ~= nil and v or 0
	elseif k == 'track-list'     then p['track-list']     = v or {}
	elseif k == 'sub-visibility' then p['sub-visibility'] = v ~= nil and v or false
	end
	local sid, vis, track_list = p['sid'], p['sub-visibility'], p['track-list']
	local track_lang, track_type
	if not sid or sid == 'no' or not track_list or #track_list <= 0 or not vis then
		track_lang, track_type = 'eng', 'text'
	else
		track_lang, track_type = get_sub_language(track_list, sid), get_sub_type(track_list, sid)
	end
	msg.debug(('Visibility: %s, SID: %s, Language: %s, Type: %s'):format(vis and 'yes' or 'no', tostring(sid), track_lang, track_type))
	set_profile(track_lang, track_type)
end

mp.observe_property('sid', 'native', on_change)
mp.observe_property('track-list', 'native', on_change)
mp.observe_property('sub-visibility', 'native', on_change)

