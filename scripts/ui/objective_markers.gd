class_name ObjectiveMarkers
extends Control
## Bomb Defusal: the sites as diamond markers ("A", "B") where they are on
## screen, with the distance; off screen or behind you they sit on the
## screen edge with an arrow pointing the way. Once the bomb is planted
## only its site shows, pulsing orange.

const SIZE := 16.0
const EDGE := 70.0
const SQUAD_EDGE := 330.0
const COLOR := Color(0.98, 0.78, 0.18)
const PLANTED := Color(1.0, 0.45, 0.15)

var level: Level


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	visible = Match.mode == GameConfig.Mode.BOMB and level != null and level.player != null \
		and not level.player.health.is_dead and Match.bomb.round_number > 0
	if visible:
		queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or level == null:
		return
	var font := get_theme_default_font()
	var b := Match.bomb
	var planted := b.bomb_state == BombRules.BombState.PLANTED
	var rect := get_viewport_rect()
	var center := rect.size * 0.5
	for site in level.bomb_sites:
		if site == null:
			continue
		if planted and site.name != b.bomb_site:
			continue
		var world: Vector3 = site.global_position + Vector3.UP * 1.5
		var col := PLANTED if planted else COLOR
		if planted:
			col.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 250.0))
		var local := cam.global_transform.affine_inverse() * world
		if absf(local.z) < 0.05:
			local.z = 0.05 # on the camera plane: unproject has no answer there
		var behind := local.z > 0.0
		var p := cam.unproject_position(cam.global_transform * local)
		if behind:
			p = center - (p - center) * 10.0 # mirror, so the edge arrow points the right way
		# Keep clear of the squad list down the left side.
		var area := Rect2(Vector2(SQUAD_EDGE if Match.is_team_mode() else EDGE, EDGE), Vector2.ZERO)
		area.end = rect.size - Vector2(EDGE, EDGE)
		var inside := not behind and area.has_point(p)
		var dir := Vector2.ZERO
		if not inside:
			dir = (p - center).normalized()
			var tx := INF
			var ty := INF
			if dir.x != 0:
				tx = ((area.end.x if dir.x > 0 else area.position.x) - center.x) / dir.x
			if dir.y != 0:
				ty = ((area.end.y if dir.y > 0 else area.position.y) - center.y) / dir.y
			p = center + dir * minf(tx, ty)
		# Diamond with the letter.
		var d := PackedVector2Array([p + Vector2(0, -SIZE), p + Vector2(SIZE, 0), p + Vector2(0, SIZE), p + Vector2(-SIZE, 0)])
		draw_colored_polygon(d, Color(0.05, 0.05, 0.05, 0.75 * col.a))
		draw_polyline(d + PackedVector2Array([d[0]]), col, 2.5)
		var letter: String = site.name
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(font, p + Vector2(-w * 0.5, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		if inside:
			var metres := "%d m" % roundi(cam.global_position.distance_to(site.global_position))
			var mw := font.get_string_size(metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string_outline(font, p + Vector2(-mw * 0.5, SIZE + 14), metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3,
				Color(0, 0, 0, 0.6))
			draw_string(font, p + Vector2(-mw * 0.5, SIZE + 14), metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
		else:
			# Arrow beyond the diamond, pointing the way.
			var tip := p + dir * (SIZE + 16)
			var side := dir.orthogonal() * 7
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 11 + side, tip - dir * 11 - side]), col)
