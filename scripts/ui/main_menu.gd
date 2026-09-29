extends Control
## The STRIKE OPS lobby (main menu).
##
## Top bar: the logo, tabs (Lobby, Loadout, Character, Profile, Settings),
## your name, level and XP. Behind everything a small 3D stage shows your
## soldier — or, in a Custom match room, everyone in the room with their
## names and READY / NOT READY.
##
## Lobby tab: how to play on the left — Quick Play (join a server or host
## one now), Custom Match (a room: people join, chat and get ready while
## the host picks the map, mode and settings, then starts), Training
## (practice on your own) and Bot Match (against training bots). On the
## right: map cards (with rendered previews), game mode, match settings and
## the big START button. Bottom left: room chat and messages.

@warning_ignore_start("static_called_on_instance") # static helpers on autoloads (NetworkManager, SettingsManager…)
const ACCENT := Color(0.98, 0.78, 0.18)
const PANEL := Color(0.05, 0.06, 0.08, 0.86)
const LINE := Color(1, 1, 1, 0.09)
const GOOD := Color(0.45, 0.9, 0.45)
const BAD := Color(1.0, 0.4, 0.35)
const TABS: PackedStringArray = ["LOBBY", "LOADOUT", "CHARACTER", "PROFILE", "SETTINGS"]
## Left column: [id, icon, title, subtitle].
const PLAYS := [
	["quick", "play", "QUICK PLAY", "Join a match"],
	["custom", "room", "CUSTOM MATCH", "Create or join a room"],
	["training", "target", "TRAINING", "Practice shooting"],
	["bot", "bot", "BOT MATCH", "Play with bots"],
]
const MODE_CARDS := [
	[GameConfig.Mode.TDM, "tdm", "Team Deathmatch"],
	[GameConfig.Mode.BOMB, "bomb", "Bomb Defuse"],
	[GameConfig.Mode.FFA, "ffa", "Free For All"],
]
const TIME_OPTIONS: Array[float] = [300.0, 600.0, 900.0, 1200.0, 1800.0, 0.0]
const SCORE_OPTIONS := {
	GameConfig.Mode.FFA: [10, 20, 30, 50],
	GameConfig.Mode.TDM: [25, 50, 75, 100, 150],
	GameConfig.Mode.BOMB: [3, 5, 8, 13],
}
const MAX_PLAYER_OPTIONS: Array[int] = [2, 4, 6, 8, 10, 12, 16]
const MAX_ON_STAGE := 6

@onready var _settings: SettingsMenu = %SettingsMenu

var _tab := "LOBBY"
var _play := "bot"
var _map := ""
var _mode: int = GameConfig.Mode.TDM
var _opts := {}

# UI
var _tab_buttons: Dictionary = {}
var _play_buttons: Dictionary = {}
var _left: VBoxContainer
var _right: PanelContainer
var _right_box: VBoxContainer
var _map_cards: Dictionary = {} # path -> Button
var _mode_buttons: Dictionary = {} # mode -> Button
var _setting_values: Dictionary = {} # key -> Button
var _setting_rows: Dictionary = {} # key -> Control
var _start_button: Button
var _start_hint: Label
var _address_edit: LineEdit
var _chat_log: RichTextLabel
var _chat_edit: LineEdit
var _chat_title: Label
var _room_bar: PanelContainer
var _room_label: Label
var _room_buttons: HBoxContainer
var _ready_button: Button
var _loadout_panel: PanelContainer
var _profile_panel: PanelContainer
var _name_edit: LineEdit
var _level_label: Label
var _xp_bar: ProgressBar
var _player_name_label: Label
var _character_screen: CharacterScreen
var _render_generation := 0

# 3D stage
var _stage_vp: SubViewport
var _stage_cam: Camera3D
var _stage_root: Node3D
var _stage_models: Array[PlayerModel] = []
var _stage_ids: Array[int] = []
var _tags: Control
var _change_button: Button


func _ready() -> void:
	Audio.play_music(&"menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_map = SettingsManager.selected_map
	if GameConfig.map_index(_map) < 0:
		_map = GameConfig.MAPS[0].path
	_mode = SettingsManager.host_mode if SettingsManager.host_mode in [GameConfig.Mode.FFA, GameConfig.Mode.TDM,
		GameConfig.Mode.BOMB] else GameConfig.Mode.TDM
	_opts = SettingsManager.lobby.duplicate()
	_opts.bots = SettingsManager.bot_count
	_opts.bot_skill = SettingsManager.bot_difficulty
	_build_stage()
	_build_ui()
	_settings.closed.connect(func() -> void: _show_tab("LOBBY"))
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.room_changed.connect(_on_room_changed)
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.room_chat.connect(_on_chat)
	var status: String = NetworkManager.last_error
	NetworkManager.last_error = ""
	if not BenchmarkRunner.last_results.is_empty():
		status = BenchmarkRunner.summary_text(BenchmarkRunner.last_results)
		BenchmarkRunner.last_results = {}
	_set_status(status)
	var report_path := HardwareTest.take_pending_report()
	if report_path != "":
		_show_hardware_report.call_deferred(report_path)
	_select_play(_play)
	_show_tab("LOBBY")
	_refresh_profile()
	_start_button.grab_focus()


# =============================================================================
# Building the UI
# =============================================================================

func _build_ui() -> void:
	var ui := Control.new()
	ui.name = "UI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	move_child(ui, _settings.get_index())
	_tags = Control.new()
	_tags.name = "Tags"
	_tags.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_tags)
	_build_top_bar(ui)
	_build_left(ui)
	_build_right(ui)
	_build_chat(ui)
	_build_room_bar(ui)
	_build_loadout(ui)
	_build_profile(ui)
	var version := Label.new()
	version.name = "Version"
	version.text = NetworkManager.version_string()
	version.modulate = Color(1, 1, 1, 0.4)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -160
	version.offset_top = -26
	version.offset_right = -12
	version.offset_bottom = -6
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(version)
	_character_screen = CharacterScreen.new()
	_character_screen.name = "CharacterScreen"
	add_child(_character_screen)
	_character_screen.closed.connect(func() -> void:
		_refresh_stage()
		_show_tab("LOBBY"))


