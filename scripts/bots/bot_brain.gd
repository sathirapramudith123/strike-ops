class_name BotBrain
extends Node
## Drives one bot (server only; a child of the bot's PlayerController).
##
## • Sees enemies it has a clear line to (not through walls or smoke) in
##   front of it, reacts after a moment, turns towards them at a limited
##   speed with an aim error that shrinks, and fires in bursts while
##   strafing. Getting shot makes it turn round.
## • Otherwise walks a navigation path (BotManager) to a goal: a random spot
##   in FFA / TDM / Practice; in Bomb Defusal attackers take the bomb to a
##   site and plant it, defenders hold a site, then everyone heads for the
##   bomb (attackers to guard it, defenders to defuse).
## • Opens closed doors in its way, jumps / re-paths when stuck, reloads,
##   buys a gun and armour in the freeze time.
## Difficulty (BotManager.Difficulty) sets reaction time, turn speed, aim
## error, headshot chance and how far it sees.

const THINK_TIME := 0.15
const EYE_FOV := 140.0
const ARRIVE := 0.7
const STUCK_TIME := 1.1

## Per difficulty: reaction (s), turn speed (deg/s), initial aim error (deg),
## error decay (per s), headshot chance, sight range (m).
const SKILL := [
	{ "reaction": 0.55, "turn": 220.0, "error": 7.0, "decay": 2.0, "head": 0.05, "sight": 45.0 },
	{ "reaction": 0.35, "turn": 380.0, "error": 4.5, "decay": 3.5, "head": 0.2, "sight": 70.0 },
	{ "reaction": 0.2, "turn": 620.0, "error": 2.5, "decay": 6.0, "head": 0.45, "sight": 100.0 },
]

var player: PlayerController
var skill: Dictionary

var target: PlayerController
var _target_seen_at := 0.0
var _react_left := 0.0
var _aim_error := Vector2.ZERO
var _aim_head := false
var _last_seen_pos := Vector3.ZERO
var _has_last_seen := false
var _think := 0.0
var _burst_left := 0.0
var _pause_left := 0.0
var _strafe := 0.0
var _strafe_left := 0.0

var _goal := Vector3.ZERO
var _has_goal := false
var _path := PackedVector3Array()
var _path_index := 0
var _repath := 0.0
var _stuck_check := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_count := 0
var _door_check := 0.0
var _hold_left := 0.0
var _bought_round := -1
var _site := ""
var _last_health := 100.0
var _hurt_from := Vector3.ZERO
var _hurt_left := 0.0


func _ready() -> void:
	player = get_parent() as PlayerController
	skill = SKILL[clampi(Match.bots.difficulty, 0, SKILL.size() - 1)]
	player.health.damaged.connect(_on_damaged)
	player.respawned.connect(_on_respawned)


func _on_respawned() -> void:
	target = null
	_has_goal = false
	_has_last_seen = false
	_path = PackedVector3Array()
	_stuck_count = 0
	_site = ""
	_last_health = player.health.current


func _on_damaged(_amount: float, source: Node, _headshot: bool) -> void:
	# Turn towards whoever shot us (server knows the shooter).
	var shooter := source as PlayerController
	if shooter and not shooter.health.is_dead:
		_hurt_from = shooter.global_position
		_hurt_left = 1.5


func _physics_process(delta: float) -> void:
	if player.health.is_dead or Match.is_ended():
		_set_trigger(false)
		return
	_hurt_left -= delta
	_think -= delta
	if _think <= 0.0:
		_think = THINK_TIME
		_perceive()
	_bomb_duties()
	var move := Vector3.ZERO
	var wants_move := true
	if target:
		move = _fight(delta)
	else:
		_set_trigger(false)
		if _hurt_left > 0.0:
			_turn_towards(_hurt_from + Vector3.UP * 1.4, delta)
		move = _follow_path(delta)
		wants_move = move != Vector3.ZERO
	if not Match.can_move():
		move = Vector3.ZERO
		wants_move = false
		_buy()
	_move(move, delta)
	_unstick(delta, wants_move)
	_open_doors(delta)
	_reload_when_idle()
	if player.global_position.y < player.fall_limit_y:
		player.health.take_damage(99999.0, null)


# -----------------------------------------------------------------------------
# Seeing
# -----------------------------------------------------------------------------

