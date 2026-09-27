class_name Minimap
extends Control
## Round radar in the top-left corner (CS style). The map picture is built
## once from the level's collision shapes — walkable floor light, walls dark,
## low cover in between — so every map gets a radar without hand-made art.
## It turns with the player (forward = up); markers for teammates, the bomb
## sites and the bomb are drawn on top. `location()` names the area the
## player stands in (the map's "Callouts" boxes, or the bomb sites).

const PIXELS_PER_METRE := 2.4
## Shapes whose top is lower than this are floor; higher than WALL_HEIGHT
## are walls. Anything starting above HEAD_HEIGHT is a ceiling (ignored).
const FLOOR_HEIGHT := 0.25
const WALL_HEIGHT := 2.2
const HEAD_HEIGHT := 2.6

const COLOR_BACK := Color(0.03, 0.04, 0.05, 0.6)
const COLOR_FLOOR := Color(0.6, 0.55, 0.45, 0.98)
const COLOR_COVER := Color(0.38, 0.35, 0.3, 0.95)
const COLOR_WALL := Color(0.11, 0.12, 0.13, 0.95)
const COLOR_ME := Color(0.55, 0.9, 1.0)
const COLOR_SITE := Color(1, 0.7, 0.2)
const COLOR_BOMB := Color(1, 0.35, 0.2)

var level: Level
var _layer: Control
var _overlay: Control
var _polys: Array = [] # [PackedVector2Array (metres), Color]
var _callouts: Array = [] # [label, AABB]
var _center_world := Vector2.ZERO
var _yaw := 0.0


func _ready() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = Control.new()
	_layer.name = "Layer"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.draw.connect(_draw_layer)
	add_child(_layer)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Reads the level's geometry (call once the level is in the tree).
func build(l: Level) -> void:
	level = l
	_polys.clear()
	_callouts.clear()
	var geometry := l.get_node_or_null("Geometry")
	if geometry == null:
		return
	var floors: Array = []
	var solids: Array = [] # [top, poly, color]
	for node in geometry.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.disabled or cs.shape == null:
			continue
		var info := _footprint(cs)
		if info.is_empty():
			continue
		var top: float = info.top
		var bottom: float = info.bottom
		if bottom > HEAD_HEIGHT:
			continue
		if top < FLOOR_HEIGHT:
			floors.append(info.poly)
		else:
			solids.append([top, info.poly, COLOR_WALL if top > WALL_HEIGHT else COLOR_COVER])
	solids.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for p in floors:
		_polys.append([p, COLOR_FLOOR])
	for s in solids:
		_polys.append([s[1], s[2]])
	var callouts := l.get_node_or_null("Callouts")
	if callouts:
		for c in callouts.get_children():
			if c is Node3D and c.has_meta(&"label") and c.has_meta(&"size"):
				var size: Vector3 = c.get_meta(&"size")
				_callouts.append([str(c.get_meta(&"label")), AABB((c as Node3D).global_position - size * 0.5, size)])
	# Smallest box first, so a site inside a bigger area wins.
	_callouts.sort_custom(func(a: Array, b: Array) -> bool: return a[1].get_volume() < b[1].get_volume())
	_layer.queue_redraw()


## Name of the area around `pos` ("Bombsite A", "Mid", …) or "".
func location(pos: Vector3) -> String:
	for c in _callouts:
		if (c[1] as AABB).has_point(pos):
			return c[0]
	if level:
		for site in level.bomb_sites:
			if site and Vector2(pos.x - site.global_position.x, pos.z - site.global_position.z).length() \
					<= BombRules.SITE_RADIUS * 1.6:
				return "Bombsite %s" % site.name
	return ""


func _process(_delta: float) -> void:
	if level == null or not is_visible_in_tree():
		return
	var viewer := _viewer()
	if viewer:
		var cam := viewer.camera
		var fwd := -cam.global_basis.z
		_yaw = atan2(-fwd.x, -fwd.z)
		_center_world = Vector2(viewer.global_position.x, viewer.global_position.z)
	var c := size * 0.5
	_layer.rotation = _yaw
	_layer.position = c - (_center_world * PIXELS_PER_METRE).rotated(_yaw)
	_overlay.queue_redraw()


## The player the radar follows: the local player, or whoever is spectated.
func _viewer() -> PlayerController:
	if level == null:
		return null
	var watched := level.spectating()
	if watched:
		return watched
	return level.player


func _draw() -> void:
	var r := size.x * 0.5
	draw_circle(size * 0.5, r, COLOR_BACK)


