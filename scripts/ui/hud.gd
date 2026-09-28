class_name Hud
extends CanvasLayer
## In-game HUD: crosshair, scope, hit markers, health, ammo, weapon slots,
## reload bar, damage flash, radar + location name, top bar (clock, scores,
## player cards), kill feed, scoreboard (Tab), end-of-match results and the
## F3 performance overlay.

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
@onready var _scope: ScopeOverlay = %ScopeOverlay
@onready var _match_bar: Label = %MatchBar
@onready var _weapon_slots: VBoxContainer = %WeaponSlots
@onready var _minimap: Minimap = %Minimap
@onready var _location_label: Label = %LocationLabel
@onready var _top_bar: TopBar = %TopBar
@onready var _health_icon: Control = %HealthIcon
@onready var _armor_group: Control = %ArmorGroup
@onready var _armor_icon: Control = %ArmorIcon
@onready var _armor_label: Label = %ArmorLabel
@onready var _armor_bar: ProgressBar = %ArmorBar
@onready var _ammo_icons: Control = %AmmoIcons
@onready var _end_screen: Control = %EndScreen
@onready var _winner_label: Label = %WinnerLabel
@onready var _next_map_label: Label = %NextMapLabel
@onready var _end_grid: GridContainer = %EndGrid
@onready var _center_message: Label = %CenterMessage
@onready var _action_box: Control = %ActionBox
@onready var _action_label: Label = %ActionLabel
@onready var _action_bar: ProgressBar = %ActionBar
@onready var _bomb_hint: Label = %BombHint

var _player: PlayerController
var _weapon: Weapon
var _location_timer := 0.0
var _banner: VBoxContainer
var _banner_time := 0.0
var _banner_round := -1
const BANNER_TIME := 6.0
var _feed_style: StyleBoxFlat
var _feed_style_mine: StyleBoxFlat


## Performance advisor: shown when dynamic resolution can't keep up.
func show_performance_hint() -> void:
	if SettingsManager.graphics.quality == GraphicsPreset.Quality.LOW:
		_show_toast("Low FPS: try lowering Render scale or the Target FPS in Settings → Graphics")
	else:
		_show_toast("Low FPS: a lower graphics preset is recommended (Settings → Graphics)")


func _show_toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", Color(1, 0.8, 0.4))
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 6)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-l.get_minimum_size().x * 0.5, 120)
	add_child(l)
	get_tree().create_timer(8.0).timeout.connect(l.queue_free)


func bind_player(player: PlayerController) -> void:
	_player = player
	player.health.health_changed.connect(_on_health_changed)
	player.health.armor_changed.connect(_on_armor_changed)
	_on_armor_changed(player.health.armor)
	player.health.damaged.connect(func(_a: float, _s: Node, _h: bool) -> void:
		_damage_flash.color.a = 0.35
		GamepadInput.rumble(0.6, 0.4, 0.2)
		Audio.play_local(&"hurt", -4.0, randf_range(0.9, 1.1)))
	_on_health_changed(player.health.current, player.health.max_health)
	if player.throwables:
		player.throwables.changed.connect(_update_weapon_slots)
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
	Match.state_changed.connect(_on_match_state_changed)
	_on_match_state_changed()
	_health_icon.draw.connect(func() -> void:
		var c := _health_icon.size * 0.5
		var col := _health_label.modulate
		_health_icon.draw_rect(Rect2(c - Vector2(3.5, 10), Vector2(7, 20)), col)
		_health_icon.draw_rect(Rect2(c - Vector2(10, 3.5), Vector2(20, 7)), col))
	# Shield outline for armour.
	_armor_icon.draw.connect(func() -> void:
		var c := _armor_icon.size * 0.5
		var shield := PackedVector2Array([c + Vector2(-9, -10), c + Vector2(9, -10), c + Vector2(9, 0),
			c + Vector2(0, 11), c + Vector2(-9, 0)])
		_armor_icon.draw_colored_polygon(shield, Color(1, 1, 1, 0.25))
		_armor_icon.draw_polyline(shield + PackedVector2Array([shield[0]]), Color.WHITE, 2.5))
	_armor_group.visible = false
	# Magazine as bullet marks: bright = rounds left (CS style).
	_ammo_icons.draw.connect(func() -> void:
		if _weapon == null:
			return
		var marks := 5
		var lit := ceili(float(_weapon.ammo_in_magazine) / maxf(_weapon.data.magazine_size, 1) * marks)
		for i in marks:
			var x := 4.0 + i * 9.0
			var col := Color(1, 0.92, 0.7) if i < lit else Color(1, 1, 1, 0.2)
			_ammo_icons.draw_line(Vector2(x, 18), Vector2(x + 6, 4), col, 3.0))
	_feed_style = StyleBoxFlat.new()
	_feed_style.bg_color = Color(0.03, 0.04, 0.05, 0.6)
	_feed_style.set_content_margin_all(4)
	_feed_style.content_margin_left = 10
	_feed_style.content_margin_right = 10
	_feed_style.set_corner_radius_all(3)
	_feed_style_mine = _feed_style.duplicate()
	_feed_style_mine.border_color = Color(0.9, 0.2, 0.15)
	_feed_style_mine.set_border_width_all(2)
	_build_banner()
	var level := get_parent() as Level
	_top_bar.level = level
	if level and not level.preview_only:
		_minimap.build.call_deferred(level)
	else:
		_minimap.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if Match.is_ended():
		# Map vote on the results screen: keys 1–3.
		for i in 3:
			if event.is_action_pressed(StringName("weapon_%d" % (i + 1))):
				Match.request_vote(i)
				_refresh_vote()
				get_viewport().set_input_as_handled()
				return
		# Controller: next weapon (Y) cycles through the candidates.
		if event.is_action_pressed(&"weapon_next") and not Match.vote_maps.is_empty():
			Match.request_vote((Match.my_vote + 1) % Match.vote_maps.size())
			_refresh_vote()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"toggle_perf_overlay"):
		SettingsManager.show_perf_overlay = not SettingsManager.show_perf_overlay
		SettingsManager.save()
		_perf_label.visible = SettingsManager.show_perf_overlay


