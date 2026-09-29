extends Node
## Autoload "Audio": every game sound goes through here.
##
##   play_3d()      positional sound (gunfire, footsteps, impacts, bomb) from a
##                  pool of AudioStreamPlayer3D voices. A wall between the
##                  listener and the sound muffles it (occlusion → the
##                  "SFXOccluded" bus with a low-pass), and Area3D reverb zones
##                  in the maps (physics layer 7) add echo indoors.
##   play_local()   non-positional sound for the local player (own steps, hurt).
##   play_ui()      interface sounds: clicks, hit markers, round/match stings.
##   play_music()   menu / match music with cross-fades.
##
## Voices are limited by the audio quality setting (Low: 16, no reverb;
## High: 40, reverb + continuous occlusion); when all are busy the oldest one
## is reused. Placeholder sounds are generated (SfxLibrary, MusicSynth) on a
## worker thread at startup; files in assets/audio/ replace them.
## Nothing plays on a dedicated server.

## Physics layer 1 ("world") blocks sound.
const OCCLUSION_MASK := 1
## Physics layer 7 ("audio_zone"): reverb Area3Ds.
const AUDIO_ZONE_MASK := 1 << 6
const VOICES_BY_QUALITY: Array[int] = [16, 40]
const LOCAL_VOICES := 8
const UI_VOICES := 6
## How often long sounds re-check occlusion (High quality).
const OCCLUSION_UPDATE := 0.12
const OCCLUDED_EXTRA_DB := -3.0
const MUSIC_FADE := 1.5
## The match track plays quietly under the game.
const MATCH_MUSIC_DB := -10.0
const REVERB_BUSES: Array[StringName] = [&"ReverbRoom", &"ReverbHall"]

## Times each sound was played: "name", "3d:name", "local:name", "ui:name".
var stats: Dictionary = {}
var current_music: StringName = &""
var max_voices: int = 40
## True once the placeholder library and music are generated.
var generated: bool = false

var _voices: Array[AudioStreamPlayer3D] = []
var _local: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _music_streams: Dictionary = {}
var _music_tween: Tween
var _occlusion_timer: float = 0.0
var _last_hover_ms: int = 0
var _task_id: int = -1
var _server_only: bool = false
## Filled by the worker thread, read after it finished.
var _generated_streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # UI sounds + music keep going while paused
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_server_only = OS.has_feature("dedicated_server") or "--server" in args
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		add_child(m)
		_music.append(m)
	for i in LOCAL_VOICES:
		_local.append(_new_2d(&"SFX"))
	for i in UI_VOICES:
		_ui.append(_new_2d(&"UI"))
	SettingsManager.audio_changed.connect(_apply_settings)
	_apply_settings()
	get_tree().node_added.connect(_on_node_added)
	Match.match_ended.connect(_on_match_ended)
	Match.bomb.round_started.connect(func(_n: int) -> void: play_ui(&"round_start", -3.0))
	Match.bomb.round_ended.connect(_on_round_ended)
	Match.bomb.bomb_planted.connect(func(_site: String) -> void: play_ui(&"bomb_planted", -2.0))
	Match.bomb.bomb_defused.connect(func() -> void: play_ui(&"bomb_defused", -2.0))
	if not _server_only:
		_task_id = WorkerThreadPool.add_task(_generate_all, false, "Generate placeholder audio")


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _process(delta: float) -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_on_generated()
	if SettingsManager.audio_quality == 0:
		return
	_occlusion_timer -= delta
	if _occlusion_timer > 0.0:
		return
	_occlusion_timer = OCCLUSION_UPDATE
	# Long sounds (explosions, sniper tails) follow walls moving in between.
	var listener := listener_position()
	for v in _voices:
		if v.playing and v.stream and v.stream.get_length() > 0.4:
			_set_occluded(v, _is_occluded(listener, v.global_position))


## False on a dedicated server (nobody to hear anything).
func is_active() -> bool:
	return not _server_only and not NetworkManager.is_dedicated()


# -----------------------------------------------------------------------------
# Sound effects
# -----------------------------------------------------------------------------

