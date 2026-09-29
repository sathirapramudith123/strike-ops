class_name LobbyIcon
extends Control
## Simple line icons drawn in code for the lobby (no image files):
## "play" crossed rifles, "room" crossed rifles in a frame, "target",
## "bot" a skull, "tdm" a skull, "bomb", "ffa" a crosshair, "random"
## crossing arrows, "gear", "power", "copy", "person", "crown", "send".

@export var kind: String = "play"
@export var color: Color = Color(0.9, 0.92, 0.95)
@export var width: float = 2.5


static func make(icon_kind: String, icon_size: float = 36.0, icon_color: Color = Color(0.9, 0.92, 0.95)) -> LobbyIcon:
	var icon := LobbyIcon.new()
	icon.kind = icon_kind
	icon.color = icon_color
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := width * s / 36.0
	match kind:
		"play", "room":
			for sgn in [-1.0, 1.0]:
				var a: Vector2 = p.call(0.5 - 0.38 * sgn, 0.12)
				var b: Vector2 = p.call(0.5 + 0.38 * sgn, 0.88)
				draw_line(a, b, color, w * 1.4)
				draw_line(p.call(0.5 + 0.2 * sgn, 0.62), p.call(0.5 + 0.34 * sgn, 0.55), color, w)
			if kind == "room":
				draw_rect(Rect2(p.call(0.02, 0.02), Vector2(s, s) * 0.96), color, false, w * 0.6)
		"target":
			draw_arc(p.call(0.5, 0.5), s * 0.4, 0, TAU, 32, color, w)
			draw_arc(p.call(0.5, 0.5), s * 0.2, 0, TAU, 24, color, w)
			draw_line(p.call(0.2, 0.2), p.call(0.8, 0.8), color, w)
			draw_line(p.call(0.8, 0.2), p.call(0.2, 0.8), color, w)
		"bot", "tdm":
			draw_circle(p.call(0.5, 0.42), s * 0.32, color)
			draw_rect(Rect2(p.call(0.32, 0.6), Vector2(s * 0.36, s * 0.26)), color)
			var dark := Color(0.08, 0.09, 0.11)
			draw_circle(p.call(0.38, 0.44), s * 0.08, dark)
			draw_circle(p.call(0.62, 0.44), s * 0.08, dark)
			for x in [0.42, 0.5, 0.58]:
				draw_line(p.call(x, 0.72), p.call(x, 0.86), dark, w * 0.6)
		"bomb":
			draw_rect(Rect2(p.call(0.26, 0.28), Vector2(s * 0.48, s * 0.6)), color, false, w)
			draw_rect(Rect2(p.call(0.36, 0.4), Vector2(s * 0.28, s * 0.16)), color)
			draw_line(p.call(0.5, 0.28), p.call(0.5, 0.12), color, w)
			draw_circle(p.call(0.5, 0.1), s * 0.05, Color(1, 0.4, 0.2))
			for y in [0.66, 0.76]:
				draw_line(p.call(0.34, y), p.call(0.66, y), color, w * 0.6)
		"ffa":
			draw_arc(p.call(0.5, 0.5), s * 0.3, 0, TAU, 32, color, w)
			for d: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				draw_line(p.call(0.5 + d.x * 0.18, 0.5 + d.y * 0.18), p.call(0.5 + d.x * 0.46, 0.5 + d.y * 0.46), color, w)
			draw_circle(p.call(0.5, 0.5), s * 0.04, color)
		"random":
			draw_line(p.call(0.1, 0.3), p.call(0.35, 0.3), color, w)
			draw_line(p.call(0.35, 0.3), p.call(0.65, 0.7), color, w)
			draw_line(p.call(0.65, 0.7), p.call(0.88, 0.7), color, w)
			draw_line(p.call(0.1, 0.7), p.call(0.35, 0.7), color, w)
			draw_line(p.call(0.35, 0.7), p.call(0.65, 0.3), color, w)
			draw_line(p.call(0.65, 0.3), p.call(0.88, 0.3), color, w)
			for y in [0.3, 0.7]:
				draw_line(p.call(0.88, y), p.call(0.78, y - 0.1), color, w)
				draw_line(p.call(0.88, y), p.call(0.78, y + 0.1), color, w)
		"gear":
			draw_arc(p.call(0.5, 0.5), s * 0.24, 0, TAU, 24, color, w * 1.6)
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(p.call(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3), p.call(0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44), color, w * 1.8)
			draw_circle(p.call(0.5, 0.5), s * 0.08, color)
		"power":
			draw_arc(p.call(0.5, 0.54), s * 0.32, -PI * 0.3, PI * 1.3, 28, color, w)
			draw_line(p.call(0.5, 0.12), p.call(0.5, 0.5), color, w)
		"copy":
			draw_rect(Rect2(p.call(0.3, 0.12), Vector2(s * 0.5, s * 0.56)), color, false, w)
			draw_rect(Rect2(p.call(0.16, 0.3), Vector2(s * 0.5, s * 0.56)), color, false, w)
		"person":
			draw_circle(p.call(0.5, 0.32), s * 0.17, color)
			draw_arc(p.call(0.5, 0.95), s * 0.36, PI, TAU, 20, color, w * 2.2)
		"crown":
			var pts := PackedVector2Array([p.call(0.12, 0.78), p.call(0.12, 0.34), p.call(0.32, 0.56), p.call(0.5, 0.22),
				p.call(0.68, 0.56), p.call(0.88, 0.34), p.call(0.88, 0.78)])
			draw_colored_polygon(pts, color)
		"send":
			draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.45), p.call(0.9, 0.12), p.call(0.62, 0.88),
				p.call(0.5, 0.55)]), color)
