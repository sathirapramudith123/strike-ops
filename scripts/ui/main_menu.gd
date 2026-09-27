extends Control
## Main menu with a basic settings panel (graphics preset, display, audio, voice).

const TEST_MAP := "res://scenes/levels/test_map.tscn"

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
	_restart_button.pressed.connect(SettingsManager.restart_game)

	_quality.item_selected.connect(_on_quality_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_vsync.toggled.connect(_on_vsync_toggled)
	_master.value_changed.connect(_on_master_changed)
	_voice.value_changed.connect(_on_voice_changed)
	_voice_mode.item_selected.connect(_on_voice_mode_selected)
	SettingsManager.restart_required.connect(_on_restart_required)

	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%PlayButton.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(TEST_MAP)


func _refresh() -> void:
	var idx := _quality.get_item_index(SettingsManager.graphics.quality)
	_quality.select(idx) # -1 (Custom) shows no selection
	_fullscreen.set_pressed_no_signal(
		SettingsManager.window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_vsync.set_pressed_no_signal(SettingsManager.vsync)
	_master.set_value_no_signal(SettingsManager.bus_volumes[&"Master"])
	_voice.set_value_no_signal(SettingsManager.bus_volumes[&"Voice"])
	_voice_mode.select(_voice_mode.get_item_index(SettingsManager.voice_mode))


func _show_settings(open: bool) -> void:
	_main.visible = not open
	_settings.visible = open
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
