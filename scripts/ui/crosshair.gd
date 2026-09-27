class_name Crosshair
extends Control
## Dynamic crosshair whose gap follows the weapon's real spread cone,
## plus a hit marker. Drawn with _draw() — no textures needed.

@export var line_length: float = 8.0
@export var thickness: float = 2.0
@export var color: Color = Color(1, 1, 1, 0.9)
@export var outline_color: Color = Color(0, 0, 0, 0.6)
@export var hit_color: Color = Color(1, 1, 1, 1)
@export var kill_color: Color = Color(1, 0.25, 0.2, 1)

## Gap from centre in pixels (set by the HUD from the weapon spread).
var gap: float = 6.0
## 0..1 fade for aiming down sights (crosshair hides, dot stays).
var ads: float = 0.0

var _hit_timer: float = 0.0
var _hit_is_kill: bool = false


func show_hit(is_kill: bool) -> void:
	_hit_timer = 0.25 if is_kill else 0.15
	_hit_is_kill = is_kill


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var alpha := 1.0 - ads
	if alpha > 0.01:
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var a := c + dir * gap
			var b := c + dir * (gap + line_length)
			draw_line(a, b, Color(outline_color, outline_color.a * alpha), thickness + 2.0)
			draw_line(a, b, Color(color, color.a * alpha), thickness)
	draw_circle(c, 1.5, color)

	if _hit_timer > 0.0:
		var col := kill_color if _hit_is_kill else hit_color
		var s := 10.0
		var inner := 4.0
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d.normalized() * inner, c + d.normalized() * s, col, 2.0)
