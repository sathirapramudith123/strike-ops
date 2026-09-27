class_name MapSelect
extends Control
## Map selection screen: a card per map (bird's-eye preview + name) and a
## details panel (big preview, style, player count, description, modes).
## Opened from the main menu for offline play and hosting.

signal chosen(map_path: String)
signal closed

const CARD_SIZE := Vector2(210, 150)

var _selected: String = ""
var _mode: int = GameConfig.Mode.FFA
var _cards: Dictionary = {} # path -> Button
var _render_generation: int = 0

@onready var _grid: GridContainer = %MapGrid
@onready var _preview: TextureRect = %BigPreview
@onready var _name: Label = %MapName
@onready var _meta: Label = %MapMeta
@onready var _desc: Label = %MapDescription
@onready var _select_button: Button = %SelectButton


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void:
		hide()
		closed.emit())
	_select_button.pressed.connect(func() -> void:
		hide()
		chosen.emit(_selected))


## Shows the screen with `current` highlighted. `mode` disables maps that
## can't host it (e.g. no bomb sites for Bomb Defusal).
func open(current: String, mode: int) -> void:
	_mode = mode
	_build_cards()
	show()
	_select(current if GameConfig.map_index(current) >= 0 else GameConfig.MAPS[0].path)
	(_cards[_selected] as Button).grab_focus()
	_render_previews()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		hide()
		closed.emit()
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	for m: Dictionary in GameConfig.MAPS:
		var b := Button.new()
		b.custom_minimum_size = CARD_SIZE
		b.text = m.name
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.toggle_mode = true
		var playable: bool = _mode != GameConfig.Mode.BOMB or m.get("bomb", false)
		b.disabled = not playable
		b.tooltip_text = m.description if playable else "No bomb sites on this map"
		var path: String = m.path
		b.pressed.connect(_select.bind(path))
		b.focus_entered.connect(_select.bind(path))
		_grid.add_child(b)
		_cards[path] = b


func _select(path: String) -> void:
	_selected = path
	for p: String in _cards:
		(_cards[p] as Button).set_pressed_no_signal(p == path)
	var m := GameConfig.map_info(path)
	_name.text = m.name
	var modes := PackedStringArray(["Free-for-All", "Team Deathmatch"])
	if m.get("bomb", false):
		modes.append("Bomb Defusal")
	_meta.text = "%s  ·  %s players\n%s" % [m.style, m.players, ", ".join(modes)]
	_desc.text = m.description
	_preview.texture = (_cards[path] as Button).icon
	_select_button.text = "Select %s" % m.name


## Renders the previews one after another (each takes a few frames).
func _render_previews() -> void:
	_render_generation += 1
	var gen := _render_generation
	for m: Dictionary in GameConfig.MAPS:
		var tex := await MapPreview.render(self, m.path)
		if gen != _render_generation or not is_inside_tree():
			return # screen was reopened / closed meanwhile
		if tex and _cards.has(m.path):
			(_cards[m.path] as Button).icon = tex
			if m.path == _selected:
				_preview.texture = tex