func _build_top_bar(ui: Control) -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 60
	bar.add_theme_stylebox_override(&"panel", _box(Color(0.03, 0.035, 0.05, 0.92), LINE, 0, 0))
	ui.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	bar.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(12, 0)
	row.add_child(pad)
	var logo := LobbyLogo.make(30)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(28, 0)
	row.add_child(gap)
	for t in TABS:
		var b := Button.new()
		b.name = "Tab" + t.capitalize()
		b.text = t
		b.flat = true
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(104, 60)
		b.add_theme_font_size_override(&"font_size", 15)
		b.add_theme_color_override(&"font_pressed_color", ACCENT)
		b.add_theme_color_override(&"font_hover_pressed_color", ACCENT)
		b.add_theme_stylebox_override(&"pressed", _underline())
		b.add_theme_stylebox_override(&"hover_pressed", _underline())
		b.pressed.connect(_show_tab.bind(t))
		row.add_child(b)
		_tab_buttons[t] = b
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	# Player card: icon, name, level + XP.
	var card := HBoxContainer.new()
	card.add_theme_constant_override(&"separation", 8)
	row.add_child(card)
	var face := PanelContainer.new()
	face.add_theme_stylebox_override(&"panel", _box(Color(0.12, 0.13, 0.16), LINE, 1, 4))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.add_child(LobbyIcon.make("person", 34))
	card.add_child(face)
	var who := VBoxContainer.new()
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_constant_override(&"separation", 0)
	card.add_child(who)
	_player_name_label = Label.new()
	_player_name_label.add_theme_font_size_override(&"font_size", 15)
	who.add_child(_player_name_label)
	var lv := HBoxContainer.new()
	who.add_child(lv)
	_level_label = Label.new()
	_level_label.add_theme_font_size_override(&"font_size", 12)
	_level_label.add_theme_color_override(&"font_color", ACCENT)
	lv.add_child(_level_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(70, 5)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.max_value = 1.0
	_xp_bar.add_theme_stylebox_override(&"fill", _box(ACCENT, Color.TRANSPARENT, 0, 2))
	_xp_bar.add_theme_stylebox_override(&"background", _box(Color(1, 1, 1, 0.15), Color.TRANSPARENT, 0, 2))
	lv.add_child(_xp_bar)
	var quit := Button.new()
	quit.name = "QuitButton"
	quit.flat = true
	quit.tooltip_text = "Quit"
	quit.custom_minimum_size = Vector2(52, 60)
	var qi := LobbyIcon.make("power", 22)
	qi.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	qi.position -= Vector2(11, 11)
	quit.add_child(qi)
	quit.pressed.connect(get_tree().quit)
	row.add_child(quit)


func _build_left(ui: Control) -> void:
	_left = VBoxContainer.new()
	_left.name = "Plays"
	_left.position = Vector2(18, 80)
	_left.custom_minimum_size = Vector2(268, 0)
	_left.add_theme_constant_override(&"separation", 10)
	ui.add_child(_left)
	for spec: Array in PLAYS:
		var b := Button.new()
		b.name = "Play_" + spec[0]
		b.custom_minimum_size = Vector2(268, 74)
		b.toggle_mode = true
		b.add_theme_stylebox_override(&"normal", _box(PANEL, LINE, 1, 3))
		b.add_theme_stylebox_override(&"hover", _box(Color(0.1, 0.11, 0.14, 0.92), Color(1, 1, 1, 0.2), 1, 3))
		b.add_theme_stylebox_override(&"pressed", _box(Color(0.1, 0.1, 0.08, 0.94), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"hover_pressed", _box(Color(0.12, 0.12, 0.09, 0.94), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"focus", _box(Color.TRANSPARENT, Color(1, 1, 1, 0.35), 1, 3))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 16
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 16)
		b.add_child(row)
		var icon := LobbyIcon.make(spec[1], 38)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override(&"separation", 0)
		row.add_child(text)
		var t := Label.new()
		t.text = spec[2]
		t.add_theme_font_size_override(&"font_size", 20)
		text.add_child(t)
		var s := Label.new()
		s.text = spec[3]
		s.modulate = Color(1, 1, 1, 0.6)
		s.add_theme_font_size_override(&"font_size", 13)
		text.add_child(s)
		b.pressed.connect(_select_play.bind(spec[0]))
		_left.add_child(b)
		_play_buttons[spec[0]] = b


func _build_right(ui: Control) -> void:
	_right = PanelContainer.new()
	_right.name = "Setup"
	_right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_right.offset_left = -400
	_right.offset_right = -14
	_right.offset_top = 74
	_right.offset_bottom = -14
	_right.add_theme_stylebox_override(&"panel", _box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0))
	ui.add_child(_right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_right.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_right_box)
	_start_hint = Label.new()
	_start_hint.name = "StartHint"
	_start_hint.modulate = Color(1, 1, 1, 0.65)
	_start_hint.add_theme_font_size_override(&"font_size", 13)
	_start_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_start_hint)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.custom_minimum_size = Vector2(0, 58)
	_start_button.add_theme_font_size_override(&"font_size", 26)
	_start_button.add_theme_color_override(&"font_color", Color(0.08, 0.07, 0.03))
	_start_button.add_theme_color_override(&"font_hover_color", Color(0.08, 0.07, 0.03))
	_start_button.add_theme_color_override(&"font_pressed_color", Color(0.08, 0.07, 0.03))
	_start_button.add_theme_color_override(&"font_focus_color", Color(0.08, 0.07, 0.03))
	_start_button.add_theme_color_override(&"font_disabled_color", Color(0.2, 0.2, 0.2))
	_start_button.add_theme_stylebox_override(&"normal", _box(ACCENT, Color.TRANSPARENT, 0, 3))
	_start_button.add_theme_stylebox_override(&"hover", _box(ACCENT.lightened(0.15), Color.TRANSPARENT, 0, 3))
	_start_button.add_theme_stylebox_override(&"pressed", _box(ACCENT.darkened(0.15), Color.TRANSPARENT, 0, 3))
	_start_button.add_theme_stylebox_override(&"focus", _box(Color.TRANSPARENT, Color.WHITE, 2, 3))
	_start_button.add_theme_stylebox_override(&"disabled", _box(Color(0.35, 0.33, 0.25), Color.TRANSPARENT, 0, 3))
	_start_button.pressed.connect(_on_start)
	col.add_child(_start_button)