func _draw_layer() -> void:
	for entry in _polys:
		var pts: PackedVector2Array = entry[0]
		var scaled := PackedVector2Array()
		scaled.resize(pts.size())
		for i in pts.size():
			scaled[i] = pts[i] * PIXELS_PER_METRE
		_layer.draw_colored_polygon(scaled, entry[1])


func _draw_overlay() -> void:
	if level == null:
		return
	var c := size * 0.5
	var r := size.x * 0.5
	var font := get_theme_default_font()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var viewer := _viewer()
	# Bomb sites.
	for site in level.bomb_sites:
		if site == null:
			continue
		var p := _to_screen(site.global_position, r - 12.0)
		var box := Rect2(p - Vector2(9, 10), Vector2(18, 20))
		_overlay.draw_rect(box, Color(0, 0, 0, 0.55))
		_overlay.draw_rect(box, COLOR_SITE, false, 1.5)
		_overlay.draw_string(font, p + Vector2(-5.5, 6.5), site.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, COLOR_SITE)
	# Teammates (everyone in FFA is an enemy — none shown).
	if Match.is_team_mode():
		for p in level.get_players():
			if p == viewer or p.health.is_dead or not Match.is_friendly(p.peer_id, me):
				continue
			var sp := _to_screen(p.global_position, r - 5.0)
			var col := GameConfig.team_color(Match.get_team(p.peer_id)).lightened(0.35)
			# A dot with a small tick showing where they look.
			var look := -p.camera.global_basis.z
			var dir := Vector2(look.x, look.z).normalized().rotated(_yaw)
			_overlay.draw_line(sp, sp + dir * 8.0, Color(col, 0.9), 2.0)
			_overlay.draw_circle(sp, 4.5, Color.BLACK)
			_overlay.draw_circle(sp, 3.5, col)
			if Match.mode == GameConfig.Mode.BOMB and Match.bomb.bomb_state == BombRules.BombState.CARRIED \
					and Match.bomb.bomb_carrier == p.peer_id:
				_overlay.draw_arc(sp, 6.5, 0.0, TAU, 12, COLOR_BOMB, 1.5)
	# The bomb: planted (everyone) or dropped (attackers only).
	if Match.mode == GameConfig.Mode.BOMB:
		var b := Match.bomb
		var show := b.bomb_state == BombRules.BombState.PLANTED \
			or (b.bomb_state == BombRules.BombState.DROPPED and b.is_attacker(me))
		if show and (b.bomb_state != BombRules.BombState.PLANTED or fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.4):
			var bp := _to_screen(b.bomb_position, r - 6.0)
			# Dropped: a plain block. Planted: a block with a ring (blinking).
			_overlay.draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), COLOR_BOMB)
			_overlay.draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.0)
			if b.bomb_state == BombRules.BombState.PLANTED:
				_overlay.draw_arc(bp, 8.0, 0.0, TAU, 16, COLOR_BOMB, 1.5)
	# Me: an arrow pointing up, at the centre.
	var arrow := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)])
	_overlay.draw_colored_polygon(arrow, COLOR_ME)
	_overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.0)
	_overlay.draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)


## World position -> radar pixels, clamped to `max_r` from the centre.
func _to_screen(world: Vector3, max_r: float) -> Vector2:
	var d := (Vector2(world.x, world.z) - _center_world) * PIXELS_PER_METRE
	d = d.rotated(_yaw)
	if d.length() > max_r:
		d = d.normalized() * max_r
	return size * 0.5 + d


## Top-down outline of a box or cylinder shape, in metres, plus its height span.
static func _footprint(cs: CollisionShape3D) -> Dictionary:
	var t := cs.global_transform
	var pts := PackedVector2Array()
	var top := -INF
	var bottom := INF
	if cs.shape is BoxShape3D:
		var h := (cs.shape as BoxShape3D).size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := t * Vector3(h.x * sx, h.y * sy, h.z * sz)
					pts.append(Vector2(p.x, p.z))
					top = maxf(top, p.y)
					bottom = minf(bottom, p.y)
		pts = Geometry2D.convex_hull(pts)
		if pts.size() > 1 and pts[0] == pts[pts.size() - 1]:
			pts.remove_at(pts.size() - 1) # the hull repeats its first point
	elif cs.shape is CylinderShape3D:
		var cyl := cs.shape as CylinderShape3D
		var o := t.origin
		for i in 12:
			var a := TAU * i / 12.0
			pts.append(Vector2(o.x + cos(a) * cyl.radius, o.z + sin(a) * cyl.radius))
		top = o.y + cyl.height * 0.5
		bottom = o.y - cyl.height * 0.5
	else:
		return {}
	if pts.size() < 3:
		return {}
	return { "poly": pts, "top": top, "bottom": bottom }
