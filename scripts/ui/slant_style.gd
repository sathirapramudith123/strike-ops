class_name SlantStyle
extends StyleBox
## The HUD's tactical strip: a dark, see-through parallelogram with a thin
## accent line along the top. `slant` (px) leans the edges — positive cuts
## the right edge (a strip in the bottom-left corner), negative the left.

var bg := Color(0.02, 0.03, 0.05, 0.55)
var accent := Color(1.0, 0.72, 0.25, 0.9)
var accent_width := 2.0
var slant := 18.0


func _init(lean: float = 18.0, pad := Vector4(14, 8, 14, 8)) -> void:
	slant = lean
	content_margin_left = pad.x + (absf(lean) if lean < 0.0 else 0.0)
	content_margin_top = pad.y
	content_margin_right = pad.z + (lean if lean > 0.0 else 0.0)
	content_margin_bottom = pad.w


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var tl := rect.position
	var br := rect.end
	var pts: PackedVector2Array
	if slant >= 0.0:
		pts = [tl, Vector2(br.x, tl.y), Vector2(br.x - slant, br.y), Vector2(tl.x, br.y)]
	else:
		pts = [Vector2(tl.x - slant, tl.y), Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]
	RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, [bg])
	if accent_width > 0.0:
		RenderingServer.canvas_item_add_line(to_canvas_item, pts[0], pts[1], accent, accent_width)