## Fills the right panel for the selected way to play.
func _rebuild_right() -> void:
	for c in _right_box.get_children():
		c.queue_free()
	_map_cards.clear()
	_mode_buttons.clear()
	_setting_values.clear()
	_setting_rows.clear()
	match _play:
		"quick":
			_right_box.add_child(_heading("JOIN A MATCH"))
			var row := HBoxContainer.new()
			_right_box.add_child(row)
			_address_edit = _address_field()
			row.add_child(_address_edit)
			_right_box.add_child(_note("Type the host's address (IP or IP:port) — the host sees it on INVITE."))
			_right_box.add_child(_heading("OR HOST A SERVER NOW"))
			_right_box.add_child(_note("Starts right away with the map, mode and settings below; others join any time."))
			_add_map_grid()
			_add_modes()
			_add_settings(["time_limit", "score_limit", "bots", "bot_skill", "friendly_fire"])
			var host := _secondary_button("HOST NOW")
			host.name = "HostButton"
			host.pressed.connect(_on_host_now)
			_right_box.add_child(host)
		"custom":
			var in_room := NetworkManager.in_room
			var host := in_room and multiplayer.is_server()
			_add_map_grid(not in_room or host)
			_add_modes(not in_room or host)
			_add_settings(["time_limit", "score_limit", "bots", "bot_skill", "friendly_fire", "max_players"],
				not in_room or host)
			if not in_room:
				_right_box.add_child(_heading("JOIN A ROOM"))
				var row := HBoxContainer.new()
				_right_box.add_child(row)
				_address_edit = _address_field()
				row.add_child(_address_edit)
				var join := _secondary_button("JOIN")
				join.name = "JoinButton"
				join.custom_minimum_size = Vector2(90, 38)
				join.pressed.connect(_on_join)
				row.add_child(join)
		"training":
			_right_box.add_child(_heading("TRAINING"))
			_right_box.add_child(_note("On your own: shoot the targets on the Test Range, or walk any map to learn it."))
			_add_map_grid()
		"bot":
			_add_map_grid()
			_add_modes()
			_add_settings(["time_limit", "score_limit", "bots", "bot_skill", "friendly_fire"])
	_render_map_previews()
	_refresh_setup()


func _add_map_grid(editable: bool = true) -> void:
	_right_box.add_child(_heading("MAP SELECTION"))
	var grid := GridContainer.new()
	grid.name = "MapGrid"
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	_right_box.add_child(grid)
	var maps: Array = GameConfig.MAPS.duplicate()
	maps.append({ "path": "random", "name": "Random" })
	for m: Dictionary in maps:
		var path: String = m.path
		var b := Button.new()
		b.name = "Map_" + String(m.get("id", "random"))
		b.toggle_mode = true
		b.disabled = not editable
		b.custom_minimum_size = Vector2(120, 70)
		b.clip_contents = true
		b.add_theme_stylebox_override(&"normal", _box(Color(0.09, 0.1, 0.13, 0.95), LINE, 1, 3))
		b.add_theme_stylebox_override(&"hover", _box(Color(0.12, 0.13, 0.16, 0.95), Color(1, 1, 1, 0.3), 1, 3))
		b.add_theme_stylebox_override(&"pressed", _box(Color(0.12, 0.12, 0.1, 0.95), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"hover_pressed", _box(Color(0.12, 0.12, 0.1, 0.95), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"disabled", _box(Color(0.08, 0.08, 0.1, 0.95), LINE, 1, 3))
		var pic := TextureRect.new()
		pic.name = "Picture"
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = 2
		pic.offset_top = 2
		pic.offset_right = -2
		pic.offset_bottom = -2
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.texture = MapPreview.cached(path) if path != "random" else null
		b.add_child(pic)
		if path == "random":
			var icon := LobbyIcon.make("random", 30)
			icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			icon.position -= Vector2(15, 24)
			b.add_child(icon)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.55)
		shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		shade.offset_top = -22
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(shade)
		var name_label := Label.new()
		name_label.text = m.name
		name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		name_label.offset_left = 6
		name_label.offset_top = -22
		name_label.add_theme_font_size_override(&"font_size", 13)
		b.add_child(name_label)
		var tick := Label.new()
		tick.name = "Tick"
		tick.text = "✔"
		tick.add_theme_color_override(&"font_color", Color(0.1, 0.08, 0.02))
		var tick_bg := PanelContainer.new()
		tick_bg.name = "TickBox"
		tick_bg.add_theme_stylebox_override(&"panel", _box(ACCENT, Color.TRANSPARENT, 0, 2))
		tick_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tick_bg.offset_left = -24
		tick_bg.offset_bottom = 22
		tick_bg.add_child(tick)
		tick_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tick_bg)
		b.pressed.connect(_pick_map.bind(path))
		grid.add_child(b)
		_map_cards[path] = b


