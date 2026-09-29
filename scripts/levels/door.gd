class_name Door
extends Node3D
## A door in a doorway (placed by tools/greybox.py: Map.door). Interact (F)
## opens it — away from you — or closes it. Wide doorways get double doors.
##
## Each leaf is a grid of wooden pieces with their own health: bullets (and
## the knife, and HE blasts) splinter the piece they hit, and a piece that
## runs out of health breaks away, leaving a hole you can see and shoot
## through — the door breaks where you shoot it.
##
## Server-authoritative: players ask the server to open/close and the server
## deals the damage, then tells every peer (late joiners get the whole state).
## The node path (/root/<Map>/Doors/DoorN) is the same on every peer.

const GROUP := &"doors"
## Late joiners get the state of every node in this group (send_state_to).
const NET_GROUP := &"net_state"
const OPEN_ANGLE := 95.0
const SWING_TIME := 0.35
## Pieces are about this size (m).
const PIECE := 0.4
const PIECE_HEALTH := 45.0
const THICKNESS := 0.06
## How close (m) a player must be to use the door (server check).
const USE_RANGE := 3.0
const WOOD := Color(0.42, 0.28, 0.16)

@export var width: float = 1.6
@export var height: float = 2.4

## 0 = closed, 1 / -1 = open towards local +Z / -Z.
var open_side: int = 0
var _hinges: Array[Node3D] = []
var _leaves: Array[StaticBody3D] = []
## leaf index -> Array of piece health.
var _health: Array = []
## leaf index -> Array of [MeshInstance3D, CollisionShape3D, Rect2 in leaf space].
var _pieces: Array = []
var _tween: Tween
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(NET_GROUP)
	_material = StandardMaterial3D.new()
	_material.albedo_color = WOOD
	_material.roughness = 0.85
	var leaves := 2 if width > 1.25 else 1
	var leaf_w := (width - 0.04) / leaves
	for i in leaves:
		_build_leaf(i, leaves, leaf_w)


func _build_leaf(i: int, count: int, leaf_w: float) -> void:
	# Hinge at the outer edge of each leaf; a double door opens from the middle.
	var hinge := Node3D.new()
	hinge.name = "Hinge%d" % i
	var side := -1.0 if i == 0 else 1.0
	hinge.position = Vector3(side * (width * 0.5 - 0.02) if count == 2 else -width * 0.5 + 0.02, 0, 0)
	add_child(hinge)
	var body := StaticBody3D.new()
	body.name = "Leaf%d" % i
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"breakable", self)
	body.set_meta(&"leaf", i)
	# The leaf runs from the hinge towards the middle.
	var dir := -side if count == 2 else 1.0
	body.position = Vector3(dir * leaf_w * 0.5, 0, 0)
	hinge.add_child(body)
	var cols := maxi(1, roundi(leaf_w / PIECE))
	var rows := maxi(1, roundi((height - 0.02) / PIECE))
	var pw := leaf_w / cols
	var ph := (height - 0.02) / rows
	var healths := []
	var pieces := []
	for r in rows:
		for c in cols:
			var center := Vector3(-leaf_w * 0.5 + (c + 0.5) * pw, 0.01 + (r + 0.5) * ph, 0)
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(pw - 0.004, ph - 0.004, THICKNESS)
			mesh.mesh = box
			mesh.material_override = _material
			mesh.position = center
			body.add_child(mesh)
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(pw, ph, THICKNESS)
			shape.shape = bs
			shape.position = center
			body.add_child(shape)
			healths.append(PIECE_HEALTH)
			pieces.append([mesh, shape, Rect2(center.x - pw * 0.5, center.y - ph * 0.5, pw, ph)])
	# A handle on both faces, near the free edge.
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.12, 0.03, THICKNESS + 0.08)
	handle.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.7, 0.66, 0.55)
	hmat.metallic = 0.8
	hmat.roughness = 0.35
	handle.material_override = hmat
	handle.position = Vector3(-dir * (leaf_w * 0.5 - 0.12), 1.0, 0)
	body.add_child(handle)
	_hinges.append(hinge)
	_leaves.append(body)
	_health.append(healths)
	_pieces.append(pieces)


func is_open() -> bool:
	return open_side != 0


## Leaves still standing (tests, bots).
func leaf(i: int) -> StaticBody3D:
	return _leaves[i]


func pieces_left() -> int:
	var n := 0
	for hs: Array in _health:
		for h: float in hs:
			if h > 0.0:
				n += 1
	return n


# -----------------------------------------------------------------------------
# Opening / closing
# -----------------------------------------------------------------------------

## Local player (or a bot on the server) uses the door from `from` (a world position).
func request_toggle(from: Vector3) -> void:
	if multiplayer.is_server():
		_server_toggle(from)
	elif NetworkManager.is_online():
		_request_toggle.rpc_id(1, from)