func _process(delta: float) -> void:
	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta * 0.8)
	# A full-screen quad costs fill rate even when transparent — hide it.
	_damage_flash.visible = _damage_flash.color.a > 0.001
	var show_scores := Input.is_action_pressed(&"scoreboard")
	if show_scores and not _scoreboard.visible:
		_refresh_scoreboard()
	_scoreboard.visible = show_scores
	if _player:
		_dead_label.visible = _player.health.is_dead and Match.mode != GameConfig.Mode.BOMB
		if _player.current_weapon != _weapon:
			_bind_weapon(_player.current_weapon)
	if _weapon:
		_update_crosshair()
		_reload_bar.visible = _weapon.is_reloading
		_reload_bar.value = _weapon.get_reload_progress()
		_scope.amount = clampf((_weapon.ads_blend - 0.85) / 0.15, 0.0, 1.0) if _weapon.data.scoped else 0.0
	_update_match_bar()
	_update_bomb_hud()
	_update_banner(delta)
	_location_timer -= delta
	if _location_timer <= 0.0:
		_location_timer = 0.25
		var level := get_parent() as Level
		var viewer: PlayerController = level.spectating() if level and level.spectating() else _player
		_location_label.text = _minimap.location(viewer.global_position) if viewer and _minimap.level else ""
	if _perf_label.visible:
		_update_perf()


func _bind_weapon(weapon: Weapon) -> void:
	_weapon = weapon
	if weapon == null:
		return
	_weapon_label.text = weapon.data.display_name
	_update_weapon_slots()
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.hit_confirmed.connect(_on_hit_confirmed)
	_on_ammo_changed(weapon.ammo_in_magazine, weapon.ammo_reserve)


func _on_hit_confirmed(kill: bool, head: bool) -> void:
	_crosshair.show_hit(kill)
	if SettingsManager.hit_sounds:
		Audio.play_ui(&"kill" if kill else (&"headshot" if head else &"hitmarker"), -4.0 if kill else -8.0)


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
	# White when healthy, red when low (the cross icon follows).
	_health_label.modulate = Color(1, 0.35, 0.3) if current <= maximum * 0.25 else Color.WHITE
	_health_icon.queue_redraw()


## "KASBAH / BOMB DEFUSAL" in the top-right when a map loads and when each
## Bomb Defusal round starts; fades out after a few seconds. The kill feed
## moves down while it is shown.
func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.name = "MapBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_banner.offset_left = -420.0
	_banner.offset_right = -24.0
	_banner.offset_top = 14.0
	_banner.alignment = BoxContainer.ALIGNMENT_BEGIN
	_banner.add_theme_constant_override(&"separation", -6)
	for spec: Array in [["Title", 44, Color(0.97, 0.94, 0.86)], ["Subtitle", 20, Color(1, 0.78, 0.45)]]:
		var l := Label.new()
		l.name = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_size_override(&"font_size", spec[1])
		l.add_theme_color_override(&"font_color", spec[2])
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override(&"outline_size", 8)
		_banner.add_child(l)
	add_child(_banner)
	_banner.visible = false