func _add_modes(editable: bool = true) -> void:
	_right_box.add_child(_heading("GAME MODE"))
	var row := HBoxContainer.new()
	row.name = "Modes"
	row.add_theme_constant_override(&"separation", 8)
	_right_box.add_child(row)
	for spec: Array in MODE_CARDS:
		var b := Button.new()
		b.name = "Mode_%d" % spec[0]
		b.toggle_mode = true
		b.disabled = not editable
		b.custom_minimum_size = Vector2(116, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override(&"normal", _box(PANEL, LINE, 1, 3))
		b.add_theme_stylebox_override(&"pressed", _box(Color(0.12, 0.12, 0.09, 0.95), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"hover_pressed", _box(Color(0.12, 0.12, 0.09, 0.95), ACCENT, 2, 3))
		b.add_theme_stylebox_override(&"disabled", _box(Color(0.05, 0.05, 0.06, 0.8), LINE, 1, 3))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var icon := LobbyIcon.make(spec[1], 24)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(icon)
		var l := Label.new()
		l.text = spec[2]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", 13)
		v.add_child(l)
		b.pressed.connect(_pick_mode.bind(spec[0]))
		row.add_child(b)
		_mode_buttons[spec[0]] = b


func _add_settings(keys: Array, editable: bool = true) -> void:
	_right_box.add_child(_heading("MATCH SETTINGS"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	_right_box.add_child(box)
	for key: String in keys:
		var row := PanelContainer.new()
		row.name = "Setting_" + key
		row.add_theme_stylebox_override(&"panel", _box(PANEL, LINE, 1, 2, 0))
		var h := HBoxContainer.new()
		row.add_child(h)
		var label := Label.new()
		label.name = "Label"
		label.custom_minimum_size = Vector2(150, 0)
		label.add_theme_font_size_override(&"font_size", 14)
		h.add_child(label)
		var prev := _arrow("◀")
		prev.disabled = not editable
		prev.pressed.connect(_step_setting.bind(key, -1))
		h.add_child(prev)
		var value := Button.new()
		value.name = "Value"
		value.flat = true
		value.disabled = not editable
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.add_theme_font_size_override(&"font_size", 14)
		value.pressed.connect(_step_setting.bind(key, 1))
		h.add_child(value)
		var next := _arrow("▶")
		next.disabled = not editable
		next.pressed.connect(_step_setting.bind(key, 1))
		h.add_child(next)
		box.add_child(row)
		_setting_values[key] = value
		_setting_rows[key] = row


func _build_chat(ui: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "Chat"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 18
	panel.offset_top = -214
	panel.offset_right = 448
	panel.offset_bottom = -14
	panel.add_theme_stylebox_override(&"panel", _box(PANEL, LINE, 1, 3))
	ui.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	_chat_title = Label.new()
	_chat_title.add_theme_font_size_override(&"font_size", 13)
	_chat_title.add_theme_color_override(&"font_color", ACCENT)
	v.add_child(_chat_title)
	_chat_log = RichTextLabel.new()
	_chat_log.name = "ChatLog"
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override(&"normal_font_size", 13)
	v.add_child(_chat_log)
	var status := get_node("%StatusLabel") as Label
	status.reparent(v)
	status.add_theme_font_size_override(&"font_size", 13)
	var row := HBoxContainer.new()
	v.add_child(row)
	_chat_edit = LineEdit.new()
	_chat_edit.name = "ChatEdit"
	_chat_edit.placeholder_text = "Type a message…"
	_chat_edit.max_length = NetworkManager.CHAT_MAX
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _send_chat())
	row.add_child(_chat_edit)
	var send := Button.new()
	send.custom_minimum_size = Vector2(40, 32)
	send.tooltip_text = "Send"
	var si := LobbyIcon.make("send", 18)
	si.position = Vector2(11, 7)
	send.add_child(si)
	send.pressed.connect(_send_chat)
	row.add_child(send)


func _build_room_bar(ui: Control) -> void:
	_room_bar = PanelContainer.new()
	_room_bar.name = "RoomBar"
	_room_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_room_bar.offset_left = -230
	_room_bar.offset_right = 150
	_room_bar.offset_top = 72
	_room_bar.offset_bottom = 110
	_room_bar.add_theme_stylebox_override(&"panel", _box(PANEL, LINE, 1, 3))
	ui.add_child(_room_bar)
	_room_label = Label.new()
	_room_label.name = "RoomLabel"
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_size_override(&"font_size", 14)
	_room_bar.add_child(_room_label)
	_room_buttons = HBoxContainer.new()
	_room_buttons.name = "RoomButtons"
	_room_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_room_buttons.offset_left = -240
	_room_buttons.offset_right = 160
	_room_buttons.offset_top = -62
	_room_buttons.offset_bottom = -16
	_room_buttons.add_theme_constant_override(&"separation", 10)
	ui.add_child(_room_buttons)
	var invite := _secondary_button("INVITE")
	invite.name = "InviteButton"
	invite.tooltip_text = "Copy the room's address to send to friends"
	invite.pressed.connect(_on_invite)
	_room_buttons.add_child(invite)
	_ready_button = _secondary_button("READY")
	_ready_button.name = "ReadyButton"
	_ready_button.toggle_mode = true
	_ready_button.toggled.connect(func(on: bool) -> void:
		NetworkManager.set_ready(on)
		_ready_button.text = "READY ✔" if on else "READY")
	_room_buttons.add_child(_ready_button)
	var leave := _secondary_button("LEAVE ROOM")
	leave.name = "LeaveButton"
	leave.add_theme_color_override(&"font_color", BAD)
	leave.pressed.connect(func() -> void: NetworkManager.leave(""))
	_room_buttons.add_child(leave)


func _build_loadout(ui: Control) -> void:
	_loadout_panel = PanelContainer.new()
	_loadout_panel.name = "Loadout"
	_loadout_panel.position = Vector2(18, 80)
	_loadout_panel.custom_minimum_size = Vector2(330, 0)
	_loadout_panel.add_theme_stylebox_override(&"panel", _box(PANEL, LINE, 1, 3))
	ui.add_child(_loadout_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	_loadout_panel.add_child(v)
	v.add_child(_heading("PRIMARY WEAPON"))
	v.add_child(_note("Your gun in Free For All and Team Deathmatch (Bomb Defusal: buy with X)."))
	var list := VBoxContainer.new()
	list.name = "Guns"
	v.add_child(list)
	var stats := RichTextLabel.new()
	stats.name = "GunStats"
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.custom_minimum_size = Vector2(300, 0)
	for id: String in GameConfig.PRIMARY_WEAPONS:
		var b := Button.new()
		b.name = "Gun_" + id
		b.text = GameConfig.PRIMARY_NAMES[id]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_stylebox_override(&"pressed", _box(Color(0.12, 0.12, 0.09, 0.95), ACCENT, 2, 3))
		b.pressed.connect(func() -> void:
			SettingsManager.preferred_primary = id
			SettingsManager.save()
			_refresh_loadout(stats)
			_refresh_stage())
		list.add_child(b)
	v.add_child(stats)
	_refresh_loadout(stats)


func _refresh_loadout(stats: RichTextLabel) -> void:
	var id := SettingsManager.preferred_primary
	for b in _loadout_panel.find_child("Guns", true, false).get_children():
		(b as Button).set_pressed_no_signal(b.name == "Gun_" + id)
	var data := load(GameConfig.WEAPONS[id].replace("scenes/weapons", "resources/weapons").replace(".tscn", ".tres")) as WeaponData
	if data == null:
		for f in DirAccess.get_files_at("res://resources/weapons"):
			var d := load("res://resources/weapons/" + f) as WeaponData
			if d and d.weapon_id == id:
				data = d
	if data == null:
		stats.text = ""
		return
	var bar := func(label: String, v: float) -> String:
		var n := clampi(roundi(v * 10.0), 1, 10)
		return "%-10s [color=#%s]%s[/color][color=#444]%s[/color]\n" % [label, ACCENT.to_html(false),
			"■".repeat(n), "■".repeat(10 - n)]
	var dps := data.damage * data.pellets * data.fire_rate / 60.0
	stats.text = "[b]%s[/b]\n\n" % data.display_name + bar.call("Damage", data.damage * data.pellets / 110.0) \
		+ bar.call("Fire rate", data.fire_rate / 900.0) + bar.call("DPS", dps / 450.0) \
		+ bar.call("Magazine", data.magazine_size / 100.0) + bar.call("Range", data.max_range / 300.0) \
		+ bar.call("Mobility", (data.move_speed_multiplier - 0.7) / 0.3) \
		+ "\n%d rounds · reload %.1f s%s" % [data.magazine_size, data.reload_time,
			" · shell by shell" if data.shell_reload else ""]


func _build_profile(ui: Control) -> void:
	_profile_panel = PanelContainer.new()
	_profile_panel.name = "Profile"
	_profile_panel.position = Vector2(18, 80)
	_profile_panel.custom_minimum_size = Vector2(360, 0)
	_profile_panel.add_theme_stylebox_override(&"panel", _box(PANEL, LINE, 1, 3))
	ui.add_child(_profile_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	_profile_panel.add_child(v)
	v.add_child(_heading("PROFILE"))
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Player name"
	_name_edit.max_length = 16
	_name_edit.text = SettingsManager.player_name
	_name_edit.text_changed.connect(func(_t: String) -> void: _store_name())
	v.add_child(_name_edit)
	var stats := RichTextLabel.new()
	stats.name = "ProfileStats"
	stats.bbcode_enabled = true
	stats.fit_content = true
	v.add_child(stats)
	var bug := _secondary_button("REPORT A BUG")
	bug.name = "BugButton"
	bug.pressed.connect(func() -> void:
		BugReport.open()
		_set_status("Bug report opened in your browser (system details copied to the clipboard)."))
	v.add_child(bug)


func _refresh_profile() -> void:
	var p := SettingsManager.profile
	var level := SettingsManager.level_of(p)
	var xp := SettingsManager.xp_of(p)
	_player_name_label.text = SettingsManager.player_name
	_level_label.text = "Lv. %d " % level
	_xp_bar.value = fmod(float(xp), 1000.0) / 1000.0
	var stats := _profile_panel.find_child("ProfileStats", true, false) as RichTextLabel
	var kd := float(p.kills) / maxf(float(p.deaths), 1.0)
	var rate := 100.0 * float(p.wins) / maxf(float(p.matches), 1.0)
	stats.text = ("Level [b]%d[/b] — %d / 1000 XP to the next\n\nMatches  [b]%d[/b]\nWins  [b]%d[/b]  (%.0f %%)\n" +
		"Kills  [b]%d[/b]\nDeaths  [b]%d[/b]\nK/D  [b]%.2f[/b]\n\n[color=#999]100 XP a match, 250 a win, 20 a kill " +
		"(not in Training).[/color]") % [level, xp % 1000, p.matches, p.wins, rate, p.kills, p.deaths, kd]


# =============================================================================
# The 3D stage behind the lobby
# =============================================================================

func _build_stage() -> void:
	var holder := SubViewportContainer.new()
	holder.name = "Stage"
	holder.stretch = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	move_child(holder, 1)
	_stage_vp = SubViewport.new()
	_stage_vp.own_world_3d = true
	_stage_vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_stage_vp)
	if DisplayServer.get_name() == "headless":
		_stage_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage_root = Node3D.new()
	_stage_vp.add_child(_stage_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.055, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.55)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.2, 0.18, 0.15)
	e.fog_density = 0.02
	env.environment = e
	_stage_root.add_child(env)
	# A warehouse corner: wet concrete floor, a back wall, crates, a lamp.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.13, 0.13, 0.14)
	floor_mat.roughness = 0.25
	floor_mat.metallic = 0.2
	_stage_box(Vector3(0, -0.05, -2), Vector3(30, 0.1, 20), floor_mat)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.24, 0.24, 0.26)
	wall.roughness = 0.9
	_stage_box(Vector3(0, 4, -7), Vector3(30, 8, 0.2), wall)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		_stage_box(Vector3(x, 4, -6.8), Vector3(0.4, 8, 0.4), wall)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.22, 0.2, 0.16)
	crate.roughness = 0.8
	for spec: Array in [[Vector3(-5.2, 0.6, -3.6), 1.2], [Vector3(-4.1, 0.5, -4.4), 1.0], [Vector3(-5.0, 1.8, -3.8), 1.1],
			[Vector3(5.4, 0.7, -4.0), 1.4], [Vector3(4.2, 0.45, -3.2), 0.9], [Vector3(6.3, 0.6, -5.2), 1.2]]:
		_stage_box(spec[0], Vector3.ONE * float(spec[1]), crate)
	var lamp := StandardMaterial3D.new()
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.6)
	lamp.emission_energy_multiplier = 3.0
	for x in [-3.0, 3.0]:
		_stage_box(Vector3(x, 5.2, -3.0), Vector3(1.6, 0.08, 0.3), lamp)
	var key := SpotLight3D.new()
	key.position = Vector3(1.5, 5.5, 3.0)
	key.look_at_from_position(key.position, Vector3(0, 1.0, 0))
	key.spot_range = 14.0
	key.spot_angle = 38.0
	key.light_energy = 3.2
	key.light_color = Color(1.0, 0.9, 0.78)
	key.shadow_enabled = true
	_stage_root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-3, 3.5, -3.5)
	rim.omni_range = 9.0
	rim.light_energy = 1.4
	rim.light_color = Color(0.6, 0.72, 1.0)
	_stage_root.add_child(rim)
	var warm := OmniLight3D.new()
	warm.position = Vector3(5, 2.0, -2.5)
	warm.omni_range = 7.0
	warm.light_energy = 1.2
	warm.light_color = Color(1.0, 0.6, 0.3)
	_stage_root.add_child(warm)
	_stage_cam = Camera3D.new()
	_stage_cam.fov = 34.0
	# Looking a little right of the group, so it stands in the free space
	# between the left column and the setup panel.
	_stage_cam.position = Vector3(-0.05, 1.2, 6.4)
	_stage_root.add_child(_stage_cam)
	_stage_cam.look_at(Vector3(-0.05, 0.95, 0))
	_stage_cam.current = true