func _perceive() -> void:
	var level := NetworkManager.current_level()
	if level == null:
		return
	var eye := player.camera.global_position
	var forward := -player.camera.global_basis.z
	var best: PlayerController = null
	var best_d: float = skill.sight
	for p in level.get_players():
		if p == player or p.health.is_dead or Match.is_friendly(player.peer_id, p.peer_id):
			continue
		var chest := p.global_position + Vector3.UP * 1.3
		var to := chest - eye
		var d := to.length()
		if d > best_d:
			continue
		# In front (or it just shot us / is the current target).
		var in_view := forward.dot(to / maxf(d, 0.01)) > cos(deg_to_rad(EYE_FOV * 0.5))
		if not in_view and p != target and not (_hurt_left > 0.0 and d < 40.0):
			continue
		if not _clear_line(eye, chest) and not _clear_line(eye, p.global_position + Vector3.UP * 1.65):
			continue
		best = p
		best_d = d
	if best != target:
		if best:
			_react_left = skill.reaction * randf_range(0.8, 1.3)
			var e: float = skill.error
			_aim_error = Vector2(randf_range(-e, e), randf_range(-e * 0.6, e * 0.6))
			_aim_head = randf() < skill.head
			_strafe_left = 0.0
		elif target and not target.health.is_dead:
			_last_seen_pos = target.global_position
			_has_last_seen = true
			_has_goal = false
		target = best
	if target:
		_target_seen_at = Time.get_ticks_msec() / 1000.0


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit.get("collider")
		# Glass doesn't hide anyone.
		if not (col and col.has_meta(&"breakable") and col.get_meta(&"breakable") is GlassPane):
			return false
	return not (get_tree().has_group(SmokeCloud.GROUP) and SmokeCloud.blocks_line(get_tree(), from, to))


# -----------------------------------------------------------------------------
# Fighting
# -----------------------------------------------------------------------------

func _fight(delta: float) -> Vector3:
	var aim_at := target.global_position + Vector3.UP * (1.62 if _aim_head else 1.3)
	_aim_error = _aim_error.move_toward(Vector2.ZERO, skill.decay * delta)
	var off := _turn_towards(aim_at, delta, _aim_error)
	_react_left -= delta
	var dist := player.global_position.distance_to(target.global_position)
	var weapon := player.current_weapon
	# Knife / out of ammo: switch to something that shoots.
	if weapon and (weapon.data.melee or (weapon.ammo_in_magazine <= 0 and weapon.ammo_reserve <= 0)):
		_best_weapon()
	var cone := clampf(atan2(0.45, maxf(dist, 1.0)), deg_to_rad(1.2), deg_to_rad(12.0))
	var can_fire := _react_left <= 0.0 and off < cone and Match.can_shoot()
	# Bursts at range, a pause to settle; at close range just hold it.
	if can_fire:
		if _pause_left > 0.0:
			_pause_left -= delta
			can_fire = false
		else:
			_burst_left -= delta
			if _burst_left <= 0.0:
				_burst_left = randf_range(0.35, 0.8) if dist > 12.0 else 2.0
				if dist > 12.0:
					_pause_left = randf_range(0.2, 0.4)
	_set_trigger(can_fire)
	# Strafe from side to side while fighting.
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(0.5, 1.2)
		_strafe = [-1.0, 0.0, 1.0].pick_random()
	var right := player.global_basis.x
	var move := right * _strafe
	# Close in on far targets, back off from very close ones.
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	if dist > 30.0:
		move += fwd.normalized() * 0.7
	elif dist < 4.0:
		move -= fwd.normalized() * 0.6
	return move


## Turns the body (yaw) and head (pitch) towards `point` at the bot's turn
## speed, offset by `error` (degrees). Returns the remaining angle (radians).
func _turn_towards(point: Vector3, delta: float, error: Vector2 = Vector2.ZERO) -> float:
	var eye := player.camera.global_position
	var to := point - eye
	var flat := Vector2(to.x, to.z).length()
	var want_yaw := atan2(-to.x, -to.z) + deg_to_rad(error.x)
	var want_pitch := clampf(atan2(to.y, flat) + deg_to_rad(error.y), -1.4, 1.4)
	var step := deg_to_rad(skill.turn) * delta
	player.rotation.y = rotate_toward(player.rotation.y, want_yaw, step)
	player.head.rotation.x = rotate_toward(player.head.rotation.x, want_pitch, step)
	return absf(angle_difference(player.rotation.y, atan2(-to.x, -to.z))) \
		+ absf(player.head.rotation.x - atan2(to.y, flat))


