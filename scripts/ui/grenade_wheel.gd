class_name GrenadeWheel
extends Control
## The grenade wheel (hold 4): a ring of four segments round the crosshair —
## HE at the top, then flash, smoke and Molotov clockwise (Throwables.ORDER)
## — with how many of each you carry. The one pointed at lights up; empty
## ones are dimmed. The choosing itself happens in Throwables.

const RADIUS := 150.0
const INNER := 62.0

var throwables: Throwables


func _ready() -> void:
	name = "GrenadeWheel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_delta: float) -> void:
	var show: bool = throwables != null and is_instance_valid(throwables) and throwables.wheel_visible()
	if show != visible:
		visible = show
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var n: int = Throwables.ORDER.size()
	var step := TAU / n
	var font := get_theme_default_font()
	draw_circle(c, RADIUS + 6.0, Color(0, 0, 0, 0.35))
	for i in n:
		var kind: int = Throwables.ORDER[i]
		var count: int = throwables.counts.get(kind, 0)
		var chosen: bool = throwables.wheel_choice == kind
		# Segment i is centred straight up for i = 0, clockwise after that.
		var mid := -PI / 2 + i * step
		var pts := PackedVector2Array()
		var segs := 16
		for k in segs + 1:
			var a := mid - step / 2 + 0.03 + (step - 0.06) * k / segs
			pts.append(c + Vector2(cos(a), sin(a)) * RADIUS)
		for k in range(segs, -1, -1):
			var a := mid - step / 2 + 0.03 + (step - 0.06) * k / segs
			pts.append(c + Vector2(cos(a), sin(a)) * INNER)
		var fill := Color(1, 0.85, 0.4, 0.55) if chosen and count > 0 \
			else Color(0.08, 0.09, 0.1, 0.75 if count > 0 else 0.45)
		draw_colored_polygon(pts, fill)
		var label_at := c + Vector2(cos(mid), sin(mid)) * (INNER + RADIUS) * 0.5
		var text := "%s\n×%d" % [Throwables.SHORT_NAMES[kind], count]
		var col := Color.WHITE if count > 0 else Color(1, 1, 1, 0.3)
		if chosen and count > 0:
			col = Color(0.1, 0.08, 0.02)
		var w := 110.0
		draw_multiline_string(font, label_at - Vector2(w * 0.5, 10), text, HORIZONTAL_ALIGNMENT_CENTER, w, 18, -1, col)
	# Where the mouse points.
	if throwables.wheel_choice >= 0:
		var i: int = Throwables.ORDER.find(throwables.wheel_choice)
		var a := -PI / 2 + i * step
		draw_line(c, c + Vector2(cos(a), sin(a)) * (INNER - 8.0), Color(1, 0.9, 0.55, 0.9), 3.0)