func _stage_box(pos: Vector3, box_size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_stage_root.add_child(mi)


## Who stands on the stage: the room's members, or just you.
func _stage_members() -> Array[int]:
	var ids: Array[int] = []
	if NetworkManager.in_room:
		for id: int in NetworkManager.roster:
			ids.append(id)
		ids.sort()
	else:
		ids.append(-1) # you, from your settings
	return ids.slice(0, MAX_ON_STAGE)


func _refresh_stage() -> void:
	var ids := _stage_members()
	while _stage_models.size() < ids.size():
		var m := PlayerModel.new()
		_stage_root.add_child(m)
		_stage_models.append(m)
	while _stage_models.size() > ids.size():
		_stage_models.pop_back().queue_free()
	_stage_ids = ids
	var n := ids.size()
	var spacing := minf(1.05, 2.6 / maxf(n - 1, 1))
	for i in n:
		var m := _stage_models[i]
		var id := ids[i]
		var look: Dictionary = SettingsManager.character if id == -1 or id == multiplayer.get_unique_id() \
			else NetworkManager.look_of(id)
		m.set_look(look)
		var primary: String = SettingsManager.preferred_primary if id == -1 or id == multiplayer.get_unique_id() \
			else String(NetworkManager.roster.get(id, {}).get("primary", "rifle"))
		m.set_weapon(primary)
		m.set_team_color(Color(0.55, 0.6, 0.66) if n == 1 else GameConfig.team_color(
			NetworkManager.roster.get(id, {}).get("team", -1)) if Match.is_team_mode() else Color(0.55, 0.6, 0.66))
		var x := (i - (n - 1) * 0.5) * spacing - 0.35
		m.position = Vector3(x, 0, -0.2 * absf(i - (n - 1) * 0.5))
		m.rotation.y = PI + (x + 0.35) * -0.12
	_rebuild_tags()


## Name tags over the soldiers (READY / NOT READY and a crown for the host
## in a room) and a Change button under yours.
func _rebuild_tags() -> void:
	for c in _tags.get_children():
		_tags.remove_child(c) # now, so the new tags get the same names
		c.queue_free()
	_change_button = null
	for i in _stage_ids.size():
		var id := _stage_ids[i]
		var mine := id == -1 or id == multiplayer.get_unique_id()
		var tag := VBoxContainer.new()
		tag.name = "Tag_%d" % id
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_constant_override(&"separation", 0)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		tag.add_child(top)
		if NetworkManager.in_room and id == 1:
			top.add_child(LobbyIcon.make("crown", 16, ACCENT))
		var name_label := Label.new()
		name_label.text = SettingsManager.player_name if id == -1 else NetworkManager.get_player_name(id)
		name_label.add_theme_font_size_override(&"font_size", 17)
		name_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
		name_label.add_theme_constant_override(&"outline_size", 4)
		top.add_child(name_label)
		if NetworkManager.in_room:
			var is_ready := bool(NetworkManager.roster.get(id, {}).get("ready", false)) or BotManager.is_bot(id)
			var state := Label.new()
			state.name = "State"
			state.text = "READY" if is_ready else "NOT READY"
			state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			state.add_theme_font_size_override(&"font_size", 13)
			state.add_theme_color_override(&"font_color", GOOD if is_ready else BAD)
			tag.add_child(state)
		_tags.add_child(tag)
		if mine:
			_change_button = _secondary_button("CHANGE")
			_change_button.name = "ChangeButton"
			_change_button.custom_minimum_size = Vector2(110, 34)
			_change_button.tooltip_text = "Change your character"
			_change_button.pressed.connect(func() -> void: _show_tab("CHARACTER"))
			_tags.add_child(_change_button)


func _process(_delta: float) -> void:
	# Soldiers breathe a little; tags follow their heads.
	for i in _stage_models.size():
		var m := _stage_models[i]
		m.position.y = sin(Time.get_ticks_msec() / 900.0 + i) * 0.006
	if _stage_cam == null or _tags == null:
		return
	var scale_to_ui := size / Vector2(_stage_vp.size) if _stage_vp.size.x > 0 else Vector2.ONE
	var ti := 0
	for c in _tags.get_children():
		if c.is_queued_for_deletion():
			continue
		if c == _change_button:
			continue
		if ti < _stage_models.size():
			var head := _stage_models[ti].global_position + Vector3(0, 1.9, 0)
			var p := _stage_cam.unproject_position(head) * scale_to_ui
			var tag := c as Control
			tag.position = p - Vector2(tag.size.x * 0.5, tag.size.y)
			var feet := _stage_cam.unproject_position(_stage_models[ti].global_position) * scale_to_ui
			if _change_button and _stage_ids[ti] in [-1, multiplayer.get_unique_id()]:
				# At knee height (the chat panel sits below the feet).
				_change_button.position = feet + Vector2(-_change_button.size.x * 0.5, -_change_button.size.y - 70)
		ti += 1


# =============================================================================
# State and actions
# =============================================================================

func _show_tab(t: String) -> void:
	_tab = t
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == t)
	var lobby := t == "LOBBY"
	_left.visible = lobby
	_right.visible = lobby
	_loadout_panel.visible = t == "LOADOUT"
	_profile_panel.visible = t == "PROFILE"
	(find_child("Chat", true, false) as Control).visible = lobby
	_tags.visible = lobby
	_refresh_room_ui()
	match t:
		"CHARACTER":
			_character_screen.open()
		"SETTINGS":
			_settings.open()
		"PROFILE":
			_name_edit.text = SettingsManager.player_name
			_refresh_profile()
	_refresh_stage()


