class_name SquadList
extends Control
## Your team down the left side (team modes): a numbered row per player —
## portrait (IconRenderer, rendered from their character; a drawn face until
## it is ready), name, health bar with the number, and a silhouette of the
## gun in their hands. Dead players are greyed out; you are outlined.
## Redrawn a few times a second.

const ROW := Vector2(276, 50)
const GAP := 6.0
const MAX_ROWS := 8

var level: Level
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		visible = Match.is_team_mode() and level != null
		queue_redraw()


func _team_ids() -> Array:
	var me := multiplayer.get_unique_id()
	var team := Match.get_team(me)
	var ids: Array = []
	for id: int in NetworkManager.roster:
		if Match.get_team(id) == team:
			ids.append(id)
	ids.sort()
	return ids


func _draw() -> void:
	if level == null or not Match.is_team_mode():
		return
	var font := get_theme_default_font()
	var me := multiplayer.get_unique_id()
	var team := Match.get_team(me)
	var col := GameConfig.team_color(team)
	var ids := _team_ids()
	for i in mini(ids.size(), MAX_ROWS):
		var id: int = ids[i]
		var p := level.get_player(id)
		var alive := p != null and not p.health.is_dead
		var y := i * (ROW.y + GAP)
		var a := 1.0 if alive else 0.45
		# Number tab, then the row.
		draw_rect(Rect2(Vector2(0, y), Vector2(22, ROW.y)), Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9 * a))
		_text(font, Vector2(6, y + ROW.y * 0.5 + 7), str(i + 1), 18, Color(1, 1, 1, a))
		draw_rect(Rect2(Vector2(24, y), Vector2(ROW.x - 24, ROW.y)), Color(0.03, 0.05, 0.09, 0.72))
		# Portrait.
		var pic := Rect2(Vector2(26, y + 2), Vector2(ROW.y - 4, ROW.y - 4))
		var look := NetworkManager.look_of(id)
		var tex := IconRenderer.cached_portrait(look)
		if tex:
			draw_texture_rect(tex, pic, false, Color(1, 1, 1, a))
		else:
			IconRenderer.request_portrait(self, look)
			TopBar.draw_face(self, pic, id, team)
		if id == me:
			draw_rect(Rect2(Vector2(24, y), Vector2(ROW.x - 24, ROW.y)), Color(1, 0.85, 0.3, 0.8), false, 1.5)
		# Name, health bar with the number.
		var x := 26 + ROW.y + 4
		_text(font, Vector2(x, y + 19), NetworkManager.get_player_name(id), 15, Color(1, 1, 1, a))
		var hp := p.health.current if p else 0.0
		var hp_max := p.health.max_health if p else 100.0
		_text(font, Vector2(x, y + 41), str(ceili(hp)) if alive else "DEAD", 13, Color(1, 1, 1, a))
		var bar := Rect2(Vector2(x + 30, y + 31), Vector2(ROW.x - x - 30 - 50, 10))
		draw_rect(bar, Color(1, 1, 1, 0.12))
		if alive:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp / hp_max, 0.0, 1.0), bar.size.y)),
				col.lightened(0.15) if hp > hp_max * 0.3 else Color(1, 0.35, 0.3))
		# The gun in their hands.
		if alive and p.current_weapon:
			var wid: String = p.current_weapon.data.weapon_id
			var gun := IconRenderer.cached_weapon(wid)
			var slot := Rect2(Vector2(ROW.x - 48, y + 8), Vector2(44, 17))
			if gun:
				draw_texture_rect(gun, slot, false, Color(1, 1, 1, 0.85))
			else:
				IconRenderer.request_weapon(self, wid)


func _text(font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.6 * color.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