func _set_trigger(on: bool) -> void:
	if player.current_weapon:
		player.current_weapon.bot_trigger = on


func _best_weapon() -> void:
	var ws := player.loadout_weapons()
	for slot in [0, 1]:
		var w: Weapon = ws[slot]
		if w and (w.ammo_in_magazine > 0 or w.ammo_reserve > 0):
			if player.current_slot != slot:
				player._equip_slot(slot)
				player.net_sync.send_slot_from_server(slot)
			return
	if player.current_slot != 2:
		player._equip_slot(2)
		player.net_sync.send_slot_from_server(2)


func _reload_when_idle() -> void:
	var w := player.current_weapon
	if w == null or w.data.melee or w.is_reloading:
		return
	if w.ammo_in_magazine <= 0 or (target == null and w.ammo_in_magazine < w.data.magazine_size * 0.5):
		w.reload()
	if player.current_slot == 2 and target == null:
		_best_weapon()


# -----------------------------------------------------------------------------
# Moving
# -----------------------------------------------------------------------------

func _move(dir: Vector3, delta: float) -> void:
	var body := player
	var on_floor := body.is_on_floor()
	if not on_floor:
		body.velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	dir.y = 0.0
	var speed := body.walk_speed
	body.is_sprinting = target == null and dir.length() > 0.5 and _path.size() - _path_index > 2
	if body.is_sprinting:
		speed = body.sprint_speed
	var want := dir.limit_length(1.0) * speed
	var horizontal := Vector3(body.velocity.x, 0, body.velocity.z).move_toward(want, 40.0 * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	var before := body.global_position
	body.move_and_slide()
	if not NetworkManager.is_dedicated():
		body._remote_movement_sounds(before, body.global_position)
	# Face the way we walk when not fighting.
	if target == null and horizontal.length() > 0.5 and _hurt_left <= 0.0:
		var look := before + horizontal * 3.0 + Vector3.UP * 1.6
		_turn_towards(look, delta)


func _follow_path(delta: float) -> Vector3:
	if _hold_left > 0.0:
		_hold_left -= delta
		return Vector3.ZERO
	if not _has_goal:
		_pick_goal()
	_repath -= delta
	if _path.is_empty() or _repath <= 0.0:
		_make_path()
	if _path.is_empty():
		return Vector3.ZERO
	var pos := player.global_position
	while _path_index < _path.size():
		var p := _path[_path_index]
		if Vector2(p.x - pos.x, p.z - pos.z).length() > ARRIVE:
			break
		_path_index += 1
	if _path_index >= _path.size():
		# Arrived: wait a moment, then somewhere else (or stay, in Bomb Defusal).
		_has_goal = false
		_path = PackedVector3Array()
		_hold_left = randf_range(0.5, 2.5) if Match.mode != GameConfig.Mode.BOMB else randf_range(2.0, 5.0)
		return Vector3.ZERO
	var next := _path[_path_index]
	return Vector3(next.x - pos.x, 0, next.z - pos.z).normalized()


func _make_path() -> void:
	_repath = 1.5
	var level := NetworkManager.current_level()
	if level == null or not _has_goal:
		return
	var map := Match.bots.nav_map(level)
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return # not synced yet (first frame of the level)
	var from := NavigationServer3D.map_get_closest_point(map, player.global_position)
	var to := NavigationServer3D.map_get_closest_point(map, _goal)
	_path = NavigationServer3D.map_get_path(map, from, to, true)
	_path_index = 1 if _path.size() > 1 else 0


func _pick_goal() -> void:
	_has_goal = true
	_path = PackedVector3Array()
	if _has_last_seen:
		_goal = _last_seen_pos
		_has_last_seen = false
		return
	var level := NetworkManager.current_level()
	if Match.mode == GameConfig.Mode.BOMB and level:
		_goal = _bomb_goal(level)
		return
	# Somewhere else on the map: a spawn, a callout or a bomb site.
	var spots: Array[Vector3] = []
	if level:
		for m: Marker3D in level.spawn_points + level.bomb_sites:
			spots.append(m.global_position)
		var callouts := level.get_node_or_null("Callouts")
		if callouts:
			for c in callouts.get_children():
				spots.append((c as Node3D).global_position)
	_goal = spots.pick_random() if not spots.is_empty() else player.global_position


func _unstick(delta: float, wants_move: bool) -> void:
	_stuck_check -= delta
	if _stuck_check > 0.0:
		return
	_stuck_check = STUCK_TIME
	var moved := player.global_position.distance_to(_stuck_pos)
	_stuck_pos = player.global_position
	if not wants_move or target or _hold_left > 0.0 or not Match.can_move():
		_stuck_count = 0
		return
	if moved < 0.4:
		_stuck_count += 1
		if player.is_on_floor():
			player.velocity.y = player.jump_velocity
		_repath = 0.0
		if _stuck_count >= 3:
			_has_goal = false
			_stuck_count = 0
	else:
		_stuck_count = 0


## A closed door in front: open it (server-side use, like pressing F).
func _open_doors(delta: float) -> void:
	_door_check -= delta
	if _door_check > 0.0:
		return
	_door_check = 0.3
	var from := player.global_position + Vector3.UP * 1.2
	var dir := Vector3(player.velocity.x, 0, player.velocity.z)
	if dir.length() < 0.5:
		dir = -player.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 1.6, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = hit.get("collider")
	if col and col.has_meta(&"breakable") and col.get_meta(&"breakable") is Door:
		var door := col.get_meta(&"breakable") as Door
		if not door.is_open():
			door._server_toggle(player.global_position)


# -----------------------------------------------------------------------------
# Bomb Defusal
# -----------------------------------------------------------------------------

func _bomb_goal(level: Level) -> Vector3:
	var b := Match.bomb
	var attacker := b.is_attacker(player.peer_id)
	if b.bomb_state == BombRules.BombState.PLANTED:
		return b.bomb_position + (Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) if attacker else Vector3.ZERO)
	if attacker and b.bomb_state == BombRules.BombState.DROPPED:
		return b.bomb_position
	if _site == "":
		_site = ["A", "B"].pick_random() if attacker else ("A" if (player.peer_id % 2 == 0) else "B")
		if attacker:
			# The whole attacking side goes for the same site this round.
			_site = "A" if (b.round_number % 2 == 0) else "B"
	for m: Marker3D in level.bomb_sites:
		if m.name == _site:
			var spread := 0.0 if b.bomb_carrier == player.peer_id else 5.0
			return m.global_position + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	return player.global_position