func show_banner() -> void:
	var level := get_parent()
	var path: String = level.scene_file_path if level and level.scene_file_path != "" else NetworkManager.current_map
	var map_name := GameConfig.map_name(path)
	(_banner.get_node(^"Title") as Label).text = map_name.to_upper()
	(_banner.get_node(^"Subtitle") as Label).text = GameConfig.MODE_NAMES[Match.mode].to_upper()
	_banner_time = BANNER_TIME
	_banner.visible = true


func _update_banner(delta: float) -> void:
	if _banner_round < 0 and get_parent() is Level and not NetworkManager.is_dedicated():
		_banner_round = 0
		show_banner()
	if Match.mode == GameConfig.Mode.BOMB and Match.bomb.round_number != _banner_round and Match.bomb.round_number > 0:
		_banner_round = Match.bomb.round_number
		show_banner()
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time / 1.0, 0.0, 1.0)
		if _banner_time <= 0.0:
			_banner.visible = false
	_kill_feed.offset_top = 104.0 if _banner.visible else 16.0
	_kill_feed.offset_bottom = _kill_feed.offset_top + 184.0


## Armour: shown while you have some (Bomb Defusal gives 100 each round).
func _on_armor_changed(armor: float) -> void:
	_armor_group.visible = armor > 0.0 or Match.mode == GameConfig.Mode.BOMB
	_armor_label.text = str(ceili(armor))
	_armor_bar.value = armor
	_armor_group.modulate.a = 1.0 if armor > 0.0 else 0.45


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	_ammo_icons.queue_redraw()
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
	var level := get_parent() as Level
	if level and level.dynamic_resolution and SettingsManager.dynamic_resolution:
		_perf_label.text += "\nDynamic res %d%%" % roundi(level.dynamic_resolution.scale * 100.0)
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


func _on_kill_feed(killer_id: int, victim_id: int, weapon_name: String, headshot: bool) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var panel := PanelContainer.new()
	row.add_child(panel)
	var box := HBoxContainer.new()
	panel.add_child(box)
	var local_id := multiplayer.get_unique_id()
	if killer_id >= 0 and killer_id != victim_id:
		box.add_child(_feed_label(NetworkManager.get_player_name(killer_id), killer_id))
		box.add_child(_feed_label("  [%s%s]  " % [weapon_name, " HS" if headshot else ""], -2))
		box.add_child(_feed_label(NetworkManager.get_player_name(victim_id), victim_id))
	else:
		box.add_child(_feed_label(NetworkManager.get_player_name(victim_id), victim_id))
		box.add_child(_feed_label("  fell", -2))
	# Your own kills and deaths get a red outline (as in CS).
	var mine := killer_id == local_id or victim_id == local_id
	panel.add_theme_stylebox_override(&"panel", _feed_style_mine if mine else _feed_style)
	row.modulate = Color(1, 1, 1, 1) if mine else Color(1, 1, 1, 0.9)
	_kill_feed.add_child(row)
	while _kill_feed.get_child_count() > KILL_FEED_MAX:
		_kill_feed.get_child(0).queue_free()
	get_tree().create_timer(KILL_FEED_TIME).timeout.connect(row.queue_free)


