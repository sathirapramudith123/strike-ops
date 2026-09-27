extends Control
## Main menu: offline play, host / join multiplayer, and a basic settings panel.

@onready var _main: VBoxContainer = %Main
@onready var _settings: VBoxContainer = %Settings
@onready var _quality: OptionButton = %QualityOption
@onready var _fullscreen: CheckButton = %FullscreenCheck
@onready var _vsync: CheckButton = %VsyncCheck
@onready var _master: HSlider = %MasterSlider
@onready var _voice: HSlider = %VoiceSlider
@onready var _voice_mode: OptionButton = %VoiceModeOption
@onready var _restart_notice: Label = %RestartNotice
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	%Version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")

	for q: GraphicsPreset.Quality in SettingsManager.PRESET_FILES:
		_quality.add_item(SettingsManager.load_preset(q).display_name, q)
	_voice_mode.add_item("Push-to-talk", SettingsManager.VoiceMode.PUSH_TO_TALK)
	_voice_mode.add_item("Voice activation", SettingsManager.VoiceMode.VOICE_ACTIVATION)

	%SettingsButton.pressed.connect(_show_settings.bind(true))
	%BackButton.pressed.connect(_show_settings.bind(false))
	%QuitButton.pressed.connect(get_tree().quit)
	%PlayButton.pressed.connect(_on_play_pressed)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%AddressEdit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	%NameEdit.text = SettingsManager.player_name
	%AddressEdit.text = SettingsManager.last_join_address
	%PortSpin.value = SettingsManager.host_port
	%StatusLabel.text = NetworkManager.last_error
	NetworkManager.last_error = ""
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_restart_button.pressed.connect(SettingsManager.restart_game)

	_quality.item_selected.connect(_on_quality_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_vsync.toggled.connect(_on_vsync_toggled)
	_master.value_changed.connect(_on_master_changed)
	_voice.value_changed.connect(_on_voice_changed)
	_voice_mode.item_selected.connect(_on_voice_mode_selected)
	SettingsManager.restart_required.connect(_on_restart_required)
	_setup_voice_settings()

	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%PlayButton.grab_focus()


func _on_play_pressed() -> void:
	_store_name()
	NetworkManager.start_offline()


func _on_host_pressed() -> void:
	_store_name()
	SettingsManager.host_port = int(%PortSpin.value)
	SettingsManager.save()
	if NetworkManager.host(SettingsManager.host_port) != OK:
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


func _store_name() -> void:
	var n: String = %NameEdit.text.strip_edges()
	SettingsManager.player_name = n if not n.is_empty() else "Player"
	NetworkManager.local_name = SettingsManager.player_name
	SettingsManager.save()


func _refresh() -> void:
	var idx := _quality.get_item_index(SettingsManager.graphics.quality)
	_quality.select(idx) # -1 (Custom) shows no selection
	_fullscreen.set_pressed_no_signal(
		SettingsManager.window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_vsync.set_pressed_no_signal(SettingsManager.vsync)
	_master.set_value_no_signal(SettingsManager.bus_volumes[&"Master"])
	_voice.set_value_no_signal(SettingsManager.bus_volumes[&"Voice"])
	_voice_mode.select(_voice_mode.get_item_index(SettingsManager.voice_mode))
	%VoiceEnabledCheck.set_pressed_no_signal(SettingsManager.voice_enabled)
	%MicVolumeSlider.set_value_no_signal(SettingsManager.mic_volume)
	%ThresholdSlider.set_value_no_signal(SettingsManager.voice_activation_threshold)
	%ProcessingCheck.set_pressed_no_signal(SettingsManager.voice_processing)
	%ProximityCheck.set_pressed_no_signal(SettingsManager.proximity_chat_enabled)


func _process(_delta: float) -> void:
	if _settings.visible:
		%MicLevelBar.value = VoiceChat.input_level


func _setup_voice_settings() -> void:
	var devices := AudioServer.get_input_device_list()
	for d in devices:
		%MicDeviceOption.add_item(d)
	var idx := devices.find(SettingsManager.voice_input_device)
	%MicDeviceOption.select(maxi(idx, 0))
	%MicDeviceOption.item_selected.connect(func(i: int) -> void:
		SettingsManager.voice_input_device = %MicDeviceOption.get_item_text(i)
		_apply_voice())
	%VoiceEnabledCheck.toggled.connect(func(on: bool) -> void:
		SettingsManager.voice_enabled = on
		_apply_voice())
	%MicVolumeSlider.value_changed.connect(func(v: float) -> void:
		SettingsManager.mic_volume = v
		_apply_voice())
	%ThresholdSlider.value_changed.connect(func(v: float) -> void:
		SettingsManager.voice_activation_threshold = v
		_apply_voice())
	%ProcessingCheck.toggled.connect(func(on: bool) -> void:
		SettingsManager.voice_processing = on
		_apply_voice())
	%ProximityCheck.toggled.connect(func(on: bool) -> void:
		SettingsManager.proximity_chat_enabled = on
		_apply_voice())
	%LoopbackCheck.toggled.connect(func(on: bool) -> void: VoiceChat.loopback = on)


func _apply_voice() -> void:
	SettingsManager.apply_voice()
	SettingsManager.save()


func _show_settings(open: bool) -> void:
	_main.visible = not open
	_settings.visible = open
	# Run the mic while the settings are open so the level meter works.
	VoiceChat.monitoring = open
	if not open:
		VoiceChat.loopback = false
		%LoopbackCheck.set_pressed_no_signal(false)
	if open:
		_refresh()
		_quality.grab_focus()
	else:
		%SettingsButton.grab_focus()


func _on_quality_selected(index: int) -> void:
	SettingsManager.set_graphics_quality(_quality.get_item_id(index) as GraphicsPreset.Quality)


func _on_fullscreen_toggled(on: bool) -> void:
	SettingsManager.window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN if on \
		else DisplayServer.WINDOW_MODE_WINDOWED
	SettingsManager.apply_display()
	SettingsManager.save()


func _on_vsync_toggled(on: bool) -> void:
	SettingsManager.vsync = on
	SettingsManager.apply_display()
	SettingsManager.save()


func _on_master_changed(value: float) -> void:
	SettingsManager.set_bus_volume(&"Master", value)


func _on_voice_changed(value: float) -> void:
	SettingsManager.set_bus_volume(&"Voice", value)


func _on_voice_mode_selected(index: int) -> void:
	SettingsManager.voice_mode = _voice_mode.get_item_id(index)
	SettingsManager.apply_voice()
	SettingsManager.save()


func _on_restart_required(reason: String) -> void:
	_restart_notice.text = "%s Restart required." % reason
	_restart_notice.visible = true
	_restart_button.visible = true
