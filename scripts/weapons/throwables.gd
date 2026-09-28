class_name Throwables
extends Node
## Grenades a player carries, refilled every life: one HE grenade, one
## Molotov, two flashbangs and one smoke. In Bomb Defusal they are bought
## instead (Economy) and kept by survivors into the next round.
## Key 4 takes one in hand — the gun is put away — then left click throws
## it (right click: a short underhand lob) and the gun comes back; 1 / 2 / 3
## or the wheel put it away. Holding 4 opens a grenade wheel: move the mouse
## (or right stick) towards one and let go (or click) to take it; a quick
## tap takes the next type. G quick-throws the one in hand, or the HE
## grenade, without the extra key press. While one is in hand its flight is
## drawn ahead of time (GrenadeArc) with a ring where it will land.
##
## Networking: the owner asks the server to throw (origin + velocity); the
## server checks the count, clamps the throw and tells every peer to spawn the
## same projectile, which each peer simulates itself. Only the server decides
## when and where it goes off (GrenadeProjectile), then broadcasts that spot,
## so the damage (server) and the effects (everyone) happen in one place.
## Created by PlayerController._ready, so the node path
## (/root/<Map>/Players/<peer_id>/Throwables) is the same on every peer.

signal changed

enum Kind { HE, MOLOTOV, FLASH, SMOKE }

## HUD order.
const ORDER: Array[int] = [Kind.HE, Kind.FLASH, Kind.SMOKE, Kind.MOLOTOV]
const NAMES := { Kind.HE: "HE Grenade", Kind.MOLOTOV: "Molotov", Kind.FLASH: "Flashbang", Kind.SMOKE: "Smoke Grenade" }
const SHORT_NAMES := { Kind.HE: "HE", Kind.MOLOTOV: "Molotov", Kind.FLASH: "Flash", Kind.SMOKE: "Smoke" }
## The grenade slot key and the quick-throw key.
const HOLD_ACTION := &"weapon_4"
const QUICK_ACTION := &"throw_grenade"
## Right click: underhand lob at this share of the speed.
const LOB_STRENGTH := 0.45
## Grenades of each kind at spawn.
const START_COUNTS := { Kind.HE: 1, Kind.MOLOTOV: 1, Kind.FLASH: 2, Kind.SMOKE: 1 }
## Fuse (s) for the kinds that go off on a timer (the Molotov breaks on impact).
const FUSES := { Kind.HE: 1.6, Kind.FLASH: 1.5, Kind.SMOKE: 1.8 }
## Throw speed (m/s) along the view, plus a little lift and some of the
## player's own speed.
const THROW_SPEED := 16.0
const THROW_LIFT := 2.0
const INHERIT_VELOCITY := 0.5
## Seconds between two throws.
const COOLDOWN := 0.6
## HE grenade: fuse, blast radius, damage at the centre (falls off linearly),
## armour penetration.
const HE_FUSE := 1.6 # = FUSES[Kind.HE]
const HE_RADIUS := 6.0
const HE_DAMAGE := 98.0
const HE_ARMOR_PENETRATION := 0.5

## Grenade wheel: pointing this far (px of mouse movement) picks a segment.
const WHEEL_PICK := 40.0
## Held this long (s), 4 opens the wheel on screen; a shorter tap cycles.
const WHEEL_DELAY := 0.15

## kind -> grenades left.
var counts := START_COUNTS.duplicate()
## The grenade in hand (Kind) or -1.
var held_kind: int = -1
## Grenade wheel (local player): open while 4 is held; the kind pointed at (or -1).
var wheel_open: bool = false
var wheel_choice: int = -1
var _wheel_time := 0.0
var _wheel_vec := Vector2.ZERO
## The predicted flight while a grenade is in hand (local player only).
var arc: GrenadeArc

var _player: PlayerController
var _cooldown := 0.0
var _next_id := 0
## Projectiles in flight: id -> GrenadeProjectile.
var _live: Dictionary = {}
var _hand_model: Node3D


func _ready() -> void:
	_player = get_parent() as PlayerController
	# Same rule on every peer: Bomb Defusal players buy their grenades.
	if Match.mode == GameConfig.Mode.BOMB:
		_set_counts([0, 0, 0, 0])


