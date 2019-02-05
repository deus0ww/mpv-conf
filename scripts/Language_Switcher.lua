-- deus0ww - 2019-02-06

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
	jpn = {sub_language = 'eng', visibility = true },
	und = {sub_language = 'eng', visibility = false },
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
	local processed_subtracks, language_first_index = { current_index = 1, track_count = #subtracks }, {}
	local lang_index
	for _, current_lang in ipairs(lang_priority) do
		lang_index = 0
		for _, subtrack in ipairs(subtracks) do
			if subtrack.lang and language_codes[current_lang]:find(subtrack.lang:lower()) ~= nil then
				subtrack.lang_index = lang_index
				lang_index = lang_index + 1
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

local saved = { audio = {lang_index = 0}, sub = {lang_index = 0}, last_path = '' }

local function set_track(track_type, subtracks, no_osd)
	if not (track_type and subtracks) then return end
	local subtrack = subtracks[subtracks.current_index]
	if not (subtrack and subtrack.lang and subtrack.id) then return end
	saved[track_type.t].lang_index = subtracks[subtracks.current_index].lang_index
	mp.commandv('async', 'set', track_type.cmd, subtrack.id)
	if not no_osd then
		mp.osd_message(('%s %.2d/%.2d: %3s %s'):format(track_type.label, subtrack.id, subtracks.track_count, subtrack.lang:upper(), subtrack.title and subtrack.title or ''))
	end
end

local function set_subtitle_visibility(visibility)
	mp.commandv('async', 'set', 'sub-visibility', visibility and 'yes' or 'no')
end

local function filter_track_lang(track_list)
	local tracks = process_track_list(track_list)
	local processed_tracks, language_first_index = {}, {}
	for track_type, subtracks in pairs(tracks) do
		processed_tracks[track_type], language_first_index[track_type] = process_tracks(subtracks, language_priorities[track_type])
		add_undefined_tracks(subtracks, processed_tracks[track_type], language_first_index[track_type])
	end
	return processed_tracks, language_first_index
end

local processed_tracks, language_first_index = {}, {}

local function get_containg_path()
	local file_path, file_name = mp.get_property_native('path', ''), mp.get_property_native('filename', '')
	return file_path:sub(1, -(file_name:len() + 1))
end

local function set_default_tracks(processed_tracks)
	local current_path = get_containg_path()
	if saved.last_path ~= current_path then
		msg.info('Directory Changed: Reseting previous selections.')
		saved.last_path = current_path
		saved.audio.lang_index = 0
		saved.sub.lang_index   = 0
	else
		msg.info('Same Directory: Using previous selections.')
	end
	processed_tracks.sub.current_index = processed_tracks.audio.current_index + saved.audio.lang_index
	local audio_track = processed_tracks.audio[processed_tracks.audio.current_index]
	if audio_track and language_pairs[audio_track.lang] then
		processed_tracks.sub.current_index = language_first_index.sub[language_pairs[audio_track.lang].sub_language] + saved.sub.lang_index
		set_subtitle_visibility(language_pairs[audio_track.lang].visibility)
	else
		set_subtitle_visibility(false)
	end
	set_track(track_types.audio, processed_tracks.audio, true)
	set_track(track_types.sub,   processed_tracks.sub,   true)
end

mp.register_event('file-loaded', function()
	local track_list = mp.get_property_native('track-list')
	if not track_list then return end
	msg.info('Setting Languages...')
	processed_tracks, language_first_index = filter_track_lang(track_list)
	set_default_tracks(processed_tracks)
end)

for track_type, _ in pairs(track_types) do
	mp.register_script_message(track_type .. '-track+', function()
		processed_tracks[track_type].current_index = (processed_tracks[track_type].current_index % #processed_tracks[track_type]) + 1
		set_track(track_types[track_type], processed_tracks[track_type])
		set_subtitle_visibility(true)
	end)
	mp.register_script_message(track_type .. '-track-', function()
		processed_tracks[track_type].current_index = ((processed_tracks[track_type].current_index - 2) % #processed_tracks[track_type]) + 1
		set_track(track_types[track_type], processed_tracks[track_type])
		set_subtitle_visibility(true)
	end)
end