func _select_play(id: String) -> void:
	if NetworkManager.in_room and id != "custom":
		id = "custom" # leave the room first
	_play = id
	if id == "bot" and int(_opts.get("bots", 0)) == 0:
		_opts.bots = 5 # a bot match needs bots
	for k: String in _play_buttons:
		(_play_buttons[k] as Button).set_pressed_no_signal(k == id)
	_rebuild_right()


func _pick_map(path: String) -> void:
	_map = path
	if _map != "random":
		SettingsManager.selected_map = _map
		if _mode == GameConfig.Mode.BOMB and not GameConfig.map_info(_map).get("bomb", false):
			_mode = GameConfig.Mode.TDM
	_push_room()
	_refresh_setup()


func _pick_mode(m: int) -> void:
	_mode = m
	SettingsManager.host_mode = m
	var scores: Array = SCORE_OPTIONS[m]
	if not int(_opts.get("score_limit", 0)) in scores:
		_opts.score_limit = 0
	_push_room()
	_refresh_setup()


func _step_setting(key: String, dir: int) -> void:
	match key:
		"time_limit":
			var i := TIME_OPTIONS.find(float(_opts.get("time_limit", 600.0)))
			_opts.time_limit = TIME_OPTIONS[posmod(maxi(i, 0) + dir, TIME_OPTIONS.size())]
		"score_limit":
			var list: Array = SCORE_OPTIONS[_mode]
			var i := list.find(_score_limit())
			_opts.score_limit = list[posmod(maxi(i, 0) + dir, list.size())]
		"bots":
			_opts.bots = posmod(int(_opts.get("bots", 0)) + dir, BotManager.MAX_BOTS + 1)
		"bot_skill":
			_opts.bot_skill = posmod(int(_opts.get("bot_skill", 1)) + dir, 3)
		"friendly_fire":
			_opts.friendly_fire = not bool(_opts.get("friendly_fire", false))
		"max_players":
			var i := MAX_PLAYER_OPTIONS.find(int(_opts.get("max_players", 8)))
			_opts.max_players = MAX_PLAYER_OPTIONS[posmod(maxi(i, 0) + dir, MAX_PLAYER_OPTIONS.size())]
	_save_opts()
	_push_room()
	_refresh_setup()


func _score_limit() -> int:
	var v := int(_opts.get("score_limit", 0))
	var list: Array = SCORE_OPTIONS[_mode]
	return v if v in list else int(GameConfig.MODE_LIMITS[_mode].score_limit)


func _save_opts() -> void:
	for k in ["time_limit", "score_limit", "friendly_fire", "max_players"]:
		SettingsManager.lobby[k] = _opts.get(k, SettingsManager.lobby.get(k))
	SettingsManager.bot_count = int(_opts.get("bots", 0))
	SettingsManager.bot_difficulty = int(_opts.get("bot_skill", 1))
	Match.bots.difficulty = SettingsManager.bot_difficulty
	SettingsManager.save()


## The settings as a room (NetworkManager.ROOM_KEYS).
func _room_settings() -> Dictionary:
	return {
		"map": _resolved_map(), "mode": _mode, "time_limit": float(_opts.get("time_limit", 600.0)),
		"score_limit": _score_limit(), "bots": int(_opts.get("bots", 0)), "bot_skill": int(_opts.get("bot_skill", 1)),
		"friendly_fire": bool(_opts.get("friendly_fire", false)), "max_players": int(_opts.get("max_players", 8)),
	}