## Plant when carrying the bomb on the site, defuse when next to it.
func _bomb_duties() -> void:
	if Match.mode != GameConfig.Mode.BOMB:
		return
	var b := Match.bomb
	var id := player.peer_id
	var act := false
	if target == null:
		if b.bomb_carrier == id and b.site_at(player.global_position) == _site and _site != "":
			act = true
		elif b.bomb_state == BombRules.BombState.PLANTED and not b.is_attacker(id) \
				and player.global_position.distance_to(b.bomb_position) <= BombRules.DEFUSE_RANGE - 0.3:
			act = true
	b.server_set_interact(id, act)
	if act:
		_hold_left = 0.3 # stand still while planting / defusing
		_path = PackedVector3Array()
	# New round / bomb planted / dropped: fresh goals.
	if b.phase == BombRules.Phase.FREEZE:
		_site = ""
		_has_goal = false
	var planted := b.bomb_state == BombRules.BombState.PLANTED
	if planted and _has_goal and _goal.distance_to(b.bomb_position) > 8.0:
		_has_goal = false


func _buy() -> void:
	if Match.mode != GameConfig.Mode.BOMB or _bought_round == Match.bomb.round_number:
		return
	_bought_round = Match.bomb.round_number
	var eco := Match.economy
	var id := player.peer_id
	var money := Economy.money_of(id)
	if player.primary_id == "":
		if money >= 2700 + 650:
			eco._server_buy(id, "rifle")
		elif money >= 1250 + 650:
			eco._server_buy(id, "smg")
	if Economy.money_of(id) >= 1000:
		eco._server_buy(id, "vest_helmet")
	elif Economy.money_of(id) >= 650:
		eco._server_buy(id, "vest")