## Positional sound at `pos`. `sound` is a SfxLibrary name or an AudioStream.
## Sounds further than `max_distance` from the listener are skipped.
func play_3d(sound: Variant, pos: Vector3, volume_db: float = 0.0, max_distance: float = 50.0,
		pitch: float = 1.0, unit_size: float = 8.0) -> AudioStreamPlayer3D:
	if not is_active():
		return null
	var listener := listener_position()
	var distance := listener.distance_to(pos)
	if distance > max_distance:
		return null
	var v := _free_voice()
	v.stream = _stream(sound)
	v.global_position = pos
	v.max_distance = max_distance
	v.unit_size = unit_size
	v.pitch_scale = pitch
	v.set_meta(&"base_db", volume_db)
	v.set_meta(&"started", Time.get_ticks_msec())
	_set_occluded(v, distance > 1.5 and _is_occluded(listener, pos))
	v.play()
	_count(sound, "3d")
	return v


## Non-positional sound for the local player (own footsteps, hurt, …).
func play_local(sound: Variant, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if is_active():
		_play_2d(_local, sound, volume_db, pitch)
		_count(sound, "local")


## Interface sound on the UI bus (clicks, hit markers, stings).
func play_ui(sound: Variant, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if is_active():
		_play_2d(_ui, sound, volume_db, pitch)
		_count(sound, "ui")


## A bullet flew from `from` to `to`: a "whiz" if it passed close to the listener.
func bullet_passed(from: Vector3, to: Vector3) -> void:
	if not is_active():
		return
	var listener := listener_position()
	var closest := Geometry3D.get_closest_point_to_segment(listener, from, to)
	var d := closest.distance_to(listener)
	if d > 0.2 and d < 3.0 and closest.distance_to(from) > 4.0:
		play_3d(&"whiz", closest, -2.0, 10.0, randf_range(0.9, 1.1), 2.0)


## True if world geometry blocks the straight line between two points.
func is_occluded(from: Vector3, to: Vector3) -> bool:
	return _is_occluded(from, to)


## Where the sounds are heard from (the active camera).
func listener_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


## Voices currently playing in the 3D pool.
func active_voices() -> int:
	return _voices.filter(func(v: AudioStreamPlayer3D) -> bool: return v.playing).size()


func voice_count() -> int:
	return _voices.size()


# -----------------------------------------------------------------------------
# Music
# -----------------------------------------------------------------------------

## Cross-fades to `track` (MusicSynth.TRACKS). Starts as soon as the track is
## generated if it isn't yet.
func play_music(track: StringName) -> void:
	if not is_active() or track == current_music:
		return
	current_music = track
	var stream: AudioStream = _music_streams.get(track)
	if stream:
		_crossfade(stream, _music_volume(track))


func stop_music(fade: float = MUSIC_FADE) -> void:
	current_music = &""
	_crossfade(null, -80.0, fade)


func music_stream(track: StringName) -> AudioStream:
	return _music_streams.get(track)


func is_music_playing() -> bool:
	return _music[_music_index].playing and _music[_music_index].stream != null


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _generate_all() -> void:
	SfxLibrary.prewarm()
	var streams := {}
	for track in MusicSynth.TRACKS:
		streams[track] = MusicSynth.get_track(track)
	_generated_streams = streams



func _on_generated() -> void:
	_music_streams = _generated_streams
	generated = true
	if current_music != &"" and _music_streams.has(current_music):
		_crossfade(_music_streams[current_music], _music_volume(current_music))


func _music_volume(track: StringName) -> float:
	if track == &"match":
		return MATCH_MUSIC_DB if SettingsManager.match_music else -80.0
	return 0.0


func _crossfade(stream: AudioStream, volume_db: float, fade: float = MUSIC_FADE) -> void:
	if _music_tween:
		_music_tween.kill()
	var old := _music[_music_index]
	var fade_in := stream != null and volume_db > -60.0
	if not fade_in and not old.playing:
		return
	_music_tween = create_tween().set_parallel(true)
	if fade_in:
		_music_index = 1 - _music_index
		var new := _music[_music_index]
		new.stream = stream
		new.volume_db = -40.0
		new.play()
		_music_tween.tween_property(new, ^"volume_db", volume_db, fade)
	if old.playing:
		_music_tween.tween_property(old, ^"volume_db", -60.0, fade)
		_music_tween.chain().tween_callback(old.stop)


func _free_voice() -> AudioStreamPlayer3D:
	for v in _voices:
		if not v.playing:
			return v
	if _voices.size() < max_voices:
		var v := AudioStreamPlayer3D.new()
		v.bus = &"SFX"
		v.area_mask = AUDIO_ZONE_MASK if SettingsManager.audio_quality > 0 else 0
		v.attenuation_filter_cutoff_hz = 9000.0 # distant sounds lose their highs
		v.attenuation_filter_db = -18.0
		v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(v)
		_voices.append(v)
		return v
	# All busy: reuse the one that started first.
	var oldest := _voices[0]
	for v in _voices:
		if int(v.get_meta(&"started", 0)) < int(oldest.get_meta(&"started", 0)):
			oldest = v
	oldest.stop()
	return oldest


func _set_occluded(v: AudioStreamPlayer3D, occluded: bool) -> void:
	v.bus = &"SFXOccluded" if occluded else &"SFX"
	v.volume_db = float(v.get_meta(&"base_db", 0.0)) + (OCCLUDED_EXTRA_DB if occluded else 0.0)


func _is_occluded(from: Vector3, to: Vector3) -> bool:
	var world := get_viewport().find_world_3d()
	if world == null or from.is_equal_approx(to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, OCCLUSION_MASK)
	var hit := world.direct_space_state.intersect_ray(query)
	# A hit right at the source is the surface it sits on (impacts, feet).
	return not hit.is_empty() and (hit.position as Vector3).distance_to(to) > 0.4


func _new_2d(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _play_2d(pool: Array[AudioStreamPlayer], sound: Variant, volume_db: float, pitch: float) -> void:
	var player := pool[0]
	for p in pool:
		if not p.playing:
			player = p
			break
		if int(p.get_meta(&"started", 0)) < int(player.get_meta(&"started", 0)):
			player = p
	player.stream = _stream(sound)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.set_meta(&"started", Time.get_ticks_msec())
	player.play()


func _stream(sound: Variant) -> AudioStream:
	return sound if sound is AudioStream else SfxLibrary.get_sound(sound)


func _count(sound: Variant, kind: String) -> void:
	var key := String(sound) if not sound is AudioStream else "custom"
	stats[key] = int(stats.get(key, 0)) + 1
	stats["%s:%s" % [kind, key]] = int(stats.get("%s:%s" % [kind, key], 0)) + 1


func _apply_settings() -> void:
	var high := SettingsManager.audio_quality > 0
	max_voices = VOICES_BY_QUALITY[clampi(SettingsManager.audio_quality, 0, 1)]
	for bus in REVERB_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_effect_enabled(idx, 0, high)
			AudioServer.set_bus_mute(idx, not high)
	while _voices.size() > max_voices:
		_voices.pop_back().queue_free()
	for v in _voices:
		v.area_mask = AUDIO_ZONE_MASK if high else 0
	if current_music == &"match" and _music_streams.has(&"match"):
		var target := _music_volume(&"match")
		var active := _music[_music_index]
		if target <= -60.0:
			active.stop()
		elif not active.playing or active.stream != _music_streams[&"match"]:
			_crossfade(_music_streams[&"match"], target)
		else:
			active.volume_db = target


## Every button in the game clicks (and ticks on hover).
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.has_meta(&"silent"):
		return
	button.pressed.connect(func() -> void: play_ui(&"ui_click", -6.0))
	button.mouse_entered.connect(func() -> void:
		var now := Time.get_ticks_msec()
		if not button.disabled and now - _last_hover_ms > 40:
			_last_hover_ms = now
			play_ui(&"ui_hover", -16.0))


func _on_round_ended(winner_team: int, _reason: String) -> void:
	_round_sting.call_deferred(winner_team)


func _round_sting(winner_team: int) -> void:
	if Match.is_ended():
		return # the last round: the match sting plays instead
	var mine := Match.get_team(multiplayer.get_unique_id())
	play_ui(&"round_win" if mine == winner_team else &"round_lose", -3.0)


func _on_match_ended(text: String) -> void:
	if not is_active():
		return
	stop_music(1.0)
	match match_result(text):
		"win": play_ui(&"match_win", -1.0)
		"draw": play_ui(&"match_draw", -2.0)
		_: play_ui(&"match_lose", -1.0)


## "win", "lose" or "draw" for the local player, from the match-end text
## ("Blue team wins!", "Time's up — Nuwan wins!", "Draw!").
func match_result(text: String) -> String:
	var t := text.trim_prefix("Time's up — ")
	if t.begins_with("Draw"):
		return "draw"
	return "win" if _local_won(t) else "lose"


func _local_won(text: String) -> bool:
	var me := multiplayer.get_unique_id()
	if Match.is_team_mode():
		var team := Match.get_team(me)
		return team >= 0 and team < GameConfig.TEAM_NAMES.size() and text.begins_with(GameConfig.TEAM_NAMES[team])
	return text == "%s wins!" % NetworkManager.get_player_name(me)