## Kill feed / scoreboard names are coloured by team (yellow = you).
func _feed_label(text: String, peer_id: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_constant_override(&"outline_size", 4)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_color_override(&"font_color", _name_color(peer_id))
	return l


func _name_color(peer_id: int) -> Color:
	if peer_id == -2:
		return Color(1, 1, 1, 0.8)
	if peer_id == multiplayer.get_unique_id():
		return Color(1, 0.85, 0.3)
	if Match.is_team_mode():
		return GameConfig.team_color(Match.get_team(peer_id)).lightened(0.25)
	return Color.WHITE


## Right-hand weapon list (CS style): the current weapon bright, others dim.
func _update_weapon_slots() -> void:
	if _player == null:
		return
	for child in _weapon_slots.get_children():
		child.queue_free()
	var ws := _player.loadout_weapons()
	for i in ws.size():
		if ws[i]:
			var current := i == _player.current_slot
			var l := Label.new()
			l.text = "%s   %d" % [ws[i].data.display_name.get_slice(" ", 0), i + 1]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.add_theme_font_size_override(&"font_size", 18 if current else 14)
			l.add_theme_color_override(&"font_color", Color(1, 0.9, 0.55) if current else Color(1, 1, 1, 0.55))
			l.add_theme_color_override(&"font_outline_color", Color.BLACK)
			l.add_theme_constant_override(&"outline_size", 4)
			_weapon_slots.add_child(l)
	# Grenades under the guns, with their quick-throw keys.
	var t := _player.throwables
	if t:
		for kind: int in [Throwables.Kind.HE, Throwables.Kind.MOLOTOV]:
			var l := Label.new()
			var n: int = t.counts[kind]
			l.text = "%s ×%d   %s" % [Throwables.SHORT_NAMES[kind], n, _key_name(Throwables.ACTIONS[kind])]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.add_theme_font_size_override(&"font_size", 13)
			l.add_theme_color_override(&"font_color", Color(0.75, 0.95, 0.6, 0.8) if n > 0 else Color(1, 1, 1, 0.25))
			l.add_theme_color_override(&"font_outline_color", Color.BLACK)
			l.add_theme_constant_override(&"outline_size", 4)
			_weapon_slots.add_child(l)


## Keyboard key bound to `action` ("G"), or "" if none.
static func _key_name(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return ""


## Objective line under the top bar (the clock and scores are drawn by TopBar).
func _update_match_bar() -> void:
	match Match.mode:
		GameConfig.Mode.PRACTICE:
			_match_bar.text = "Practice — %s" % GameConfig.map_name(NetworkManager.current_map)
		GameConfig.Mode.BOMB:
			var b := Match.bomb
			var my_team := Match.get_team(multiplayer.get_unique_id())
			var role := ""
			if my_team >= 0:
				var attacker := b.is_attacker(multiplayer.get_unique_id())
				if b.bomb_state == BombRules.BombState.PLANTED:
					role = "Protect the bomb at %s" % b.bomb_site if attacker else "Defuse the bomb at %s!" % b.bomb_site
				else:
					role = "Attack — plant the bomb at A or B" if attacker else "Defend — stop the plant or defuse"
			_match_bar.text = role
		GameConfig.Mode.TDM:
			var my_team := Match.get_team(multiplayer.get_unique_id())
			_match_bar.text = ("You are %s — first to %d" % [GameConfig.TEAM_NAMES[my_team], Match.score_limit]) \
				if my_team >= 0 else ""
		_:
			var mine: int = NetworkManager.roster.get(multiplayer.get_unique_id(), {}).get("kills", 0)
			var best := 0
			for id: int in NetworkManager.roster:
				best = maxi(best, NetworkManager.roster[id].kills)
			_match_bar.text = "You %d · Leader %d · First to %d" % [mine, best, Match.score_limit]


## Bomb Defusal: centre messages, plant/defuse progress, carrier hint, spectating.
func _update_bomb_hud() -> void:
	if Match.mode != GameConfig.Mode.BOMB or Match.bomb.round_number == 0:
		_center_message.text = ""
		_action_box.visible = false
		_bomb_hint.text = ""
		return
	var b := Match.bomb
	var me := multiplayer.get_unique_id()
	var msg := ""
	match b.phase:
		BombRules.Phase.FREEZE:
			if b.waiting_for_players:
				msg = "Waiting for players on both teams…"
			else:
				msg = ("Switching sides!\n" if b.sides_swapped else "") + "Round %d starts in %d" % [b.round_number, ceili(b.phase_time_left)]
		BombRules.Phase.PLANTED:
			msg = "BOMB PLANTED at %s" % b.bomb_site if b.phase_time_left > b.bomb_time - 3.0 else ""
		BombRules.Phase.ROUND_END:
			if b.round_winner >= 0:
				msg = "%s wins the round\n%s" % [GameConfig.TEAM_NAMES[b.round_winner], b.round_reason]
	if Match.is_ended():
		msg = ""
	_center_message.text = msg
	_center_message.modulate = GameConfig.team_color(b.round_winner).lightened(0.3) \
		if b.phase == BombRules.Phase.ROUND_END and b.round_winner >= 0 else Color.WHITE

	var acting := b.action != BombRules.Action.NONE and (b.action_player == me or b.bomb_state == BombRules.BombState.PLANTED)
	_action_box.visible = acting
	if acting:
		var who := "You are" if b.action_player == me else "%s is" % NetworkManager.get_player_name(b.action_player)
		_action_label.text = "%s %s…" % [who, "planting" if b.action == BombRules.Action.PLANT else "defusing"]
		_action_bar.value = b.action_progress

	var hint := ""
	if _player and not _player.health.is_dead:
		if b.bomb_state == BombRules.BombState.CARRIED and b.bomb_carrier == me:
			var site := b.site_at(_player.global_position)
			hint = "At site %s — hold %s to plant (stand still)" % [site, SettingsManager.prompt_text(&"interact")] if site != "" \
				else "You have the bomb — take it to site A or B"
		elif b.bomb_state == BombRules.BombState.PLANTED and not b.is_attacker(me) \
				and _player.global_position.distance_to(b.bomb_position) <= BombRules.DEFUSE_RANGE:
			hint = "Hold %s to defuse (stand still)" % SettingsManager.prompt_text(&"interact")
		elif b.bomb_state == BombRules.BombState.DROPPED and b.is_attacker(me):
			hint = "The bomb was dropped — pick it up"
	elif _player and _player.health.is_dead:
		var level := get_parent() as Level
		var watched := level.spectating() if level else null
		hint = ("Spectating %s — %s for next" % [watched.player_name, SettingsManager.prompt_text(&"shoot")]) \
			if watched else "Dead — wait for the next round"
	_bomb_hint.text = hint


func _on_match_state_changed() -> void:
	var ended := Match.is_ended()
	if ended and not _end_screen.visible:
		_winner_label.text = Match.winner_text
		_fill_score_grid(_end_grid)
	_end_screen.visible = ended
	if ended:
		_refresh_vote()


## "Vote for the next map: [1] Rooftops (2) …" on the results screen.
func _refresh_vote() -> void:
	if Match.vote_maps.is_empty():
		_next_map_label.text = "Next: %s" % GameConfig.map_name(GameConfig.next_map(NetworkManager.current_map, Match.mode))
		return
	var parts := PackedStringArray()
	for i in Match.vote_maps.size():
		var votes: int = Match.vote_counts[i] if i < Match.vote_counts.size() else 0
		parts.append("%s[%d] %s — %d vote%s" % ["» " if i == Match.my_vote else "", i + 1,
			GameConfig.map_name(Match.vote_maps[i]), votes, "" if votes == 1 else "s"])
	var how := "%s to change your vote" % SettingsManager.prompt_text(&"weapon_next") if GamepadInput.using_pad \
		else "keys 1–%d" % Match.vote_maps.size()
	_next_map_label.text = "Vote for the next map (%s):\n%s" % [how, "\n".join(parts)]


func player_name_or_empty() -> String:
	return _player.player_name if _player else ""


func _refresh_scoreboard() -> void:
	_fill_score_grid(_score_grid)
	var n := NetworkManager.roster.size()
	var where := "%s · %s" % [GameConfig.MODE_NAMES[Match.mode], GameConfig.map_name(NetworkManager.current_map)]
	match NetworkManager.mode:
		NetworkManager.Mode.OFFLINE: _server_label.text = "Offline · " + where
		NetworkManager.Mode.HOST: _server_label.text = "Hosting · %s · %d player(s)" % [where, n]
		_: _server_label.text = "Online · %s · %d player(s)" % [where, n]


## Sorted by team (team modes) then kills.
func _fill_score_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		child.queue_free()
	for header: String in ["Player", "Kills", "Deaths", "Ping"]:
		_add_score_cell(grid, header, Color(1, 1, 1, 0.6))
	var ids := NetworkManager.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ta := Match.get_team(a)
		var tb := Match.get_team(b)
		if ta != tb:
			return ta < tb
		return NetworkManager.roster[a].kills > NetworkManager.roster[b].kills)
	for id: int in ids:
		var e: Dictionary = NetworkManager.roster[id]
		var col := _name_color(id)
		_add_score_cell(grid, ("» " if VoiceChat.is_speaking(id) else "") + e.name, col)
		_add_score_cell(grid, str(e.kills), col)
		_add_score_cell(grid, str(e.deaths), col)
		_add_score_cell(grid, "host" if id == 1 else str(e.ping), col)


func _add_score_cell(grid: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
