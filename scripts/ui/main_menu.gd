extends Control
## Main menu: offline practice, host / join multiplayer, and the settings screen.

@onready var _main: VBoxContainer = %Main
@onready var _settings: SettingsMenu = %SettingsMenu


func _ready() -> void:
	%Version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	%SettingsButton.pressed.connect(_show_settings)
	_settings.closed.connect(_on_settings_closed)
	%QuitButton.pressed.connect(get_tree().quit)
	%PlayButton.pressed.connect(_on_play_pressed)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%AddressEdit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	%NameEdit.text = SettingsManager.player_name
	%AddressEdit.text = SettingsManager.last_join_address
	%PortSpin.value = SettingsManager.host_port
	for m: Dictionary in GameConfig.MAPS:
		%MapOption.add_item(m.name)
	%MapOption.select(maxi(GameConfig.map_index(SettingsManager.selected_map), 0))
	for mode_id: int in [GameConfig.Mode.FFA, GameConfig.Mode.TDM, GameConfig.Mode.BOMB]:
		%ModeOption.add_item(GameConfig.MODE_NAMES[mode_id], mode_id)
	%ModeOption.select(maxi(%ModeOption.get_item_index(SettingsManager.host_mode), 0))
	%StatusLabel.text = NetworkManager.last_error
	NetworkManager.last_error = ""
	if not BenchmarkRunner.last_results.is_empty():
		%StatusLabel.text = BenchmarkRunner.summary_text(BenchmarkRunner.last_results)
		BenchmarkRunner.last_results = {}
	NetworkManager.connection_failed.connect(_on_connection_failed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%PlayButton.grab_focus()


func _show_settings() -> void:
	_main.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	_main.visible = true
	%NameEdit.text = SettingsManager.player_name
	%SettingsButton.grab_focus()


func _on_play_pressed() -> void:
	_store_name()
	NetworkManager.start_offline(_selected_map())


func _on_host_pressed() -> void:
	_store_name()
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
	var path: String = GameConfig.MAPS[maxi(%MapOption.selected, 0)].path
	SettingsManager.selected_map = path
	SettingsManager.save()
	return path


func _store_name() -> void:
	var n: String = %NameEdit.text.strip_edges()
	SettingsManager.player_name = n if not n.is_empty() else "Player"
	NetworkManager.local_name = SettingsManager.player_name
	SettingsManager.save()