## "random" → a map that suits the mode.
func _resolved_map() -> String:
	if _map != "random":
		return _map
	var pool: Array = GameConfig.MAPS.filter(func(m: Dictionary) -> bool:
		return m.id != "test_map" and (_mode != GameConfig.Mode.BOMB or m.get("bomb", false)))
	return (pool[randi() % pool.size()] as Dictionary).path


func _push_room() -> void:
	if NetworkManager.in_room and multiplayer.is_server():
		var r := _room_settings()
		if _map == "random":
			r.map = NetworkManager.room.get("map", r.map)
		NetworkManager.set_room(r)


## Shows the current choices on the cards, rows and START button.
func _refresh_setup() -> void:
	var in_room := NetworkManager.in_room
	if in_room:
		# Everyone shows the host's room.
		var r := NetworkManager.room
		_map = r.get("map", _map) if not (multiplayer.is_server() and _map == "random") else _map
		_mode = int(r.get("mode", _mode))
		for k in ["time_limit", "bots", "bot_skill", "friendly_fire", "max_players"]:
			_opts[k] = r.get(k, _opts.get(k))
		_opts.score_limit = int(r.get("score_limit", 0))
	for path: String in _map_cards:
		var b := _map_cards[path] as Button
		var bomb_ok: bool = path == "random" or _mode != GameConfig.Mode.BOMB or GameConfig.map_info(path).get("bomb", false)
		b.set_pressed_no_signal(path == _map)
		(b.get_node("TickBox") as Control).visible = path == _map
		b.modulate = Color.WHITE if bomb_ok else Color(1, 1, 1, 0.35)
		b.tooltip_text = "" if bomb_ok else "No bomb sites on this map"
	var map_bomb: bool = _map == "random" or GameConfig.map_info(_map).get("bomb", false)
	for m: int in _mode_buttons:
		var b := _mode_buttons[m] as Button
		b.set_pressed_no_signal(m == _mode)
		if m == GameConfig.Mode.BOMB and not map_bomb:
			b.disabled = true
	for key: String in _setting_values:
		var label := (_setting_rows[key] as Control).find_child("Label", true, false) as Label
		var value := _setting_values[key] as Button
		match key:
			"time_limit":
				label.text = "Round Time" if _mode != GameConfig.Mode.BOMB else "Round Time"
				var t := float(_opts.get("time_limit", 600.0))
				value.text = ("%d Minutes" % roundi(t / 60.0)) if t > 0.0 else "No limit"
				(_setting_rows[key] as Control).visible = _mode != GameConfig.Mode.BOMB
			"score_limit":
				label.text = "Rounds to win" if _mode == GameConfig.Mode.BOMB else "Score Limit"
				value.text = str(_score_limit())
			"bots":
				label.text = "Bots"
				var n := int(_opts.get("bots", 0))
				value.text = "Off" if n == 0 else str(n)
			"bot_skill":
				label.text = "Bot Skill"
				value.text = BotManager.DIFFICULTY_NAMES[int(_opts.get("bot_skill", 1))]
				(_setting_rows[key] as Control).visible = int(_opts.get("bots", 0)) > 0
			"friendly_fire":
				label.text = "Friendly Fire"
				value.text = "On" if bool(_opts.get("friendly_fire", false)) else "Off"
				(_setting_rows[key] as Control).visible = _mode != GameConfig.Mode.FFA
			"max_players":
				label.text = "Max Players"
				value.text = str(int(_opts.get("max_players", 8)))
	_refresh_start()


func _refresh_start() -> void:
	var host := multiplayer.is_server()
	_start_button.disabled = false
	match _play:
		"quick":
			_start_button.text = "JOIN"
			_start_hint.text = ""
		"custom":
			if not NetworkManager.in_room:
				_start_button.text = "CREATE ROOM"
				_start_hint.text = "Open a room with these settings; friends join with INVITE's address."
			elif host:
				_start_button.text = "START MATCH"
				var waiting := 0
				for id: int in NetworkManager.roster:
					if not NetworkManager.roster[id].get("ready", false):
						waiting += 1
				_start_hint.text = "Everyone is ready." if waiting == 0 else "%d not ready yet — you can start anyway." % waiting
			else:
				_start_button.text = "WAITING FOR HOST"
				_start_button.disabled = true
				_start_hint.text = "The host picks the map and starts the match."
		"training":
			_start_button.text = "START TRAINING"
			_start_hint.text = GameConfig.map_name(_resolved_map_label())
		"bot":
			_start_button.text = "START MATCH"
			var n := maxi(int(_opts.get("bots", 0)), 1)
			_start_hint.text = "%s on %s vs %d bot%s" % [GameConfig.MODE_NAMES[_mode],
				GameConfig.map_name(_resolved_map_label()), n, "" if n == 1 else "s"]


func _resolved_map_label() -> String:
	return _map if _map != "random" else GameConfig.MAPS[0].path


func _on_start() -> void:
	_store_name()
	match _play:
		"quick":
			_on_join()
		"custom":
			if not NetworkManager.in_room:
				_on_create_room()
			elif multiplayer.is_server():
				NetworkManager.start_room_match()
		"training":
			NetworkManager.start_offline(_resolved_map(), 0)
		"bot":
			var n := maxi(int(_opts.get("bots", 0)), 1)
			NetworkManager.start_offline(_resolved_map(), n, _mode, _score_limit(),
				float(_opts.get("time_limit", 600.0)), bool(_opts.get("friendly_fire", false)))


func _on_create_room() -> void:
	SettingsManager.save()
	if NetworkManager.host_room(SettingsManager.host_port, _room_settings()) != OK:
		_set_status(NetworkManager.last_error)
		return
	_set_status("")
	_chat_line("", "Room open — press INVITE to copy its address for your friends.")


func _on_host_now() -> void:
	_store_name()
	var r := _room_settings()
	NetworkManager.start_bots = r.bots
	Match.bots.difficulty = r.bot_skill
	Match.configure(_mode as GameConfig.Mode, r.score_limit, r.time_limit if _mode != GameConfig.Mode.BOMB else 0.0)
	if NetworkManager.host(SettingsManager.host_port, NetworkManager.DEFAULT_MAX_PLAYERS, false, r.map, -1) != OK:
		_set_status(NetworkManager.last_error)
		return
	Match.friendly_fire = r.friendly_fire


func _on_join() -> void:
	_store_name()
	var text := _address_edit.text.strip_edges() if _address_edit else ""
	if text.is_empty():
		text = "127.0.0.1"
	var address := text
	var port := NetworkManager.DEFAULT_PORT
	if text.count(":") == 1:
		address = text.get_slice(":", 0)
		port = text.get_slice(":", 1).to_int()
	SettingsManager.last_join_address = text
	SettingsManager.save()
	if NetworkManager.join(address, port) == OK:
		_set_status("Connecting to %s:%d…" % [address, port])
		_start_button.disabled = true
	else:
		_set_status(NetworkManager.last_error)


