class_name Throwables
extends Node
## Grenades a player carries: one HE grenade and one Molotov per life (per
## round in Bomb Defusal). Quick-throw — G throws the HE, Q the Molotov —
## without switching away from the gun.
##
## Networking: the owner asks the server to throw (origin + velocity); the
## server checks the count, clamps the throw and tells every peer to spawn the
## same projectile, which each peer simulates itself. Only the server decides
## when and where it goes off (GrenadeProjectile), then broadcasts that spot,
## so the damage (server) and the effects (everyone) happen in one place.
## Created by PlayerController._ready, so the node path
## (/root/<Map>/Players/<peer_id>/Throwables) is the same on every peer.

signal changed

enum Kind { HE, MOLOTOV }

const NAMES := { Kind.HE: "HE Grenade", Kind.MOLOTOV: "Molotov" }
const SHORT_NAMES := { Kind.HE: "HE", Kind.MOLOTOV: "Molotov" }
const ACTIONS := { Kind.HE: &"throw_grenade", Kind.MOLOTOV: &"throw_molotov" }
const START_COUNT := 1
## Throw speed (m/s) along the view, plus a little lift and some of the
## player's own speed.
const THROW_SPEED := 16.0
const THROW_LIFT := 2.0
const INHERIT_VELOCITY := 0.5
## Seconds between two throws.
const COOLDOWN := 0.6
## HE grenade: fuse, blast radius, damage at the centre (falls off linearly),
## armour penetration.
const HE_FUSE := 1.6
const HE_RADIUS := 6.0
const HE_DAMAGE := 98.0
const HE_ARMOR_PENETRATION := 0.5

## kind -> grenades left.
var counts := { Kind.HE: START_COUNT, Kind.MOLOTOV: START_COUNT }

var _player: PlayerController
var _cooldown := 0.0
var _next_id := 0
## Projectiles in flight: id -> GrenadeProjectile.
var _live: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as PlayerController


func _process(delta: float) -> void:
	_cooldown -= delta


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not _player.is_local or not _player.input_enabled:
		return
	for kind: int in ACTIONS:
		if InputMap.has_action(ACTIONS[kind]) and event.is_action_pressed(ACTIONS[kind]):
			throw(kind)
			get_viewport().set_input_as_handled()
			return


## Refill on (re)spawn — every peer does this, so no RPC is needed.
func refill() -> void:
	counts = { Kind.HE: START_COUNT, Kind.MOLOTOV: START_COUNT }
	changed.emit()


func can_throw(kind: int) -> bool:
	return counts.get(kind, 0) > 0 and _cooldown <= 0.0 and not _player.health.is_dead and Match.can_shoot()


