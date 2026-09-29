class_name TopBar
extends Control
## Score bar at the top centre: the clock in a slanted box with the round
## (ROUND 8/10, FIRST TO 50…) under it, each team's score in its colour
## with the team emblem, and a dot per player still alive (the players
## themselves are listed on the left, SquadList). Free-for-all shows the
## clock with your kills against the leader's. Redrawn a few times a second.

const SKIN := [Color(0.93, 0.76, 0.62), Color(0.8, 0.6, 0.45), Color(0.62, 0.44, 0.3), Color(0.45, 0.3, 0.2)]
const SCORE := Vector2(58, 36)
const CLOCK := Vector2(110, 36)
const GAP := 3.0
const COLOR_BOX := Color(0.05, 0.06, 0.08, 0.72)

var level: Level
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.2
		queue_redraw()


## "1:45", "BOMB 0:32" (red), or "" when the mode has no clock.
func clock_text() -> Array:
	match Match.mode:
		GameConfig.Mode.BOMB:
			var b := Match.bomb
			var secs := ceili(b.phase_time_left)
			var t := "%d:%02d" % [floori(secs / 60.0), secs % 60]
			if b.phase == BombRules.Phase.PLANTED:
				return [t, Color(1, 0.35, 0.25)]
			if b.phase == BombRules.Phase.FREEZE:
				return [t, Color(0.75, 0.85, 1.0)]
			return [t, Color.WHITE]
		_:
			if Match.time_limit > 0.0:
				var secs := ceili(Match.time_left)
				return ["%d:%02d" % [floori(secs / 60.0), secs % 60], Color.WHITE if secs > 30 else Color(1, 0.45, 0.3)]
	return ["", Color.WHITE]


func _draw() -> void:
	var font := get_theme_default_font()
	var mid := size.x * 0.5
	var clock: Array = clock_text()
	var team_mode := Match.is_team_mode()
	if clock[0] == "" and not team_mode:
		return
	# Clock in a slanted dark box, the round (or goal) under it.
	var cw := CLOCK.x * 0.5
	var box := PackedVector2Array([Vector2(mid - cw - 10, 0), Vector2(mid + cw + 10, 0), Vector2(mid + cw, CLOCK.y + 4),
		Vector2(mid - cw, CLOCK.y + 4)])
	draw_colored_polygon(box, Color(0.04, 0.06, 0.1, 0.88))
	draw_polyline(box + PackedVector2Array([box[0]]), Color(1, 1, 1, 0.12), 1.0)
	_centered(font, Rect2(Vector2(mid - cw, 0), Vector2(CLOCK.x, CLOCK.y + 4)), clock[0] if clock[0] != "" else "—", 26, clock[1])
	var sub := sub_text()
	if sub != "":
		var sw := CLOCK.x - 6.0
		var sub_box := PackedVector2Array([Vector2(mid - sw * 0.5, CLOCK.y + 5), Vector2(mid + sw * 0.5, CLOCK.y + 5),
			Vector2(mid + sw * 0.5 - 8, CLOCK.y + 22), Vector2(mid - sw * 0.5 + 8, CLOCK.y + 22)])
		draw_colored_polygon(sub_box, Color(0.04, 0.06, 0.1, 0.8))
		_centered(font, Rect2(Vector2(mid - sw * 0.5, CLOCK.y + 5), Vector2(sw, 17)), sub, 11, Color(1, 1, 1, 0.8))
	if not team_mode:
		return
	for team in 2:
		var side := -1.0 if team == 0 else 1.0
		var col := GameConfig.team_color(team)
		# A slanted score panel in the team colour, the emblem on its far end.
		var x0 := mid + side * (cw + 12)
		var x1 := x0 + side * SCORE.x
		var panel := PackedVector2Array([Vector2(x0 - side * 10, 0), Vector2(x1 + side * 20, 0), Vector2(x1 + side * 8, CLOCK.y + 4),
			Vector2(x0, CLOCK.y + 4)])
		draw_colored_polygon(panel, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.9))
		draw_colored_polygon(PackedVector2Array([panel[0], panel[1], Vector2(panel[1].x - side * 3, 4), Vector2(panel[0].x, 4)]),
			col.lightened(0.2))
		_centered(font, Rect2(Vector2(minf(x0, x1), 0), Vector2(SCORE.x, CLOCK.y + 4)), str(Match.team_scores[team]), 28,
			Color.WHITE)
		_draw_emblem(Vector2(x1 + side * 34, (CLOCK.y + 4) * 0.5), team)
		# Small dots for the players still alive (the full list is on the left).
		var ids := _team_ids(team)
		var alive := 0
		for id: int in ids:
			if _is_alive(id):
				alive += 1
		for i in ids.size():
			var dx := side * (10.0 + i * 9.0)
			var dot := Vector2(x1 + side * 60 + dx, (CLOCK.y + 4) * 0.5)
			draw_circle(dot, 3.2, col.lightened(0.3) if i < alive else Color(1, 1, 1, 0.2))


