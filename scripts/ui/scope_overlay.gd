class_name ScopeOverlay
extends Control
## Sniper scope: black mask outside a circle, fine crosshair and mil dots.

var amount: float = 0.0 # 0..1 fade


func _process(_delta: float) -> void:
	visible = amount > 0.01
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var black := Color(0, 0, 0, amount)
	# Everything outside the lens: side bars + a thick ring for the corners.
	draw_rect(Rect2(0, 0, c.x - r, size.y), black)
	draw_rect(Rect2(c.x + r, 0, size.x - (c.x + r), size.y), black)
	var ring := r * 0.6
	draw_arc(c, r + ring * 0.5, 0.0, TAU, 96, black, ring, true)
	var line := Color(0, 0, 0, 0.85 * amount)
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), line, 1.5)
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), line, 1.5)
	for i in range(1, 5):
		var d := r * 0.12 * i
		for p: Vector2 in [c + Vector2(d, 0), c - Vector2(d, 0), c + Vector2(0, d), c - Vector2(0, d)]:
			draw_circle(p, 2.0, line)
