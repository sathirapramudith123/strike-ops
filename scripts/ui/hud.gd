class_name Hud
extends CanvasLayer
## In-game HUD: crosshair, hit markers, health, ammo, reload bar,
## damage flash, kill feed, scoreboard (Tab) and the F3 performance overlay.

const KILL_FEED_TIME := 5.0
const KILL_FEED_MAX := 5

@onready var _crosshair: Crosshair = %Crosshair
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reserve_label: Label = %ReserveLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _perf_label: Label = %PerfLabel
@onready var _dead_label: Label = %DeadLabel
@onready var _kill_feed: VBoxContainer = %KillFeed
@onready var _scoreboard: Control = %Scoreboard
@onready var _score_grid: GridContainer = %ScoreGrid
@onready var _server_label: Label = %ServerLabel
@onready var _mic_indicator: Label = %MicIndicator
@onready var _speakers: VBoxContainer = %Speakers

var _player: PlayerController
var _weapon: Weapon


func bind_player(player: PlayerController) -> void:
	_player = player
	player.health.health_changed.connect(_on_health_changed)
	player.health.damaged.connect(func(_a: float, _s: Node, _h: bool) -> void: _damage_flash.color.a = 0.35)
	_on_health_changed(player.health.current, player.health.max_health)
	_bind_weapon(player.current_weapon)


func _ready() -> void:
	_perf_label.visible = SettingsManager.show_perf_overlay
	_reload_bar.visible = false
	_dead_label.visible = false
	_damage_flash.color.a = 0.0
	_scoreboard.visible = false
	NetworkManager.kill_feed.connect(_on_kill_feed)
	NetworkManager.roster_changed.connect(_refresh_scoreboard)
	_mic_indicator.visible = false
	VoiceChat.transmitting_changed.connect(_on_transmitting_changed)
	VoiceChat.speaking_changed.connect(_on_speaking_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_perf_overlay"):
		SettingsManager.show_perf_overlay = not SettingsManager.show_perf_overlay
		SettingsManager.save()
		_perf_label.visible = SettingsManager.show_perf_overlay


func _process(delta: float) -> void:
	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta * 0.8)
	var show_scores := Input.is_action_pressed(&"scoreboard")
	if show_scores and not _scoreboard.visible:
		_refresh_scoreboard()
	_scoreboard.visible = show_scores
	if _player:
		_dead_label.visible = _player.health.is_dead
		if _player.current_weapon != _weapon:
			_bind_weapon(_player.current_weapon)
	if _weapon:
		_update_crosshair()
		_reload_bar.visible = _weapon.is_reloading
		_reload_bar.value = _weapon.get_reload_progress()
	if _perf_label.visible:
		_update_perf()


func _bind_weapon(weapon: Weapon) -> void:
	_weapon = weapon
	if weapon == null:
		return
	_weapon_label.text = weapon.data.display_name
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.hit_confirmed.connect(func(kill: bool, _head: bool) -> void: _crosshair.show_hit(kill))
	_on_ammo_changed(weapon.ammo_in_magazine, weapon.ammo_reserve)


func _update_crosshair() -> void:
	# Convert the spread angle into screen pixels so the crosshair is honest.
	var cam := _player.camera
	var half_h := get_viewport().get_visible_rect().size.y * 0.5
	var px := tan(deg_to_rad(_weapon.current_spread)) / tan(deg_to_rad(cam.fov * 0.5)) * half_h
	_crosshair.gap = maxf(px, 3.0)
	_crosshair.ads = _weapon.ads_blend


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = str(ceili(current))


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	_ammo_label.text = str(in_magazine)
	_reserve_label.text = "/ %d" % reserve
	var low := _weapon and in_magazine <= _weapon.data.magazine_size / 4
	_ammo_label.modulate = Color(1, 0.35, 0.3) if low else Color.WHITE


func _update_perf() -> void:
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	_perf_label.text = "FPS %d  (%.1f ms)\nDraw calls %d  |  Tris %dk\nVRAM %.0f MB\nPreset %s  |  %s" % [
		fps, frame_ms, draw_calls, prims / 1000, vram,
		SettingsManager.graphics.display_name, RenderingServer.get_current_rendering_method()]
	if NetworkManager.mode == NetworkManager.Mode.CLIENT:
		_perf_label.text += "\nPing %d ms" % NetworkManager.ping_ms


func _on_transmitting_changed(transmitting: bool, channel: int) -> void:
	_mic_indicator.visible = transmitting
	_mic_indicator.text = "● MIC — %s" % ["TEAM", "PROXIMITY", "ALL"][channel]


## Left-side "who is talking" list; also tints the speaker's name tag.
func _on_speaking_changed(peer_id: int, speaking: bool) -> void:
	var node_name := "Speaker_%d" % peer_id
	var existing := _speakers.get_node_or_null(node_name)
	if speaking and existing == null:
		var l := Label.new()
		l.name = node_name
		l.text = "» %s" % NetworkManager.get_player_name(peer_id)
		l.add_theme_color_override(&"font_color", Color(0.4, 1, 0.5))
		l.add_theme_color_override(&"font_outline_color", Color.BLACK)
		l.add_theme_constant_override(&"outline_size", 4)
		_speakers.add_child(l)
	elif not speaking and existing:
		existing.queue_free()
	var level := get_parent() as Level
	var speaker := level.get_player(peer_id) if level else null
	if speaker:
		speaker.set_speaking(speaking)


func _on_kill_feed(killer: String, victim: String, weapon_name: String, headshot: bool) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_constant_override(&"outline_size", 4)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	var how := weapon_name + (" (headshot)" if headshot else "")
	label.text = "%s  [%s]  %s" % [killer, how, victim] if killer != "World" else "%s fell" % victim
	var local_name := player_name_or_empty()
	if local_name != "" and (killer == local_name or victim == local_name):
		label.add_theme_color_override(&"font_color", Color(1, 0.85, 0.3))
	_kill_feed.add_child(label)
	while _kill_feed.get_child_count() > KILL_FEED_MAX:
		_kill_feed.get_child(0).queue_free()
	get_tree().create_timer(KILL_FEED_TIME).timeout.connect(label.queue_free)


func player_name_or_empty() -> String:
	return _player.player_name if _player else ""


func _refresh_scoreboard() -> void:
	for child in _score_grid.get_children():
		child.queue_free()
	for header: String in ["Player", "Kills", "Deaths", "Ping"]:
		_add_score_cell(header, Color(1, 1, 1, 0.6))
	var ids := NetworkManager.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return NetworkManager.roster[a].kills > NetworkManager.roster[b].kills)
	for id: int in ids:
		var e: Dictionary = NetworkManager.roster[id]
		var col := Color(1, 0.85, 0.3) if id == multiplayer.get_unique_id() else Color.WHITE
		_add_score_cell(("» " if VoiceChat.is_speaking(id) else "") + e.name, col)
		_add_score_cell(str(e.kills), col)
		_add_score_cell(str(e.deaths), col)
		_add_score_cell("host" if id == 1 else str(e.ping), col)
	match NetworkManager.mode:
		NetworkManager.Mode.OFFLINE: _server_label.text = "Offline"
		NetworkManager.Mode.HOST: _server_label.text = "Hosting — %d player(s)" % ids.size()
		_: _server_label.text = "Online — %d player(s)" % ids.size()


func _add_score_cell(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_grid.add_child(l)
