extends Control
## Main menu: offline practice, host / join multiplayer, and the settings screen.

@warning_ignore_start("static_called_on_instance") # static helpers on autoloads (NetworkManager, SettingsManager…)
@onready var _main: VBoxContainer = %Main
@onready var _settings: SettingsMenu = %SettingsMenu


func _ready() -> void:
	%Version.text = NetworkManager.version_string()
	Audio.play_music(&"menu")
	%SettingsButton.pressed.connect(_show_settings)
	_settings.closed.connect(_on_settings_closed)
	%QuitButton.pressed.connect(get_tree().quit)
	%BugButton.pressed.connect(func() -> void:
		BugReport.open()
		%StatusLabel.text = "Bug report opened in your browser (system details copied to the clipboard).")
	%PlayButton.pressed.connect(_on_play_pressed)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%AddressEdit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	%NameEdit.text = SettingsManager.player_name
	%AddressEdit.text = SettingsManager.last_join_address
	%PortSpin.value = SettingsManager.host_port
	# A map that was removed or renamed since the settings were saved.
	var saved := GameConfig.map_index(SettingsManager.selected_map)
	SettingsManager.selected_map = GameConfig.MAPS[maxi(saved, 0)].path
	_update_map_button()
	%MapButton.pressed.connect(func() -> void:
		_main.visible = false
		%MapSelect.open(SettingsManager.selected_map, %ModeOption.get_selected_id()))
	%MapSelect.chosen.connect(func(path: String) -> void:
		SettingsManager.selected_map = path
		SettingsManager.save()
		_update_map_button()
		_main.visible = true
		%MapButton.grab_focus())
	%MapSelect.closed.connect(func() -> void:
		_main.visible = true
		%MapButton.grab_focus())
	for mode_id: int in [GameConfig.Mode.FFA, GameConfig.Mode.TDM, GameConfig.Mode.BOMB]:
		%ModeOption.add_item(GameConfig.MODE_NAMES[mode_id], mode_id)
	%ModeOption.select(maxi(%ModeOption.get_item_index(SettingsManager.host_mode), 0))
	%StatusLabel.text = NetworkManager.last_error
	NetworkManager.last_error = ""
	if not BenchmarkRunner.last_results.is_empty():
		%StatusLabel.text = BenchmarkRunner.summary_text(BenchmarkRunner.last_results)
		BenchmarkRunner.last_results = {}
	var report_path := HardwareTest.take_pending_report()
	if report_path != "":
		_show_hardware_report.call_deferred(report_path)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_bots_row()
	_build_character_button()
	%PlayButton.grab_focus()


## "Character: <face> · <outfit> ▸" under the name: opens the Character screen.
var _character_button: Button
var _character_screen: CharacterScreen


func _build_character_button() -> void:
	_character_button = Button.new()
	_character_button.name = "CharacterButton"
	_character_button.tooltip_text = "Body, face, voice, outfit and kit — what other players see"
	_main.add_child(_character_button)
	_main.move_child(_character_button, %MapButton.get_index())
	_character_screen = CharacterScreen.new()
	_character_screen.name = "CharacterScreen"
	add_child(_character_screen)
	_character_button.pressed.connect(func() -> void:
		_main.visible = false
		_character_screen.open())
	_character_screen.closed.connect(func() -> void:
		_main.visible = true
		_update_character_button()
		_character_button.grab_focus())
	_update_character_button()


func _update_character_button() -> void:
	var look: Dictionary = CharacterLook.sanitize(SettingsManager.character)
	_character_button.text = "Character: %s · %s ▸" % [CharacterLook.face_of(look).name,
		CharacterLook.OUTFITS[int(look.outfit)].name]


## "Bots [n] [Easy / Normal / Hard]" under the map and mode: training bots
## for offline play (against them, in the chosen mode) and when hosting.
var _bot_spin: SpinBox
var _bot_skill: OptionButton


func _build_bots_row() -> void:
	var row := HBoxContainer.new()
	row.name = "BotsRow"
	var label := Label.new()
	label.text = "Bots"
	row.add_child(label)
	_bot_spin = SpinBox.new()
	_bot_spin.name = "BotSpin"
	_bot_spin.min_value = 0
	_bot_spin.max_value = BotManager.MAX_BOTS
	_bot_spin.value = SettingsManager.bot_count
	_bot_spin.tooltip_text = "Training bots (offline: play the chosen mode against them; hosting: they fill the teams)"
	_bot_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bot_spin)
	_bot_skill = OptionButton.new()
	_bot_skill.name = "BotSkill"
	for i in BotManager.DIFFICULTY_NAMES.size():
		_bot_skill.add_item(BotManager.DIFFICULTY_NAMES[i], i)
	_bot_skill.select(clampi(SettingsManager.bot_difficulty, 0, 2))
	_bot_skill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bot_skill)
	_main.add_child(row)
	_main.move_child(row, %PlayButton.get_index())
	_bot_spin.value_changed.connect(func(_v: float) -> void: _update_play_text())
	%ModeOption.item_selected.connect(func(_i: int) -> void: _update_play_text())
	_update_play_text()


func _update_play_text() -> void:
	var n := int(_bot_spin.value)
	%PlayButton.text = "Play Offline (Practice)" if n == 0 \
		else "Play Offline — %s vs %d bot%s" % [%ModeOption.get_item_text(%ModeOption.selected), n, "" if n == 1 else "s"]


func _store_bots() -> void:
	SettingsManager.bot_count = int(_bot_spin.value)
	SettingsManager.bot_difficulty = _bot_skill.get_selected_id()
	Match.bots.difficulty = SettingsManager.bot_difficulty
	SettingsManager.save()


func _show_settings() -> void:
	_main.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	_main.visible = true
	%NameEdit.text = SettingsManager.player_name
	%SettingsButton.grab_focus()


func _on_play_pressed() -> void:
	_store_name()
	_store_bots()
	SettingsManager.host_mode = %ModeOption.get_selected_id()
	SettingsManager.save()
	NetworkManager.start_offline(_selected_map(), SettingsManager.bot_count, SettingsManager.host_mode)


func _on_host_pressed() -> void:
	_store_name()
	_store_bots()
	NetworkManager.start_bots = SettingsManager.bot_count
	SettingsManager.host_port = int(%PortSpin.value)
	SettingsManager.host_mode = %ModeOption.get_selected_id()
	SettingsManager.save()
	if NetworkManager.host(SettingsManager.host_port, NetworkManager.DEFAULT_MAX_PLAYERS, false,
			_selected_map(), SettingsManager.host_mode) != OK:
		%StatusLabel.text = NetworkManager.last_error


func _on_join_pressed() -> void:
	_store_name()
	var text: String = %AddressEdit.text.strip_edges()
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
		%StatusLabel.text = "Connecting to %s:%d…" % [address, port]
		_set_buttons_disabled(true)
	else:
		%StatusLabel.text = NetworkManager.last_error


func _on_connection_failed(reason: String) -> void:
	if is_inside_tree():
		%StatusLabel.text = reason
		_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for b: String in ["PlayButton", "HostButton", "JoinButton"]:
		(get_node("%" + b) as Button).disabled = disabled


func _selected_map() -> String:
	return SettingsManager.selected_map


func _update_map_button() -> void:
	%MapButton.text = "Map: %s ▸" % GameConfig.map_name(SettingsManager.selected_map)


func _store_name() -> void:
	var n: String = %NameEdit.text.strip_edges()
	SettingsManager.player_name = n if not n.is_empty() else "Player"
	NetworkManager.local_name = SettingsManager.player_name
	SettingsManager.save()


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
