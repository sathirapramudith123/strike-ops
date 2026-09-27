class_name TopBar
extends Control
## CS-style bar at the top centre: the round clock in the middle, team
## scores either side of it and one card per player (a small drawn face —
## helmet, cap, beanie or balaclava, skin tone picked from the player id —
## greyed out and struck through when dead; yellow outline = you). Free-for-all and
## practice show just the clock. Redrawn a few times a second.

const CARD := Vector2(32, 32)
const SKIN := [Color(0.93, 0.76, 0.62), Color(0.8, 0.6, 0.45), Color(0.62, 0.44, 0.3), Color(0.45, 0.3, 0.2)]
const SCORE := Vector2(44, 34)
const CLOCK := Vector2(84, 34)
const GAP := 3.0
const MAX_CARDS := 5
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
			var t := "%d:%02d" % [secs / 60, secs % 60]
			if b.phase == BombRules.Phase.PLANTED:
				return [t, Color(1, 0.35, 0.25)]
			if b.phase == BombRules.Phase.FREEZE:
				return [t, Color(0.75, 0.85, 1.0)]
			return [t, Color.WHITE]
		_:
			if Match.time_limit > 0.0:
				var secs := ceili(Match.time_left)
				return ["%d:%02d" % [secs / 60, secs % 60], Color.WHITE if secs > 30 else Color(1, 0.45, 0.3)]
	return ["", Color.WHITE]


func _draw() -> void:
	var font := get_theme_default_font()
	var mid := size.x * 0.5
	var clock: Array = clock_text()
	var team_mode := Match.is_team_mode()
	if clock[0] == "" and not team_mode:
		return
	# Clock.
	var clock_rect := Rect2(Vector2(mid - CLOCK.x * 0.5, 0), CLOCK)
	draw_rect(clock_rect, COLOR_BOX)
	_centered(font, clock_rect, clock[0] if clock[0] != "" else "—", 22, clock[1])
	if Match.mode == GameConfig.Mode.BOMB and Match.bomb.round_number > 0:
		_centered(font, Rect2(clock_rect.position + Vector2(0, CLOCK.y), Vector2(CLOCK.x, 14)),
			"ROUND %d" % Match.bomb.round_number, 10, Color(1, 1, 1, 0.7))
	if not team_mode:
		return
	for team in 2:
		var side := -1.0 if team == 0 else 1.0
		var col := GameConfig.team_color(team)
		# Score box next to the clock.
		var sx := mid + side * (CLOCK.x * 0.5 + GAP) - (SCORE.x if side < 0 else 0.0)
		var score_rect := Rect2(Vector2(sx, 0), SCORE)
		draw_rect(score_rect, Color(col.r, col.g, col.b, 0.85))
		_centered(font, score_rect, str(Match.team_scores[team]), 22, Color.WHITE)
		# Player cards, nearest the score first.
		var ids := _team_ids(team)
		var x := sx + (-GAP - CARD.x if side < 0 else SCORE.x + GAP)
		for i in mini(ids.size(), MAX_CARDS):
			var id: int = ids[i]
			var alive := _is_alive(id)
			var rect := Rect2(Vector2(x, 2), CARD)
			var bg := col.darkened(0.35) if alive else Color(0.12, 0.12, 0.13, 0.7)
			draw_rect(rect, Color(bg.r, bg.g, bg.b, 0.9 if alive else 0.6))
			_draw_face(rect, id, team)
			if not alive:
				draw_rect(rect, Color(0.08, 0.08, 0.09, 0.6))
				draw_line(rect.position + Vector2(5, 5), rect.end - Vector2(5, 5), Color(1, 0.3, 0.25, 0.6), 2.0)
			if id == multiplayer.get_unique_id():
				draw_rect(rect, Color(1, 0.85, 0.3), false, 2.0)
			x += side * (CARD.x + GAP)
		if ids.size() > MAX_CARDS:
			var more := Rect2(Vector2(x if side > 0 else x + CARD.x - 24.0, 2), Vector2(24, CARD.y))
			_centered(font, more, "+%d" % (ids.size() - MAX_CARDS), 13, Color(1, 1, 1, 0.8))


## A little head in the card: face, eyes, and headgear by team — blue
## (defenders) wear helmets or caps, red (attackers) beanies or balaclavas.
func _draw_face(rect: Rect2, peer_id: int, team: int) -> void:
	var h := hash(peer_id)
	var skin: Color = SKIN[h % SKIN.size()]
	var c := rect.get_center() + Vector2(0, 3)
	var gear := GameConfig.team_color(team).darkened(0.55) if team >= 0 else Color(0.2, 0.2, 0.2)
	draw_rect(Rect2(c + Vector2(-9, 8), Vector2(18, 6)), gear.darkened(0.2)) # shoulders
	draw_circle(c, 9.0, skin)
	var style := (h / 7) % 2 + (0 if team == 0 else 2)
	match style:
		0: # helmet
			draw_circle(c + Vector2(0, -3), 10.0, gear.lightened(0.15))
			draw_rect(Rect2(c + Vector2(-11, -3), Vector2(22, 3)), gear)
			draw_rect(Rect2(c + Vector2(-8, 0), Vector2(16, 9)), skin)
		1: # cap
			draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 7)), gear.lightened(0.1))
			draw_rect(Rect2(c + Vector2(-2, -4), Vector2(13, 2.5)), gear)
		2: # beanie
			draw_rect(Rect2(c + Vector2(-9.5, -10), Vector2(19, 9)), Color(0.18, 0.18, 0.17))
		_: # balaclava: dark with an eye slit
			draw_circle(c, 9.5, Color(0.13, 0.13, 0.12))
			draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 5)), skin)
	for ex in [-3.5, 3.5]:
		draw_rect(Rect2(c + Vector2(ex - 1.2, -1.5), Vector2(2.4, 2.2)), Color(0.08, 0.07, 0.06))
	if style != 3:
		draw_line(c + Vector2(-2.5, 5), c + Vector2(2.5, 5), Color(0.3, 0.15, 0.12, 0.8), 1.2)


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
