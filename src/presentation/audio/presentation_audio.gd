## Story008 Presentation-only audio event router.
##
## This component mirrors already accepted Presentation/owner facts. It never
## owns routes, saves, load results, runs, focus, or any gameplay timing.
class_name PresentationAudio
extends Node


signal event_routed(event_id: StringName)


const UI_PRESS_EVENT: StringName = &"presentation_audio.ui_press"
const PAUSE_OPEN_EVENT: StringName = &"presentation_audio.pause_open"
const PAUSE_RESUME_EVENT: StringName = &"presentation_audio.pause_resume"
const SAVE_SUCCESS_EVENT: StringName = &"presentation_audio.save_success"
const SAVE_FAILURE_EVENT: StringName = &"presentation_audio.save_failure"
const LOAD_SUCCESS_EVENT: StringName = &"presentation_audio.load_success"
const LOAD_FAILURE_EVENT: StringName = &"presentation_audio.load_failure"
const DAY_COMPLETE_EVENT: StringName = &"presentation_audio.day_complete"
const FINAL_OUTCOME_EVENT: StringName = &"presentation_audio.final_outcome"
const RELIABLE_ENGINEER_OUTCOME_ID: StringName = &"career.outcome.reliable_engineer"
const FIREFIGHTER_OUTCOME_ID: StringName = &"career.outcome.firefighter"
const NEEDS_GUIDANCE_OUTCOME_ID: StringName = &"career.outcome.needs_guidance"

const PAUSE_DUCK_DB: float = -9.0
const UI_PRESS_COOLDOWN_MSEC: int = 35
const MAX_SIMULTANEOUS_UI_PRESSES: int = 3
const SEMANTIC_EVENT_COOLDOWN_MSEC: int = 80

const EVENT_PLAYER_NAMES: Dictionary = {
	&"presentation_audio.ui_press": ["UiPress01", "UiPress02", "UiPress03", "UiPress04"],
	&"presentation_audio.pause_open": ["PauseOpen"],
	&"presentation_audio.pause_resume": ["PauseResume"],
	&"presentation_audio.save_success": ["SaveSuccess"],
	&"presentation_audio.save_failure": ["SaveFailure"],
	&"presentation_audio.load_success": ["LoadSuccess"],
	&"presentation_audio.load_failure": ["LoadFailure"],
	&"presentation_audio.day_complete": ["DayComplete"],
	&"presentation_audio.final_outcome": [
		"FinalOutcomeReliable", "FinalOutcomeFirefighter", "FinalOutcomeGuidance"
	],
}

const FINAL_OUTCOME_PLAYER_NAMES: Dictionary = {
	&"career.outcome.reliable_engineer": "FinalOutcomeReliable",
	&"career.outcome.firefighter": "FinalOutcomeFirefighter",
	&"career.outcome.needs_guidance": "FinalOutcomeGuidance",
}

var _music_player: AudioStreamPlayer
var _ui_press_players: Array[AudioStreamPlayer] = []
var _semantic_players: Dictionary = {}
var _final_outcome_players: Dictionary = {}
var _next_ui_press_index: int = 0
var _last_ui_press_msec: int = -UI_PRESS_COOLDOWN_MSEC
var _last_semantic_event_msec: Dictionary = {}
var _music_normal_volume_db: float = 0.0
var _is_cached: bool = false


func _ready() -> void:
	_cache_players()
	_configure_music_loop()
	if is_instance_valid(_music_player) and not _music_player.playing:
		_music_player.play()


func _configure_music_loop() -> void:
	if not is_instance_valid(_music_player) or not _music_player.stream is AudioStreamWAV:
		return
	var authored_stream := _music_player.stream as AudioStreamWAV
	var looping_stream := authored_stream.duplicate(true) as AudioStreamWAV
	looping_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looping_stream.loop_begin = 0
	looping_stream.loop_end = int(round(looping_stream.get_length() * float(looping_stream.mix_rate)))
	_music_player.stream = looping_stream