func _process(delta: float) -> void:
	_cooldown -= delta
	if _player == null or not _player.is_local:
		return
	if wheel_open:
		_update_wheel(delta)
	_update_arc()
	if held_kind < 0 or wheel_open:
		return
	if not _player.input_enabled or _player.health.is_dead:
		return
	if Input.is_action_just_pressed(&"shoot"):
		_throw_held(1.0)
	elif Input.is_action_just_pressed(&"aim"):
		_throw_held(LOB_STRENGTH)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not _player.is_local:
		return
	if wheel_open:
		if event is InputEventMouseMotion:
			_point_wheel((event as InputEventMouseMotion).relative)
		elif event.is_action_released(HOLD_ACTION) or event.is_action_pressed(&"shoot"):
			close_wheel(true)
			get_viewport().set_input_as_handled()
		return
	if not _player.input_enabled:
		return
	if event.is_action_pressed(HOLD_ACTION) and not event.is_echo():
		open_wheel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(QUICK_ACTION):
		var kind := held_kind if held_kind >= 0 else Kind.HE
		if kind >= 0 and throw(kind):
			put_away()
		get_viewport().set_input_as_handled()


func is_holding() -> bool:
	return held_kind >= 0


## 4 pressed: start the wheel (shown after WHEEL_DELAY). False if there are no grenades.
func open_wheel() -> bool:
	if _player.health.is_dead or _first_available() < 0:
		return false
	wheel_open = true
	wheel_choice = -1
	_wheel_time = 0.0
	_wheel_vec = Vector2.ZERO
	_player.grenade_wheel_open = true
	return true


## 4 released (or a click): take the grenade pointed at; nothing pointed at
## = a tap, the next grenade (`pick` false: just close).
func close_wheel(pick: bool) -> void:
	if not wheel_open:
		return
	wheel_open = false
	_player.grenade_wheel_open = false
	if not pick or _player.health.is_dead:
		return
	if wheel_choice >= 0 and counts.get(wheel_choice, 0) > 0:
		if wheel_choice != held_kind:
			_hold(wheel_choice)
	else:
		hold_next()


## Whether the wheel is open long enough to be drawn.
func wheel_visible() -> bool:
	return wheel_open and (_wheel_time >= WHEEL_DELAY or wheel_choice >= 0)


## Wheel segments: ORDER[0] at the top, then clockwise.
static func wheel_kind_at(dir: Vector2) -> int:
	if dir.length() < 0.001:
		return -1
	var a := fposmod(atan2(dir.x, -dir.y) + PI / ORDER.size(), TAU)
	return ORDER[int(a / (TAU / ORDER.size())) % ORDER.size()]


func _point_wheel(motion: Vector2) -> void:
	_wheel_vec = (_wheel_vec + motion).limit_length(WHEEL_PICK * 3.0)
	if _wheel_vec.length() >= WHEEL_PICK:
		wheel_choice = wheel_kind_at(_wheel_vec)


func _update_wheel(delta: float) -> void:
	_wheel_time += delta
	if _player.health.is_dead or not _player.input_enabled:
		close_wheel(false)
		return
	if not Input.is_action_pressed(HOLD_ACTION):
		close_wheel(true) # the release was missed (e.g. the window lost focus)
		return
	# Controller: the right stick points.
	var stick := GamepadInput.look_vector(SettingsManager.pad_deadzone, 1.0)
	if stick.length() > 0.5:
		wheel_choice = wheel_kind_at(stick)


## Key 4: take a grenade in hand, or switch to the next type you have.
## Returns false if there is none left.
func hold_next() -> bool:
	if _player.health.is_dead:
		return false
	var start := ORDER.find(held_kind) + 1 if held_kind >= 0 else 0
	for i in ORDER.size():
		var kind: int = ORDER[(start + i) % ORDER.size()]
		if counts.get(kind, 0) > 0:
			_hold(kind)
			return true
	return false


## Back to the gun (1 / 2 / 3, the wheel, after a throw, on death).
func put_away() -> void:
	close_wheel(false)
	if held_kind < 0:
		return
	held_kind = -1
	if _hand_model:
		_hand_model.queue_free()
		_hand_model = null
	if _player.current_weapon:
		_player.current_weapon.set_holstered(false)
	changed.emit()


func _hold(kind: int) -> void:
	var switching := held_kind >= 0
	held_kind = kind
	if _player.current_weapon:
		_player.current_weapon.set_holstered(true)
	if _hand_model:
		_hand_model.queue_free()
	_hand_model = GrenadeProjectile.build_model(kind)
	_hand_model.name = "GrenadeInHand"
	_hand_model.position = Vector3(0.2, -0.24, -0.42)
	_hand_model.rotation = Vector3(0.3, 0.4, 0.0)
	_hand_model.scale = Vector3.ONE * 1.4
	_player.camera.add_child(_hand_model)
	if not switching:
		_player.play_equip_sound()
	changed.emit()