## Under the clock: "ROUND 8/10", "OVERTIME 1", "FIRST TO 50", or in
## free-for-all your kills against the leader's.
func sub_text() -> String:
	match Match.mode:
		GameConfig.Mode.BOMB:
			var b := Match.bomb
			if b.round_number <= 0:
				return ""
			if b.is_overtime():
				return "OVERTIME %d · ROUND %d" % [b.overtime, b.round_number]
			return "ROUND %d/%d" % [b.round_number, b.regulation_rounds()]
		GameConfig.Mode.TDM:
			return "FIRST TO %d" % Match.score_limit
		GameConfig.Mode.FFA:
			var mine: int = NetworkManager.roster.get(multiplayer.get_unique_id(), {}).get("kills", 0)
			var best := 0
			for id: int in NetworkManager.roster:
				best = maxi(best, int(NetworkManager.roster[id].get("kills", 0)))
			return "YOU %d · TOP %d / %d" % [mine, best, Match.score_limit]
	return ""


## Team emblems: blue a shield with chevrons and wings, red a shield with
## spread wings and a fang.
func _draw_emblem(c: Vector2, team: int) -> void:
	var col := GameConfig.team_color(team).lightened(0.15)
	var dark := GameConfig.team_color(team).darkened(0.5)
	var shield := PackedVector2Array([c + Vector2(-11, -13), c + Vector2(11, -13), c + Vector2(11, 1), c + Vector2(0, 14),
		c + Vector2(-11, 1)])
	for sx in [-1.0, 1.0]:
		var wing := PackedVector2Array([c + Vector2(sx * 9, -10), c + Vector2(sx * 22, -16), c + Vector2(sx * 19, -4),
			c + Vector2(sx * 23, -2), c + Vector2(sx * 15, 6), c + Vector2(sx * 9, 2)])
		draw_colored_polygon(wing, col.darkened(0.15))
	draw_colored_polygon(shield, col)
	draw_polyline(shield + PackedVector2Array([shield[0]]), dark, 1.5)
	if team == 0:
		for i in 2:
			var y := -6.0 + i * 7.0
			draw_polyline(PackedVector2Array([c + Vector2(-6, y), c + Vector2(0, y + 5), c + Vector2(6, y)]), dark, 2.5)
	else:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(5, -8), c + Vector2(0, 8)]), dark)


## A little drawn head (the fallback portrait until the real one is
## rendered): face, eyes, and headgear by team — blue wear helmets or caps,
## red beanies or balaclavas.
static func draw_face(ci: CanvasItem, rect: Rect2, peer_id: int, team: int) -> void:
	var h := hash(peer_id)
	var skin: Color = SKIN[h % SKIN.size()]
	var c := rect.get_center() + Vector2(0, 3)
	var gear := GameConfig.team_color(team).darkened(0.55) if team >= 0 else Color(0.2, 0.2, 0.2)
	ci.draw_rect(Rect2(c + Vector2(-9, 8), Vector2(18, 6)), gear.darkened(0.2)) # shoulders
	ci.draw_circle(c, 9.0, skin)
	var style := floori(h / 7.0) % 2 + (0 if team == 0 else 2)
	match style:
		0: # helmet
			ci.draw_circle(c + Vector2(0, -3), 10.0, gear.lightened(0.15))
			ci.draw_rect(Rect2(c + Vector2(-11, -3), Vector2(22, 3)), gear)
			ci.draw_rect(Rect2(c + Vector2(-8, 0), Vector2(16, 9)), skin)
		1: # cap
			ci.draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 7)), gear.lightened(0.1))
			ci.draw_rect(Rect2(c + Vector2(-2, -4), Vector2(13, 2.5)), gear)
		2: # beanie
			ci.draw_rect(Rect2(c + Vector2(-9.5, -10), Vector2(19, 9)), Color(0.18, 0.18, 0.17))
		_: # balaclava: dark with an eye slit
			ci.draw_circle(c, 9.5, Color(0.13, 0.13, 0.12))
			ci.draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 5)), skin)
	for ex in [-3.5, 3.5]:
		ci.draw_rect(Rect2(c + Vector2(ex - 1.2, -1.5), Vector2(2.4, 2.2)), Color(0.08, 0.07, 0.06))
	if style != 3:
		ci.draw_line(c + Vector2(-2.5, 5), c + Vector2(2.5, 5), Color(0.3, 0.15, 0.12, 0.8), 1.2)


func _team_ids(team: int) -> Array:
	var ids: Array = []
	for id: int in NetworkManager.roster:
		if Match.get_team(id) == team:
			ids.append(id)
	ids.sort()
	return ids


func _is_alive(peer_id: int) -> bool:
	if level == null:
		return true
	var p := level.get_player(peer_id)
	return p != null and not p.health.is_dead


func _centered(font: Font, rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := font.get_ascent(font_size)
	var desc := font.get_descent(font_size)
	var pos := Vector2(rect.position.x + (rect.size.x - w) * 0.5, rect.position.y + (rect.size.y + asc - desc) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