func _on_invite() -> void:
	var addr := room_address()
	DisplayServer.clipboard_set(addr)
	_chat_line("", "Room address copied: %s — friends paste it in Custom Match → Join a room." % addr)


## "LAN-IP:port" of this room (for friends on your network; over the
## internet use your public IP and forward the port).
static func room_address() -> String:
	var ip := "127.0.0.1"
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.count(".") == 3):
			ip = a
			break
	return "%s:%d" % [ip, SettingsManager.host_port]


func _send_chat() -> void:
	var text := _chat_edit.text.strip_edges()
	if text.is_empty():
		return
	_chat_edit.clear()
	if NetworkManager.in_room:
		NetworkManager.send_chat(text)
	else:
		_chat_line("", "Chat works in a Custom match room.")


func _on_chat(from_name: String, text: String) -> void:
	_chat_line(from_name, text)


func _chat_line(from_name: String, text: String) -> void:
	if from_name.is_empty():
		_chat_log.append_text("[color=#9aa]%s[/color]\n" % text.replace("[", "[lb]"))
	else:
		_chat_log.append_text("[color=#%s][%s][/color] %s\n" % [Color(0.45, 0.65, 1.0).to_html(false),
			from_name.replace("[", "[lb]"), text.replace("[", "[lb]")])


func _on_room_changed() -> void:
	if NetworkManager.in_room and _play != "custom":
		_play = "custom"
		for k: String in _play_buttons:
			(_play_buttons[k] as Button).set_pressed_no_signal(k == "custom")
		_set_status("")
		_rebuild_right()
	else:
		_refresh_setup()
	_refresh_room_ui()
	_refresh_stage()


func _on_roster_changed() -> void:
	_refresh_room_ui()
	_refresh_stage()
	_refresh_start()


func _refresh_room_ui() -> void:
	var in_room := NetworkManager.in_room and _tab == "LOBBY"
	_room_bar.visible = in_room
	_room_buttons.visible = in_room
	_chat_title.text = "ROOM CHAT" if NetworkManager.in_room else "MESSAGES"
	_chat_edit.editable = NetworkManager.in_room
	if not NetworkManager.in_room:
		return
	var host := multiplayer.is_server()
	_ready_button.visible = not host
	var n := NetworkManager.roster.size()
	_room_label.text = "ROOM  %s   ·   %d / %d players   ·   %s" % [room_address() if host else "joined",
		n, int(NetworkManager.room.get("max_players", 8)), "you host" if host else "host: " + NetworkManager.get_player_name(1)]
	if host:
		(find_child("InviteButton", true, false) as Button).visible = true


func _on_connection_failed(reason: String) -> void:
	if is_inside_tree():
		_set_status(reason)
		_start_button.disabled = false


func _set_status(text: String) -> void:
	var status := get_node("%StatusLabel") as Label
	status.text = text
	status.visible = not text.is_empty()


func _store_name() -> void:
	var n := _name_edit.text.strip_edges() if _name_edit else SettingsManager.player_name
	SettingsManager.player_name = n if not n.is_empty() else "Player"
	NetworkManager.local_name = SettingsManager.player_name
	SettingsManager.save()
	if _player_name_label:
		_player_name_label.text = SettingsManager.player_name


## Renders the map previews into the cards one by one (cached after once).
func _render_map_previews() -> void:
	_render_generation += 1
	var gen := _render_generation
	for m: Dictionary in GameConfig.MAPS:
		var tex := await MapPreview.render(self, m.path)
		if gen != _render_generation or not is_inside_tree():
			return
		if tex and _map_cards.has(m.path):
			((_map_cards[m.path] as Button).get_node("Picture") as TextureRect).texture = tex


# =============================================================================
# Small builders
# =============================================================================

static func _box(bg: Color, border: Color, border_width: int, radius: int, margin_v: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


static func _underline() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = ACCENT
	sb.border_width_bottom = 3
	return sb


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 17)
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	l.add_theme_font_size_override(&"font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _arrow(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(30, 28)
	return b


func _secondary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 44)
	b.add_theme_font_size_override(&"font_size", 16)
	b.add_theme_stylebox_override(&"normal", _box(PANEL, Color(1, 1, 1, 0.18), 1, 3))
	b.add_theme_stylebox_override(&"hover", _box(Color(0.12, 0.13, 0.16, 0.95), ACCENT, 1, 3))
	b.add_theme_stylebox_override(&"pressed", _box(Color(0.12, 0.12, 0.09, 0.95), ACCENT, 2, 3))
	return b


func _address_field() -> LineEdit:
	var e := LineEdit.new()
	e.name = "AddressEdit"
	e.placeholder_text = "IP address[:port]"
	e.text = SettingsManager.last_join_address
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 38)
	e.text_submitted.connect(func(_t: String) -> void: _on_join())
	return e


## Result of the full hardware test: summary, recommended preset, send/copy.
func _show_hardware_report(path: String) -> void:
	var report: Dictionary = HardwareTest._read_json(path)
	if report.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Hardware test results"
	dialog.ok_button_text = "Close"
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(760, 420)
	text.fit_content = false
	text.selection_enabled = true
	text.bbcode_enabled = true
	text.text = HardwareTest.bbcode(report)
	dialog.add_child(text)
	var recommended: String = report.get("recommended", "")
	if recommended != "":
		dialog.add_button("Use %s" % recommended, false, "use")
	dialog.add_button("Copy report", false, "copy")
	dialog.add_button("Send to the developers", false, "send")
	dialog.add_button("Open folder", false, "folder")
	dialog.custom_action.connect(_on_report_action.bind(report, dialog))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	%StatusLabel.text = "Hardware test finished — recommended preset: %s." % (recommended if recommended != "" else "Low + dynamic resolution")


func _on_report_action(action: StringName, report: Dictionary, dialog: AcceptDialog) -> void:
	var recommended: String = report.get("recommended", "")
	match String(action):
		"use":
			SettingsManager.set_graphics_quality(HardwareTest.PRESET_NAMES.find(recommended) as GraphicsPreset.Quality)
			%StatusLabel.text = "%s preset applied." % recommended
			dialog.hide()
		"copy":
			DisplayServer.clipboard_set(report.markdown)
			%StatusLabel.text = "Hardware report copied to the clipboard."
		"send":
			DisplayServer.clipboard_set(report.markdown)
			OS.shell_open(HardwareTest.issue_url(report))
			%StatusLabel.text = "Opened GitHub (the report is also on your clipboard)."
		"folder":
			OS.shell_open(ProjectSettings.globalize_path(HardwareTest.DIR))