func _throw_held(strength: float) -> void:
	var kind := held_kind
	if can_throw(kind) and throw(kind, strength):
		put_away()


func _first_available() -> int:
	for kind: int in ORDER:
		if counts.get(kind, 0) > 0:
			return kind
	return -1


## Refill on (re)spawn — every peer does this, so no RPC is needed.
## `nades` (counts by Kind) is what a Bomb Defusal player carries; without
## it Bomb Defusal starts empty and the other modes full.
func refill(nades: Array = []) -> void:
	if held_kind >= 0:
		put_away()
	if nades.size() == Kind.size():
		_set_counts(nades)
	elif Match.mode == GameConfig.Mode.BOMB:
		_set_counts([0, 0, 0, 0])
	else:
		counts = START_COUNTS.duplicate()
	changed.emit()


## Counts by Kind (HE, Molotov, flash, smoke).
func counts_array() -> Array:
	var result := []
	for kind in Kind.size():
		result.append(counts.get(kind, 0))
	return result


## Server: new counts (bought grenades), sent to every peer.
func server_set_counts(nades: Array) -> void:
	if not multiplayer.is_server():
		return
	_set_counts(nades)
	changed.emit()
	NetworkManager.send_to_ready(self, &"_client_counts", [nades])


@rpc("authority", "call_remote", "reliable")
func _client_counts(nades: Array) -> void:
	_set_counts(nades)
	changed.emit()


func _set_counts(nades: Array) -> void:
	counts = {}
	for kind in Kind.size():
		counts[kind] = clampi(int(nades[kind]) if kind < nades.size() else 0, 0, 9)


func can_throw(kind: int) -> bool:
	return counts.get(kind, 0) > 0 and _cooldown <= 0.0 and not _player.health.is_dead and Match.can_shoot()


## Local player: throw `kind` where the camera looks (`strength` < 1 for a
## lob). Returns false if not allowed.
func throw(kind: int, strength: float = 1.0) -> bool:
	if not can_throw(kind):
		return false
	_cooldown = COOLDOWN
	var launch := throw_launch(strength)
	var origin: Vector3 = launch[0]
	var vel: Vector3 = launch[1]
	Audio.play_local(&"throw", -6.0, randf_range(0.95, 1.05))
	_player.add_recoil(-1.5, 0.0)
	if multiplayer.is_server():
		_server_throw_checked(kind, origin, vel)
	else:
		counts[kind] -= 1 # predicted; the server's spawn message confirms it
		changed.emit()
		_server_throw.rpc_id(1, kind, origin, vel)
	return true


## [origin, velocity] of a throw from where the camera looks.
func throw_launch(strength: float = 1.0) -> Array:
	var cam := _player.camera
	var dir := -cam.global_basis.z
	var origin := cam.global_position + dir * 0.4 + cam.global_basis.x * 0.15 - cam.global_basis.y * 0.1
	var vel := dir * THROW_SPEED * strength + Vector3.UP * THROW_LIFT * strength + _player.velocity * INHERIT_VELOCITY
	return [origin, vel]


## Shows the predicted flight of the grenade in hand (hidden otherwise).
func _update_arc() -> void:
	var show := held_kind >= 0 and not wheel_open and not _player.health.is_dead and SettingsManager.grenade_arc
	if not show:
		if arc:
			arc.visible = false
		return
	if arc == null:
		arc = GrenadeArc.new()
		arc.name = "GrenadeArc"
		add_child(arc)
	var launch := throw_launch(1.0)
	arc.show_path(GrenadeArc.predict(_player.get_world_3d().direct_space_state, launch[0], launch[1], held_kind),
		held_kind)


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


## Everyone: remove the projectile and show the effect. The Molotov's fire
## only burns anyone on the server; each peer works out how blind its own
## player is from a flash; the smoke cloud is the same everywhere.
func _detonate(id: int, kind: int, pos: Vector3) -> void:
	var p: GrenadeProjectile = _live.get(id)
	_live.erase(id)
	if is_instance_valid(p):
		p.queue_free()
	match kind:
		Kind.HE:
			GrenadeFx.explosion(_world_root(), pos)
		Kind.MOLOTOV:
			var fire := FireZone.new()
			fire.thrower = _player
			fire.name = "Fire_%d_%d" % [_player.peer_id, id]
			_world_root().add_child(fire)
			fire.ignite(pos)
		Kind.FLASH:
			GrenadeFx.flash(_world_root(), pos)
		Kind.SMOKE:
			var cloud := SmokeCloud.new()
			cloud.name = "Smoke_%d_%d" % [_player.peer_id, id]
			_world_root().add_child(cloud)
			cloud.start(pos)


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
