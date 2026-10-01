class_name Crosshair
extends Control
## Dynamic crosshair whose gap follows the weapon's real spread cone,
## plus a hit marker. Drawn with _draw() — no textures needed.

@export var line_length: float = 8.0
@export var thickness: float = 2.0
@export var outline_color: Color = Color(0, 0, 0, 0.6)
@export var hit_color: Color = Color(1, 1, 1, 1)
@export var kill_color: Color = Color(1, 0.25, 0.2, 1)

## Gap from centre in pixels (set by the HUD from the weapon spread).
var gap: float = 6.0
## 0..1 fade for aiming down sights (crosshair hides, dot stays).
var ads: float = 0.0
## 0..1: aiming through a red-dot sight. Its glowing dot is drawn here, in
## the middle of the sight's window (the gun is held so they line up).
var red_dot: float = 0.0

var _hit_timer: float = 0.0
var _hit_is_kill: bool = false


func show_hit(is_kill: bool) -> void:
	_hit_timer = 0.25 if is_kill else 0.15
	_hit_is_kill = is_kill


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	# Colour, size and centre dot come from Settings → Gameplay.
	var color := SettingsManager.crosshair_color()
	var scale_f := SettingsManager.crosshair_size
	var len_px := line_length * scale_f
	var thick := maxf(thickness * scale_f, 1.0)
	var gap_px := gap * lerpf(1.0, scale_f, 0.3)
	var c := size * 0.5
	var alpha := 1.0 - ads
	if alpha > 0.01:
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var a := c + dir * gap_px
			var b := c + dir * (gap_px + len_px)
			draw_line(a, b, Color(outline_color, outline_color.a * alpha), thick + 2.0)
			draw_line(a, b, Color(color, color.a * alpha), thick)
	if red_dot > 0.01:
		draw_circle(c, 5.0, Color(1.0, 0.1, 0.05, 0.18 * red_dot))
		draw_circle(c, 3.0, Color(1.0, 0.15, 0.08, 0.45 * red_dot))
		draw_circle(c, 1.7, Color(1.0, 0.35, 0.25, red_dot))
	elif SettingsManager.crosshair_dot:
		draw_circle(c, 1.5 * scale_f, color)

	if _hit_timer > 0.0:
		var col := kill_color if _hit_is_kill else hit_color
		var s := 10.0
		var inner := 4.0
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d.normalized() * inner, c + d.normalized() * s, col, 2.0)
