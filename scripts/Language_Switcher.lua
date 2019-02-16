-- deus0ww - 2019-02-17

local mp      = require 'mp'
local msg     = require 'mp.msg'

-- Language Definitions: [language key] = descriptive search string. Must be lowercase; should have 'und' as the last entry.
local language_codes = {
	eng  = 'english',
	jpn  = 'japanese,jpn',
	tha  = 'thai',
	und  = 'unknown,undetermined',
}

-- Set this instead of MPV 'alang, slang'. Must use language keys; should have 'und' as the last entry.
local language_priorities = {
	video = {},
	audio = { 'jpn', 'tha', 'eng', 'und' },
	sub   = { 'tha', 'eng', 'und' },
}

-- Default (audio => subtitle,visibility) language pairings.  Must use language keys.
local language_pairs = {
	eng = {sub_language = 'tha', visibility = false },
	jpn = {sub_language = 'eng', visibility = true  },
	und = {sub_language = 'und', visibility = false },
}

local function process_track_list(track_list)
	if not track_list then return end
	local tracks = { video = {}, audio = {}, sub = {} }
	for _, current in ipairs(track_list) do
		table.insert(tracks[current.type], current)
	end
	return tracks
end

local function process_tracks(subtracks, lang_priority)
	if not (subtracks and lang_priority) then return end
	local processed_subtracks, language_first_index = { current_index = 1, track_count = #subtracks, active = true }, {}
	for _, current_lang in ipairs(lang_priority) do
		for _, subtrack in ipairs(subtracks) do
			if subtrack.lang and language_codes[current_lang]:find(subtrack.lang:lower()) ~= nil then
				processed_subtracks[#processed_subtracks + 1] = subtrack
				if not language_first_index[current_lang] then
					language_first_index[current_lang] = #processed_subtracks
				end
			end
		end
	end
	return processed_subtracks, language_first_index
end

local function add_undefined_tracks(subtracks, processed_subtracks, language_first_index)
	if not (subtracks and processed_subtracks and language_first_index) then return end
	for _, subtrack in ipairs(subtracks) do
		if ((subtrack.lang == nil) or (subtrack.lang == '')) then
			subtrack.lang = 'und'
			processed_subtracks[#processed_subtracks + 1] = subtrack
			if not language_first_index.und then
				language_first_index.und = #processed_subtracks
			end
		end
	end
	return processed_subtracks, language_first_index
end

local track_types = {
	video = { t = 'video', cmd = 'vid', label = 'Video Track' },
	audio = { t = 'audio', cmd = 'aid', label = 'Audio Track' },
	sub   = { t = 'sub',   cmd = 'sid', label = 'Subtitle Track' },
}

local saved
local function reset_saved(path) saved = { audio = {current_index = nil, active = false}, sub = {current_index = nil, active = false}, last_path = path } end
reset_saved('')

local function set_track(track_type, subtracks, no_osd)
	if not (track_type and subtracks and subtracks.current_index) then return end
	local subtrack = subtracks[subtracks.current_index]
	if not (subtrack and subtrack.lang and subtrack.id) then return end
	saved[track_type.t].current_index = subtracks.current_index
	mp.commandv('async', 'set', track_type.cmd, subtrack.id)
	if not no_osd then
		mp.osd_message(('☑ %s %.2d/%.2d:  %3s %s'):format(track_type.label, subtrack.id, subtracks.track_count, subtrack.lang:upper(), subtrack.title and subtrack.title or ''))
	end
end

local set_track_active = {
	video = function(active, no_osd) return end,
	audio = function(active, no_osd)
	            saved.audio.active = active
	            mp.commandv('async', 'set', 'mute',           active and 'no' or 'yes')
	            if not no_osd then mp.osd_message((active and '☑︎' or '☐') .. ' Audio') end
	        end,
	sub   = function(active, no_osd)
	            saved.sub.active = active
	            mp.commandv('async', 'set', 'sub-visibility', active and 'yes' or 'no')
	            if not no_osd then mp.osd_message((active and '☑︎' or '☐') .. ' Subtitle') end
	        end,
}

local function filter_track_lang(track_list)
	local processed_tracks = process_track_list(track_list)
	local tracks, language_first_index = {}, {}
	for track_type, subtracks in pairs(processed_tracks) do
		tracks[track_type], language_first_index[track_type] = process_tracks(subtracks, language_priorities[track_type])
		add_undefined_tracks(subtracks, tracks[track_type], language_first_index[track_type])
	end
	return tracks, language_first_index
end

local tracks, language_first_index = {}, {}

local function get_containing_path()
	local file_path, file_name = mp.get_property_native('path', ''), mp.get_property_native('filename', '')
	return file_path:sub(1, -(file_name:len() + 1))
end

local function set_default_tracks(tracks)
	local current_path = get_containing_path()
	local sub_vis = false
	if saved.last_path ~= current_path then
		msg.debug('Directory Changed: Reseting previous selections.')
		reset_saved(current_path)
		tracks.audio.current_index = tracks.audio.track_count > 0 and 1 or nil
		local audio_track = tracks.audio.current_index and tracks.audio[tracks.audio.current_index] or nil
		tracks.audio.active = true
		if audio_track and language_pairs[audio_track.lang] then
			msg.debug('Language Pair Found:', audio_track.lang, language_pairs[audio_track.lang].sub_language)
			tracks.sub.current_index = language_first_index.sub[language_pairs[audio_track.lang].sub_language]
			tracks.sub.active = language_pairs[audio_track.lang].visibility
		else
			msg.debug('Language Pair Not Found')
			tracks.sub.current_index = tracks.sub.track_count > 0 and 1 or nil
			tracks.sub.active = false
		end
	else
		msg.debug('Same Directory: Using previous selections.')
		tracks.audio.current_index = ( saved.audio.current_index and tracks.audio[saved.audio.current_index] ~= nil ) and saved.audio.current_index or (tracks.audio.track_count > 0 and 1 or nil)
		tracks.sub.current_index   = ( saved.sub.current_index   and tracks.sub[saved.sub.current_index]     ~= nil ) and saved.sub.current_index   or (tracks.sub.track_count   > 0 and 1 or nil)
		tracks.audio.active = saved.audio.active ~= nil and saved.audio.active or false
		tracks.sub.active   = saved.sub.active   ~= nil and saved.sub.active   or false

	end
	set_track_active.audio(tracks.audio.active, true)
	set_track_active.sub(tracks.sub.active,     true)
	set_track(track_types.audio, tracks.audio, true)
	set_track(track_types.sub,   tracks.sub,   true)
end

mp.register_event('file-loaded', function()
	msg.debug('Setting Languages...')
	local track_list = mp.get_property_native('track-list')
	if not track_list then return end
	tracks, language_first_index = filter_track_lang(track_list)
	set_default_tracks(tracks)
end)

for track_type, _ in pairs(track_types) do
	mp.register_script_message(track_type .. '-track+', function()
		msg.debug('Track Up:', track_type)
		if not tracks[track_type].current_index then return end
		tracks[track_type].current_index = (tracks[track_type].current_index % #tracks[track_type]) + 1
		set_track(track_types[track_type], tracks[track_type])
		tracks[track_type].active = true
		set_track_active[track_type](tracks[track_type].active, true)
	end)
	mp.register_script_message(track_type .. '-track-', function()
		msg.debug('Track Down:', track_type)
		if not tracks[track_type].current_index then return end
		tracks[track_type].current_index = ((tracks[track_type].current_index - 2) % #tracks[track_type]) + 1
		set_track(track_types[track_type], tracks[track_type])
		tracks[track_type].active = true
		set_track_active[track_type](tracks[track_type].active, true)
	end)
	mp.register_script_message(track_type .. '-toggle', function()
		tracks[track_type].active = not tracks[track_type].active
		set_track_active[track_type](tracks[track_type].active)
	end)
end
