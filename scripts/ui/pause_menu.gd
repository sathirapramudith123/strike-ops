class_name PauseMenu
extends CanvasLayer
## In-game menu (Esc). The game keeps running underneath — this is a
## multiplayer shooter — only the local player's input is disabled.

var player: PlayerController

@onready var _panel: Control = %Panel
@onready var _sensitivity: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _fov: HSlider = %FovSlider
@onready var _fov_value: Label = %FovValue
@onready var _quality: OptionButton = %QualityOption


func _ready() -> void:
	_panel.visible = false
	for q: GraphicsPreset.Quality in SettingsManager.PRESET_FILES:
		_quality.add_item(SettingsManager.load_preset(q).display_name, q)
	%MainMenuButton.text = "Disconnect" if NetworkManager.is_online() else "Main menu"
	%ResumeButton.pressed.connect(close)
	%MainMenuButton.pressed.connect(_go_to_main_menu)
	%QuitButton.pressed.connect(get_tree().quit)
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	_fov.value_changed.connect(_on_fov_changed)
	%MuteAllCheck.toggled.connect(func(on: bool) -> void: VoiceChat.mute_all = on)
	for id: String in GameConfig.PRIMARY_WEAPONS:
		%LoadoutOption.add_item(GameConfig.PRIMARY_NAMES[id])
	%LoadoutOption.item_selected.connect(func(i: int) -> void:
		Match.request_loadout(GameConfig.PRIMARY_WEAPONS[i]))
	%TeamButton.pressed.connect(func() -> void:
		Match.request_team_switch()
		close())
	_quality.item_selected.connect(func(i: int) -> void:
		SettingsManager.set_graphics_quality(_quality.get_item_id(i) as GraphicsPreset.Quality))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _panel.visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.input_enabled = false
	_sensitivity.set_value_no_signal(SettingsManager.mouse_sensitivity)
	_sensitivity_value.text = "%.2f" % SettingsManager.mouse_sensitivity
	_fov.set_value_no_signal(SettingsManager.field_of_view)
	_fov_value.text = str(int(SettingsManager.field_of_view))
	_quality.select(_quality.get_item_index(SettingsManager.graphics.quality))
	_build_mute_list()
	%LoadoutOption.select(maxi(GameConfig.PRIMARY_WEAPONS.find(SettingsManager.preferred_primary), 0))
	%TeamButton.visible = Match.is_team_mode()
	%ResumeButton.grab_focus()


## One "Mute <name>" checkbox per other player in the match.
func _build_mute_list() -> void:
	%MuteAllCheck.set_pressed_no_signal(VoiceChat.mute_all)
	var list: VBoxContainer = %MuteList
	for child in list.get_children():
		child.queue_free()
	var level := get_parent() as Level
	if level == null:
		return
	for p: PlayerController in level.get_players():
		if p.is_local:
			continue
		var cb := CheckBox.new()
		cb.text = "Mute %s" % p.player_name
		cb.button_pressed = VoiceChat.muted.has(p.peer_id)
		var id := p.peer_id
		cb.toggled.connect(func(on: bool) -> void: VoiceChat.set_muted(id, on))
		list.add_child(cb)
	%MuteAllCheck.visible = NetworkManager.is_online()
	$Panel/Center/Box/VoiceTitle.visible = NetworkManager.is_online()


func close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player:
		player.input_enabled = true
	SettingsManager.save()


func _on_sensitivity_changed(value: float) -> void:
	SettingsManager.mouse_sensitivity = value
	_sensitivity_value.text = "%.2f" % value


func _on_fov_changed(value: float) -> void:
	SettingsManager.field_of_view = value
	_fov_value.text = str(int(value))


func _go_to_main_menu() -> void:
	SettingsManager.save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave()