@rpc("any_peer", "call_remote", "reliable")
## (`_from` is ignored: the server uses where it knows the player is.)
func _request_toggle(_from: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var level := NetworkManager.current_level()
	var p := level.get_player(multiplayer.get_remote_sender_id()) if level else null
	if p == null or p.health.is_dead or p.global_position.distance_to(global_position) > USE_RANGE + 1.0:
		return
	_server_toggle(p.global_position)


func _server_toggle(from: Vector3) -> void:
	var side := 0
	if open_side == 0:
		# Open away from whoever uses it.
		var local := to_local(from)
		side = -1 if local.z > 0.0 else 1
	set_open(side)
	NetworkManager.send_to_ready(self, &"_client_set_open", [side])


@rpc("authority", "call_remote", "reliable")
func _client_set_open(side: int) -> void:
	set_open(side)


## Swings the leaves (every peer). side: 0 closed, 1 / -1 open.
func set_open(side: int, instant: bool = false) -> void:
	if side != open_side and not instant:
		Audio.play_3d(&"door_open" if side != 0 else &"door_close", global_position + Vector3.UP, -6.0, 20.0,
			randf_range(0.92, 1.08), 3.0)
	open_side = side
	if _tween:
		_tween.kill()
	var count := _hinges.size()
	if instant:
		for i in count:
			_hinges[i].rotation.y = _target_angle(i, count)
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in count:
		_tween.tween_property(_hinges[i], "rotation:y", _target_angle(i, count), SWING_TIME)


func _target_angle(i: int, count: int) -> float:
	# Each leaf turns so that it swings towards `open_side` (local ±Z); a
	# leaf that runs along +X from its hinge needs a negative turn for +Z.
	var runs := -1.0 if (count == 2 and i == 1) else 1.0
	return -runs * open_side * deg_to_rad(OPEN_ANGLE)


# -----------------------------------------------------------------------------
# Damage
# -----------------------------------------------------------------------------

## Server: a bullet (or the knife) hit `body` at world `point` for `damage`.
func server_hit(body: Node, point: Vector3, damage: float) -> void:
	if not multiplayer.is_server() or not body.has_meta(&"leaf"):
		return
	var li: int = body.get_meta(&"leaf")
	var local := (body as Node3D).to_local(point)
	var pi := _piece_at(li, Vector2(local.x, local.y))
	if pi < 0:
		return
	_apply_hit(li, pi, damage)
	NetworkManager.send_to_ready(self, &"_client_hit", [li, pi, damage])


## Server: an explosion at `pos` (HE grenade) — every piece in reach.
func server_blast(pos: Vector3, radius: float, damage: float) -> void:
	if not multiplayer.is_server():
		return
	for li in _leaves.size():
		for pi in (_pieces[li] as Array).size():
			if _health[li][pi] <= 0.0:
				continue
			var piece: Array = _pieces[li][pi]
			var d := (piece[0] as Node3D).global_position.distance_to(pos)
			if d < radius:
				var dmg := damage * (1.0 - d / radius)
				_apply_hit(li, pi, dmg)
				NetworkManager.send_to_ready(self, &"_client_hit", [li, pi, dmg])


@rpc("authority", "call_remote", "reliable")
func _client_hit(li: int, pi: int, damage: float) -> void:
	_apply_hit(li, pi, damage)


func _apply_hit(li: int, pi: int, damage: float) -> void:
	if li >= _health.size() or pi >= (_health[li] as Array).size() or _health[li][pi] <= 0.0:
		return
	_health[li][pi] = maxf(_health[li][pi] - damage, 0.0)
	var piece: Array = _pieces[li][pi]
	var mesh := piece[0] as MeshInstance3D
	_splinters(mesh.global_position, 5 if _health[li][pi] > 0.0 else 12)
	if _health[li][pi] <= 0.0:
		_break_piece(li, pi)
		Audio.play_3d(&"wood_break", mesh.global_position, -4.0, 25.0, randf_range(0.9, 1.1), 3.0)
	else:
		# Darker the more it is hurt.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = WOOD.darkened(0.45 * (1.0 - _health[li][pi] / PIECE_HEALTH))
		mat.roughness = 0.9
		mesh.material_override = mat


func _break_piece(li: int, pi: int) -> void:
	var piece: Array = _pieces[li][pi]
	(piece[0] as MeshInstance3D).visible = false
	(piece[1] as CollisionShape3D).set_deferred(&"disabled", true)


func _piece_at(li: int, p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for pi in (_pieces[li] as Array).size():
		if _health[li][pi] <= 0.0:
			continue
		var r: Rect2 = _pieces[li][pi][2]
		var d := r.get_center().distance_squared_to(p)
		if r.grow(0.02).has_point(p):
			return pi
		if d < best_d:
			best_d = d
			best = pi
	return best if best_d < PIECE * PIECE else -1


func _splinters(pos: Vector3, amount: int) -> void:
	if NetworkManager.is_dedicated() or not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3(0, 0.5, 1)
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.12, 0.02)
	mesh.material = _material
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.top_level = true
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


# -----------------------------------------------------------------------------
# Late joiners
# -----------------------------------------------------------------------------

func send_state_to(peer_id: int) -> void:
	if is_inside_tree():
		_state.rpc_id(peer_id, open_side, _health)


@rpc("authority", "call_remote", "reliable")
func _state(side: int, health: Array) -> void:
	set_open(side, true)
	for li in mini(health.size(), _health.size()):
		for pi in mini((health[li] as Array).size(), (_health[li] as Array).size()):
			_health[li][pi] = health[li][pi]
			if _health[li][pi] <= 0.0:
				_break_piece(li, pi)
