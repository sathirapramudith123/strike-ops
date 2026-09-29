class_name LoadingScreen
extends CanvasLayer
## Loading screen shown while a map loads (NetworkManager._goto_map): the
## map's picture (MapPreview, when it was rendered in the lobby), its name,
## the mode and player count, a progress bar and four steps — Loading
## assets → Building geometry → Setting up spawns → Preparing match — and a
## tip. It lives on the scene tree root, so it survives the scene change,
## and fades out once your player is in the level.

const STEPS: PackedStringArray = ["Loading assets", "Building geometry", "Setting up spawns", "Preparing match"]
const TIPS: PackedStringArray = [
	"Tactical minds win battles.",
	"Crouch-walk to move almost silently.",
	"Hold 4 to pick a grenade from the wheel; the arc shows where it lands.",
	"Doors break where you shoot them — make your own angle.",
	"The shotgun loads shell by shell: fire any time to stop reloading.",
	"Teammates' names show through walls; enemies' only when you aim at them.",
	"In Bomb Defusal, buy armour before a rifle when money is short.",
	"Press I to inspect your weapon.",
]
const ACCENT := Color(0.98, 0.78, 0.18)
const TIMEOUT := 20.0

static var _current: LoadingScreen

var map_path: String = ""
var step: int = 0
var progress: float = 0.0
var _bar: ProgressBar
var _percent: Label
var _dots: Array[Label] = []
var _age: float = 0.0
var _closing := false


## Shows the screen for `path` (replacing one already open).
static func open(tree: SceneTree, path: String) -> LoadingScreen:
	if is_instance_valid(_current):
		_current.queue_free()
	var s := LoadingScreen.new()
	s.map_path = path
	tree.root.add_child(s)
	_current = s
	return s


static func current() -> LoadingScreen:
	return _current if is_instance_valid(_current) else null


func _ready() -> void:
	layer = 100
	var info := GameConfig.map_info(map_path)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var pic := TextureRect.new()
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = MapPreview.cached(map_path)
	pic.modulate = Color(0.55, 0.58, 0.66)
	root.add_child(pic)
	# Darker towards the bottom-left, where the text is.
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.85))
	grad.set_color(1, Color(0, 0, 0, 0.1))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0.8, 0.2)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(shade)

	var logo := LobbyLogo.make(30)
	logo.position = Vector2(40, 30)
	root.add_child(logo)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 60
	box.offset_top = -330
	box.offset_right = 760
	box.offset_bottom = -40
	box.add_theme_constant_override(&"separation", 10)
	root.add_child(box)
	var title := Label.new()
	title.text = String(info.get("name", "Map")).to_upper()
	title.add_theme_font_size_override(&"font_size", 64)
	title.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override(&"outline_size", 6)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "%s   ·   %s players" % [GameConfig.MODE_NAMES[Match.mode].to_upper(), info.get("players", "")]
	sub.add_theme_font_size_override(&"font_size", 20)
	sub.modulate = Color(0.85, 0.88, 0.95)
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	box.add_child(gap)
	var loading := Label.new()
	loading.text = "LOADING MAP…"
	loading.add_theme_font_size_override(&"font_size", 18)
	box.add_child(loading)
	var bar_row := HBoxContainer.new()
	box.add_child(bar_row)
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520, 14)
	_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override(&"fill", fill)
	_bar.add_theme_stylebox_override(&"background", back)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_bar)
	_percent = Label.new()
	_percent.custom_minimum_size = Vector2(70, 0)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(_percent)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override(&"separation", 34)
	box.add_child(steps)
	for s in STEPS:
		var l := Label.new()
		l.text = "○  " + s
		l.add_theme_font_size_override(&"font_size", 14)
		steps.add_child(l)
		_dots.append(l)
	var tip := Label.new()
	tip.text = "“%s”" % TIPS[randi() % TIPS.size()]
	tip.modulate = Color(1, 1, 1, 0.6)
	tip.add_theme_font_size_override(&"font_size", 15)
	box.add_child(tip)
	_refresh()


## Loading the map file: `p` 0..1 (the first 70 % of the bar).
func set_load_progress(p: float) -> void:
	progress = maxf(progress, clampf(p, 0.0, 1.0) * 0.7)
	_refresh()


func set_step(i: int) -> void:
	step = maxi(step, i)
	progress = maxf(progress, [0.0, 0.72, 0.85, 0.95, 1.0][clampi(step, 0, 4)])
	_refresh()


func _refresh() -> void:
	if _bar == null:
		return
	_bar.value = progress
	_percent.text = "%d%%" % roundi(progress * 100.0)
	for i in _dots.size():
		var done := i < step
		_dots[i].text = ("✔  " if done else ("●  " if i == step else "○  ")) + STEPS[i]
		_dots[i].modulate = ACCENT if done else (Color.WHITE if i == step else Color(1, 1, 1, 0.45))


func _process(delta: float) -> void:
	_age += delta
	if _closing:
		return
	var level := NetworkManager.current_level()
	if level:
		set_step(2) # the level is in: spawns next
		if level.player != null or NetworkManager.is_dedicated():
			set_step(4)
			finish()
	elif step >= 1 and get_tree().current_scene and not get_tree().current_scene is Level:
		finish() # back in a menu (left, or the load failed)
	if _age > TIMEOUT:
		finish()


## Fades out and frees itself.
func finish() -> void:
	if _closing:
		return
	_closing = true
	set_step(4)
	var root := get_child(0) as Control
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(root, "modulate:a", 0.0, 0.35)
	t.tween_callback(queue_free)
