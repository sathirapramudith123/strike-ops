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
	%ResumeButton.grab_focus()


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
