class_name CharacterScreen
extends Control
## Character screen (main menu → Character ▸): a turning 3D preview of your
## soldier and a row per option — body, face, eyes, mouth, ears, voice,
## outfit and each kit piece (◀ / ▶ or click the name to step through).
## Picking an outfit dresses the whole kit; pieces can then be changed one
## by one. Random rolls a look, Done saves it (SettingsManager.character) —
## everyone sees it in game, and you hear the voice when you are hit.

signal closed

const SECTIONS := [
	["Body and face", ["body", "face", "eyes", "mouth", "ears", "voice"]],
	["Clothing kit", ["outfit", "headwear", "torso", "backpack", "gloves", "pants", "boots"]],
]

var look: Dictionary = CharacterLook.default_look()
var _values: Dictionary = {} # key -> Button showing the choice
var _model: PlayerModel
var _pivot: Node3D
var _camera: Camera3D
var _close_up := false
var _drag := false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 20
	root.offset_bottom = -20
	root.add_theme_constant_override(&"separation", 24)
	add_child(root)

	# --- Preview ------------------------------------------------------------------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	root.add_child(left)
	var title := Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override(&"font_size", 30)
	left.add_child(title)
	var view := SubViewportContainer.new()
	view.name = "Preview"
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.gui_input.connect(_on_preview_input)
	left.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	view.add_child(vp)
	_build_stage(vp)
	var hint := Label.new()
	hint.text = "Drag to turn · Face close-up to look closer"
	hint.modulate = Color(1, 1, 1, 0.6)
	left.add_child(hint)
	var view_row := HBoxContainer.new()
	left.add_child(view_row)
	var zoom := Button.new()
	zoom.name = "ZoomButton"
	zoom.text = "Face close-up"
	zoom.toggle_mode = true
	zoom.toggled.connect(func(on: bool) -> void: _close_up = on)
	view_row.add_child(zoom)
	var voice := Button.new()
	voice.name = "VoiceButton"
	voice.text = "▶ Hear voice"
	voice.pressed.connect(_play_voice)
	view_row.add_child(voice)

	# --- Options --------------------------------------------------------------------
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list)
	for section: Array in SECTIONS:
		var head := Label.new()
		head.text = section[0]
		head.add_theme_font_size_override(&"font_size", 20)
		head.add_theme_color_override(&"font_color", Color(0.95, 0.75, 0.3))
		list.add_child(head)
		for key: String in section[1]:
			list.add_child(_option_row(key))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 10)
	right.add_child(buttons)
	for spec: Array in [["RandomButton", "Random", _randomize], ["ResetButton", "Reset", _reset],
			["CancelButton", "Cancel", _cancel], ["DoneButton", "Done", _done]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(spec[2])
		buttons.add_child(b)


func _option_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	var label := Label.new()
	label.text = CharacterLook.LABELS[key]
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(40, 34)
	prev.pressed.connect(step.bind(key, -1))
	row.add_child(prev)
	var value := Button.new()
	value.name = "Value"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.custom_minimum_size = Vector2(0, 34)
	value.pressed.connect(step.bind(key, 1))
	row.add_child(value)
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(40, 34)
	next.pressed.connect(step.bind(key, 1))
	row.add_child(next)
	_values[key] = value
	return row


## The turntable: the model, lights and a camera in the preview's own world.
func _build_stage(vp: SubViewport) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.64)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-30, 35, 0)
	key_light.light_energy = 1.3
	vp.add_child(key_light)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	vp.add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.04
	floor_mesh.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	floor_mesh.material_override = mat
	floor_mesh.position.y = -0.02
	vp.add_child(floor_mesh)
	_pivot = Node3D.new()
	_pivot.rotation.y = PI # facing the camera
	vp.add_child(_pivot)
	_model = PlayerModel.new()
	_model.name = "Model"
	_pivot.add_child(_model)
	_model.showcase()
	_model.set_team_color(Color(0.55, 0.6, 0.66))
	_camera = Camera3D.new()
	_camera.fov = 32.0
	vp.add_child(_camera)
	_camera.current = true
	_place_camera(1.0)


func _process(delta: float) -> void:
	if not visible:
		return
	if _close_up and not _drag:
		# Face the camera for the close-up.
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, PI, clampf(delta * 5.0, 0.0, 1.0))
	elif not _drag:
		_pivot.rotation.y += delta * 0.4
	_place_camera(delta * 6.0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


func _place_camera(k: float) -> void:
	var target := Vector3(0, 1.6, 0) if _close_up else Vector3(0, 0.92, 0)
	var pos := Vector3(0, 1.64, 1.3) if _close_up else Vector3(0, 1.05, 3.3)
	_camera.position = _camera.position.lerp(pos, clampf(k, 0.0, 1.0))
	_camera.look_at(target)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _drag:
		_pivot.rotation.y += (event as InputEventMouseMotion).relative.x * 0.01


func open() -> void:
	look = CharacterLook.sanitize(SettingsManager.character)
	visible = true
	_refresh()
	(find_child("DoneButton", true, false) as Button).grab_focus()


## Next (+1) / previous (-1) choice for `key`.
func step(key: String, dir: int) -> void:
	var n := CharacterLook.count(key, look)
	var i := posmod(int(look[key]) + dir, n)
	if key == "outfit":
		look = CharacterLook.with_outfit(look, i)
	else:
		look[key] = i
	look = CharacterLook.sanitize(look) # a new body may have fewer faces
	_refresh()
	if key == "voice":
		_play_voice()


func _refresh() -> void:
	for key: String in _values:
		(_values[key] as Button).text = CharacterLook.option_name(key, int(look[key]), look)
	_model.set_look(look)


func _play_voice() -> void:
	var sound := &"grunt_rough" if CharacterLook.voice_rough(look) else &"grunt"
	Audio.play_local(sound, -4.0, CharacterLook.voice_pitch(look))


func _randomize() -> void:
	look = CharacterLook.random(randi())
	_refresh()


func _reset() -> void:
	look = CharacterLook.default_look()
	_refresh()


func _done() -> void:
	SettingsManager.character = CharacterLook.sanitize(look)
	SettingsManager.save()
	visible = false
	closed.emit()


func _cancel() -> void:
	visible = false
	closed.emit()
