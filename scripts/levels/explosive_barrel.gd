class_name ExplosiveBarrel
extends Node3D
## A red oil drum that blows up (placed by tools/greybox.py: Map.barrel).
## Bullets wear it down (HEALTH); when it goes it explodes like a small HE
## grenade: the fireball and bang (GrenadeFx.explosion), damage to everyone
## within RADIUS that the blast can see — credited to whoever shot it — and
## it shatters glass, splinters doors and sets off other barrels nearby (a
## short chain delay). An HE grenade sets it off too. It comes back at the
## start of every Bomb Defusal round, or RESPAWN_TIME later in other modes.
##
## Server-authoritative like Door and GlassPane; late joiners get the state
## (Door.NET_GROUP).

const GROUP := &"explosive_barrel"
const MODEL := "res://assets/props/explosive_barrel/explosive_barrel.glb"
const HEALTH := 40.0
const RADIUS := 5.0
const DAMAGE := 110.0
const ARMOR_PENETRATION := 0.5
const CHAIN_DELAY := 0.18
const RESPAWN_TIME := 45.0
const HEIGHT := 0.9
const BARREL_RADIUS := 0.3

var exploded: bool = false
var _hp := HEALTH
var _by: Node = null
var _body: StaticBody3D
var _model: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Door.NET_GROUP)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta(&"breakable", self)
	add_child(_body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BARREL_RADIUS
	cyl.height = HEIGHT
	shape.shape = cyl
	shape.position.y = HEIGHT * 0.5
	_body.add_child(shape)
	if not NetworkManager.is_dedicated():
		_model = _build_model()
		_body.add_child(_model)
	if Match.bomb and not Match.bomb.round_started.is_connected(_on_round_started):
		Match.bomb.round_started.connect(_on_round_started)


func _exit_tree() -> void:
	if Match.bomb and Match.bomb.round_started.is_connected(_on_round_started):
		Match.bomb.round_started.disconnect(_on_round_started)


## The real drum (Poly Haven Barrel_01), or a red cylinder if it is missing.
func _build_model() -> Node3D:
	if ResourceLoader.exists(MODEL):
		var m := (load(MODEL) as PackedScene).instantiate() as Node3D
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return m
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = BARREL_RADIUS
	mesh.bottom_radius = BARREL_RADIUS
	mesh.height = HEIGHT
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.08, 0.05)
	mat.roughness = 0.6
	mesh.material = mat
	mi.mesh = mesh
	mi.position.y = HEIGHT * 0.5
	return mi


## Server: a bullet hit it (`by` = the shooter, for the kill credit).
func server_hit(_body_node: Node, _point: Vector3, damage: float, by: Node = null) -> void:
	if not multiplayer.is_server() or exploded:
		return
	_hp -= damage
	if by:
		_by = by
	if _hp <= 0.0:
		server_explode(_by)


## Server: an explosion within `radius` (HE, another barrel) sets it off.
func server_blast(pos: Vector3, radius: float, damage: float, by: Node = null) -> void:
	if not multiplayer.is_server() or exploded or damage <= 0.0:
		return
	if global_position.distance_to(pos) > radius + BARREL_RADIUS:
		return
	if by:
		_by = by
	get_tree().create_timer(CHAIN_DELAY).timeout.connect(_chain, CONNECT_ONE_SHOT)


func _chain() -> void:
	server_explode(_by)


## Server: blow up now.
func server_explode(by: Node = null) -> void:
	if not multiplayer.is_server() or exploded or not is_inside_tree():
		return
	_set_exploded(true, true)
	NetworkManager.send_to_ready(self, &"_client_explode", [])
	var center := global_position + Vector3.UP * (HEIGHT * 0.6)
	_blast_players(center, by)
	blast_breakables(get_tree(), center, RADIUS, DAMAGE, by)
	if Match.mode != GameConfig.Mode.BOMB:
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(server_reset, CONNECT_ONE_SHOT)


## Server: damage to everyone in range that the blast can see (like HE).
func _blast_players(center: Vector3, by: Node) -> void:
	var space := get_world_3d().direct_space_state
	var shooter := by as PlayerController
	for node in get_tree().get_nodes_in_group(Health.NET_GROUP):
		var health := node as Health
		var target := health.get_parent() as Node3D
		if health.is_dead or target == null:
			continue
		var victim := target as PlayerController
		if victim and shooter and Match.shields(shooter.peer_id, victim.peer_id):
			continue
		var best := INF
		for h: float in [0.3, 1.0, 1.5]: # feet, chest, head
			var point := target.global_position + Vector3.UP * h
			var d := center.distance_to(point)
			if d < best and d < RADIUS and _reaches(space, center, point):
				best = d
		if best < RADIUS:
			health.take_damage(DAMAGE * (1.0 - best / RADIUS), shooter, false, "Explosive barrel",
				ARMOR_PENETRATION, true)


## True if nothing solid but this barrel is between the blast and `point`.
func _reaches(space: PhysicsDirectSpaceState3D, from: Vector3, point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, point, 1, [_body.get_rid()])
	return space.intersect_ray(q).is_empty()


## Server: glass, doors and other barrels round an explosion at `pos`.
static func blast_breakables(tree: SceneTree, pos: Vector3, radius: float, damage: float, by: Node = null) -> void:
	for pane in tree.get_nodes_in_group(GlassPane.GROUP):
		(pane as GlassPane).server_blast(pos, radius, damage)
	if damage > 0.0:
		for door in tree.get_nodes_in_group(Door.GROUP):
			if (door as Node3D).global_position.distance_to(pos) < radius + 2.0:
				(door as Door).server_blast(pos, radius * 0.6, damage)
		for barrel in tree.get_nodes_in_group(GROUP):
			(barrel as ExplosiveBarrel).server_blast(pos, radius, damage, by)


## Server: the barrel is back (new round, or RESPAWN_TIME after it blew).
func server_reset() -> void:
	if not multiplayer.is_server() or not exploded or not is_inside_tree():
		return
	_set_exploded(false, false)
	NetworkManager.send_to_ready(self, &"_client_reset", [])


func _on_round_started(_round_number: int) -> void:
	if multiplayer.is_server():
		server_reset()


@rpc("authority", "call_remote", "reliable")
func _client_explode() -> void:
	_set_exploded(true, true)


@rpc("authority", "call_remote", "reliable")
func _client_reset() -> void:
	_set_exploded(false, false)


func _set_exploded(on: bool, with_effect: bool) -> void:
	exploded = on
	_body.visible = not on
	for c in _body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred(&"disabled", on)
	if on:
		if with_effect and is_inside_tree():
			GrenadeFx.explosion(get_parent(), global_position + Vector3.UP * 0.3)
	else:
		_hp = HEALTH
		_by = null


func send_state_to(peer_id: int) -> void:
	if is_inside_tree():
		_state.rpc_id(peer_id, exploded)


@rpc("authority", "call_remote", "reliable")
func _state(is_exploded: bool) -> void:
	if is_exploded != exploded:
		_set_exploded(is_exploded, false)