## Routes a closed Presentation event. Unknown, unavailable, and cooldown-held
## events are ignored without mutating any route or domain owner state.
func route_event(event_id: StringName, outcome_id: StringName = &"") -> void:
	_cache_players()
	if not is_supported_event(event_id):
		return
	if event_id == UI_PRESS_EVENT:
		_route_ui_press()
		return
	if event_id == FINAL_OUTCOME_EVENT:
		_route_final_outcome(outcome_id)
		return
	_route_semantic_event(event_id)


## Applies the Story008 mix change without stopping, seeking, or restarting
## music transport. Restoring returns to the scene-authored normal level.
func set_pause_ducked(is_ducked: bool) -> void:
	_cache_players()
	if not is_instance_valid(_music_player):
		return
	_music_player.volume_db = _music_normal_volume_db + (PAUSE_DUCK_DB if is_ducked else 0.0)


func is_supported_event(event_id: StringName) -> bool:
	return EVENT_PLAYER_NAMES.has(event_id)


func get_event_player_names() -> Dictionary:
	return EVENT_PLAYER_NAMES.duplicate(true)


func get_pause_duck_db() -> float:
	return PAUSE_DUCK_DB


func get_next_ui_press_index() -> int:
	return _next_ui_press_index


func _cache_players() -> void:
	if _is_cached:
		return
	_music_player = get_node_or_null(^"MusicPlayer") as AudioStreamPlayer
	if is_instance_valid(_music_player):
		_music_normal_volume_db = _music_player.volume_db
	for player_name: String in EVENT_PLAYER_NAMES[UI_PRESS_EVENT]:
		var player: AudioStreamPlayer = get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
		if is_instance_valid(player):
			_ui_press_players.append(player)
	for event_id: StringName in EVENT_PLAYER_NAMES:
		if event_id == UI_PRESS_EVENT or event_id == FINAL_OUTCOME_EVENT:
			continue
		var semantic_name: String = str(EVENT_PLAYER_NAMES[event_id][0])
		var semantic_player: AudioStreamPlayer = get_node_or_null(NodePath(semantic_name)) as AudioStreamPlayer
		if is_instance_valid(semantic_player):
			_semantic_players[event_id] = semantic_player
	for outcome_id: StringName in FINAL_OUTCOME_PLAYER_NAMES:
		var outcome_name: String = str(FINAL_OUTCOME_PLAYER_NAMES[outcome_id])
		var outcome_player: AudioStreamPlayer = get_node_or_null(NodePath(outcome_name)) as AudioStreamPlayer
		if is_instance_valid(outcome_player):
			_final_outcome_players[outcome_id] = outcome_player
	_is_cached = true


func _route_ui_press() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_ui_press_msec < UI_PRESS_COOLDOWN_MSEC:
		return
	if _ui_press_players.is_empty() or _count_playing(_ui_press_players) >= MAX_SIMULTANEOUS_UI_PRESSES:
		return
	for index_offset: int in range(_ui_press_players.size()):
		var index: int = (_next_ui_press_index + index_offset) % _ui_press_players.size()
		var player: AudioStreamPlayer = _ui_press_players[index]
		if not player.playing:
			_next_ui_press_index = (index + 1) % _ui_press_players.size()
			_last_ui_press_msec = now_msec
			player.play()
			event_routed.emit(UI_PRESS_EVENT)
			return


func _route_semantic_event(event_id: StringName) -> void:
	var player: AudioStreamPlayer = _semantic_players.get(event_id) as AudioStreamPlayer
	if not is_instance_valid(player):
		return
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_semantic_event_msec.get(event_id, -SEMANTIC_EVENT_COOLDOWN_MSEC))
	if now_msec - last_msec < SEMANTIC_EVENT_COOLDOWN_MSEC:
		return
	_last_semantic_event_msec[event_id] = now_msec
	player.play()
	event_routed.emit(event_id)


func _route_final_outcome(outcome_id: StringName) -> void:
	var player: AudioStreamPlayer = _final_outcome_players.get(outcome_id) as AudioStreamPlayer
	if not is_instance_valid(player):
		return
	player.play()
	event_routed.emit(FINAL_OUTCOME_EVENT)


func _count_playing(players: Array[AudioStreamPlayer]) -> int:
	var playing_count: int = 0
	for player: AudioStreamPlayer in players:
		if player.playing:
			playing_count += 1
	return playing_count