## Local player: throw `kind` where the camera looks. Returns false if not allowed.
func throw(kind: int) -> bool:
	if not can_throw(kind):
		return false
	_cooldown = COOLDOWN
	var cam := _player.camera
	var dir := -cam.global_basis.z
	var origin := cam.global_position + dir * 0.4 + cam.global_basis.x * 0.15 - cam.global_basis.y * 0.1
	var vel := dir * THROW_SPEED + Vector3.UP * THROW_LIFT + _player.velocity * INHERIT_VELOCITY
	Audio.play_local(&"throw", -6.0, randf_range(0.95, 1.05))
	_player.add_recoil(-1.5, 0.0)
	if multiplayer.is_server():
		_server_throw_checked(kind, origin, vel)
	else:
		counts[kind] -= 1 # predicted; the server's spawn message confirms it
		changed.emit()
		_server_throw.rpc_id(1, kind, origin, vel)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _server_throw(kind: int, origin: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _player.peer_id:
		return
	_server_throw_checked(kind, origin, vel)


## Server: validate, then spawn the projectile everywhere.
func _server_throw_checked(kind: int, origin: Vector3, vel: Vector3) -> void:
	# (A refused throw can be an honest race — the round ended, a refill
	# arrived late — so it is dropped, not reported.)
	if not NAMES.has(kind) or counts.get(kind, 0) <= 0 or _player.health.is_dead or not Match.can_shoot():
		return
	counts[kind] -= 1
	changed.emit()
	var eye := _player.global_position + Vector3.UP * (_player.current_height() - _player.eye_offset)
	if origin.distance_to(eye) > 1.5:
		origin = eye
	var max_speed := THROW_SPEED + THROW_LIFT + PlayerNetSync.MAX_SPEED * INHERIT_VELOCITY + 1.0
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	_next_id += 1
	_spawn(_next_id, kind, origin, vel)
	NetworkManager.send_to_ready(self, &"_client_spawn", [_next_id, kind, origin, vel, counts[kind]])


@rpc("any_peer", "call_remote", "reliable")
func _client_spawn(id: int, kind: int, origin: Vector3, vel: Vector3, left: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	counts[kind] = left
	changed.emit()
	_spawn(id, kind, origin, vel)
	if not _player.is_local:
		Audio.play_3d(&"throw", origin, -4.0, 20.0, randf_range(0.95, 1.05), 3.0)


func _spawn(id: int, kind: int, origin: Vector3, vel: Vector3) -> void:
	var p := GrenadeProjectile.new()
	p.kind = kind
	p.thrower = _player
	p.throwables = self
	p.projectile_id = id
	p.name = "Grenade_%d_%d" % [_player.peer_id, id]
	_world_root().add_child(p)
	p.launch(origin, vel)
	_live[id] = p


## Server: projectile `id` went off at `pos`.
func server_detonate(id: int, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var p: GrenadeProjectile = _live.get(id)
	var kind := p.kind if p else Kind.HE
	_detonate(id, kind, pos)
	NetworkManager.send_to_ready(self, &"_client_detonate", [id, kind, pos])
	if kind == Kind.HE:
		_server_blast(pos)


@rpc("any_peer", "call_remote", "reliable")
func _client_detonate(id: int, kind: int, pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_detonate(id, kind, pos)


## Everyone: remove the projectile and show the effect (and, for the
## Molotov, start the fire — it only burns anyone on the server).
func _detonate(id: int, kind: int, pos: Vector3) -> void:
	var p: GrenadeProjectile = _live.get(id)
	_live.erase(id)
	if is_instance_valid(p):
		p.queue_free()
	if kind == Kind.HE:
		GrenadeFx.explosion(_world_root(), pos)
	else:
		var fire := FireZone.new()
		fire.thrower = _player
		fire.name = "Fire_%d_%d" % [_player.peer_id, id]
		_world_root().add_child(fire)
		fire.ignite(pos)


## Server: HE damage to everyone in range that the blast can see.
func _server_blast(pos: Vector3) -> void:
	var space := _player.get_world_3d().direct_space_state
	var center := pos + Vector3.UP * 0.15
	for node in get_tree().get_nodes_in_group(Health.NET_GROUP):
		var health := node as Health
		var target := health.get_parent() as Node3D
		if health.is_dead or target == null:
			continue
		var victim := target as PlayerController
		if victim and victim != _player and Match.is_friendly(_player.peer_id, victim.peer_id):
			continue
		var best := INF
		for h: float in [0.3, 1.0, 1.5]: # feet, chest, head
			var point := target.global_position + Vector3.UP * h
			var d := center.distance_to(point)
			if d < best and d < HE_RADIUS and blast_reaches(space, center, point):
				best = d
		if best < HE_RADIUS:
			var dmg := HE_DAMAGE * (1.0 - best / HE_RADIUS)
			health.take_damage(dmg, _player, false, NAMES[Kind.HE], HE_ARMOR_PENETRATION, true)


## True if nothing solid (world layer) is between the blast and `point`.
static func blast_reaches(space: PhysicsDirectSpaceState3D, from: Vector3, point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, point, 1)
	return space.intersect_ray(q).is_empty()


func _world_root() -> Node:
	var level := _player.get_parent().get_parent() if _player.get_parent() else null
	if level is Level:
		return level
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


## Throw counts as HUD text: "HE 1   Molotov 1".
func hud_text() -> String:
	var parts: PackedStringArray = []
	for kind: int in [Kind.HE, Kind.MOLOTOV]:
		parts.append("%s %d" % [SHORT_NAMES[kind], counts[kind]])
	return "   ".join(parts)
