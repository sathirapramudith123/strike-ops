class_name PlayerNetSync
extends Node
## Replicates one player's movement and handles server-side respawns.
##
## • Owner (local player): sends its state to the server SEND_RATE times/sec.
## • Server: validates the state (speed check), stamps it with server time,
##   stores it in the history used by lag compensation and relays it to others.
## • Everyone else: buffers snapshots and renders the player
##   INTERPOLATION_DELAY in the past, interpolating between two snapshots.

const SEND_RATE := 30.0
const HISTORY_SECONDS := 1.0
## Max horizontal speed accepted by the server (sprint + slide boost + margin).
const MAX_SPEED := 14.0
## Max upward speed accepted (jump is 5 m/s; margin for ramps + jitter).
const MAX_RISE_SPEED := 12.0
## Seconds of invulnerability after (re)spawning.
const SPAWN_PROTECTION := 1.5

enum Flags { SPRINTING = 1, CROUCHING = 2, SLIDING = 4, AIMING = 8, RELOADING = 16, LEAN_LEFT = 32,
	LEAN_RIGHT = 64, WALKING = 128 }

@onready var player: PlayerController = get_parent()

## Snapshots: { t, pos, yaw, pitch, height, flags } ordered by t (server time).
var _snapshots: Array[Dictionary] = []
var _send_timer: float = 0.0
var _respawn_timer: float = -1.0
var _last_valid_pos: Vector3
var _last_valid_time: float = -1.0


func _ready() -> void:
	# Children are ready before the parent, so player.health isn't set yet.
	(player.get_node("Health") as Health).died.connect(_on_died)


func _physics_process(delta: float) -> void:
	var now := NetworkManager.server_time()
	if player.is_local:
		_send_timer -= delta
		if multiplayer.is_server():
			# Host player: record every tick for lag compensation.
			_push_snapshot(now, player.global_position, player.rotation.y,
				player.head.rotation.x, player.current_height(), _flags())
			if _send_timer <= 0.0:
				_send_timer = 1.0 / SEND_RATE
				NetworkManager.send_to_ready(self, &"_client_state", [now, player.global_position,
					player.rotation.y, player.head.rotation.x, player.current_height(), _flags()])
		elif _send_timer <= 0.0 and NetworkManager.is_online():
			_send_timer = 1.0 / SEND_RATE
			_server_state.rpc_id(1, player.global_position, player.rotation.y,
				player.head.rotation.x, player.current_height(), _flags())
	else:
		_interpolate(now - NetworkManager.INTERPOLATION_DELAY)

	if multiplayer.is_server() and _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer < 0.0:
			_server_respawn()


## Player state at a given server time (for lag compensation).
func get_state_at(t: float) -> Dictionary:
	if _snapshots.is_empty():
		return { "pos": player.global_position, "height": player.current_height() }
	return _sample(t)


## Owner → server when the player falls out of the map.
func report_fell() -> void:
	if multiplayer.is_server():
		player.health.take_damage(99999.0, null)
	else:
		_server_fell.rpc_id(1)


# -----------------------------------------------------------------------------
# RPCs
# -----------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1) # channel 1 = NetworkManager.CHANNEL_STATE
func _server_state(pos: Vector3, yaw: float, pitch: float, height: float, flags: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != player.peer_id:
		return
	if player.health.is_dead:
		return
	var now := NetworkManager.server_time()
	if _last_valid_time >= 0.0:
		var dt := maxf(now - _last_valid_time, 1.0 / SEND_RATE)
		var moved := Vector2(pos.x - _last_valid_pos.x, pos.z - _last_valid_pos.z).length()
		var rise := pos.y - _last_valid_pos.y
		if moved > 1.0 and moved / dt > MAX_SPEED * 1.5:
			# Too fast — reject and snap the owner back.
			NetworkManager.report_violation(player.peer_id, "speed")
			_correct.rpc_id(player.peer_id, _last_valid_pos)
			return
		if rise > 1.0 and rise / dt > MAX_RISE_SPEED:
			# Flying up faster than any jump or ramp allows.
			NetworkManager.report_violation(player.peer_id, "fly")
			_correct.rpc_id(player.peer_id, _last_valid_pos)
			return
	_last_valid_pos = pos
	_last_valid_time = now
	pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	height = clampf(height, player.crouch_height, player.stand_height)
	_push_snapshot(now, pos, yaw, pitch, height, flags)
	NetworkManager.send_to_ready(self, &"_client_state", [now, pos, yaw, pitch, height, flags], [player.peer_id])


@rpc("any_peer", "call_remote", "unreliable_ordered", 1) # channel 1 = NetworkManager.CHANNEL_STATE
func _client_state(t: float, pos: Vector3, yaw: float, pitch: float, height: float, flags: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or player.is_local:
		return
	_push_snapshot(t, pos, yaw, pitch, height, flags)


@rpc("any_peer", "call_remote", "reliable")
func _correct(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1 and player.is_local:
		player.global_position = pos
		player.velocity = Vector3.ZERO


@rpc("any_peer", "call_remote", "reliable")
func _server_fell() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.peer_id:
		player.health.take_damage(99999.0, null)


@rpc("any_peer", "call_remote", "reliable")
func _respawn(xform: Transform3D, primary: String, nades: Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_respawn(xform, primary, nades)


## Server: a primary bought in the buy menu, on every peer.
func server_give_primary(primary: String) -> void:
	if not multiplayer.is_server():
		return
	player.give_primary(primary)
	NetworkManager.send_to_ready(self, &"_client_give_primary", [primary])


@rpc("any_peer", "call_remote", "reliable")
func _client_give_primary(primary: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		player.give_primary(primary)


## Owner → server → everyone: weapon slot changes.
func send_slot(slot: int) -> void:
	if not NetworkManager.is_online():
		return
	if multiplayer.is_server():
		NetworkManager.send_to_ready(self, &"_client_slot", [slot], [player.peer_id])
	else:
		_server_slot.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _server_slot(slot: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != player.peer_id:
		return
	slot = clampi(slot, 0, PlayerController.SLOT_COUNT - 1)
	player._equip_slot(slot)
	player.play_equip_sound()
	NetworkManager.send_to_ready(self, &"_client_slot", [slot], [player.peer_id])


@rpc("any_peer", "call_remote", "reliable")
func _client_slot(slot: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and not player.is_local:
		player._equip_slot(clampi(slot, 0, PlayerController.SLOT_COUNT - 1))
		player.play_equip_sound()


## Server: respawn right now without counting a death (team switch).
func server_force_respawn() -> void:
	if multiplayer.is_server():
		_respawn_timer = -1.0
		_server_respawn()


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _on_died(source: Node) -> void:
	if not multiplayer.is_server() or player.health.silent_death:
		return
	# Bomb Defusal: no respawns during a round (the next round revives everyone).
	if Match.mode != GameConfig.Mode.BOMB:
		_respawn_timer = player.respawn_delay
	var killer := source as PlayerController
	var cause := player.health.last_cause if player.health.last_cause != "" else "Fall"
	var weapon_name := cause
	if killer and killer.current_weapon and cause not in Throwables.NAMES.values():
		weapon_name = killer.current_weapon.data.display_name
	NetworkManager.report_kill(killer.peer_id if killer else -1, player.peer_id,
		weapon_name, player.health.last_hit_headshot)


func _server_respawn() -> void:
	var level := player.get_parent().get_parent() as Level
	var xform := level.next_spawn_transform(player.peer_id) if level else player.global_transform
	var primary: String = NetworkManager.roster.get(player.peer_id, {}).get("primary", player.primary_id)
	var nades := []
	if Match.mode == GameConfig.Mode.BOMB:
		# Bomb Defusal: what the player bought / kept (Economy).
		var gear := Match.economy.gear_for(player.peer_id)
		primary = gear.primary
		nades = gear.nades
		player.health.revive(gear.armor, gear.helmet)
	else:
		player.health.revive()
	# Bomb Defusal has freeze time instead of spawn protection.
	if Match.mode != GameConfig.Mode.BOMB:
		player.health.protect(SPAWN_PROTECTION)
	_apply_respawn(xform, primary, nades)
	NetworkManager.send_to_ready(self, &"_respawn", [xform, primary, nades])


func _apply_respawn(xform: Transform3D, primary: String, nades: Array) -> void:
	_snapshots.clear()
	_last_valid_pos = xform.origin
	_last_valid_time = NetworkManager.server_time()
	player.respawn_at(xform, primary, nades)


func _push_snapshot(t: float, pos: Vector3, yaw: float, pitch: float, height: float, flags: int) -> void:
	if not _snapshots.is_empty() and t <= _snapshots[-1].t:
		return # out of order / duplicate
	_snapshots.append({ "t": t, "pos": pos, "yaw": yaw, "pitch": pitch, "height": height, "flags": flags })
	while _snapshots.size() > 2 and _snapshots[0].t < t - HISTORY_SECONDS:
		_snapshots.pop_front()


func _interpolate(render_t: float) -> void:
	if _snapshots.is_empty():
		return
	var st := _sample(render_t)
	player.apply_remote_state(st.pos, st.yaw, st.pitch, st.height, st.flags)


## Interpolated snapshot at time t (clamped to the buffered range).
func _sample(t: float) -> Dictionary:
	if t <= _snapshots[0].t:
		return _snapshots[0]
	if t >= _snapshots[-1].t:
		return _snapshots[-1]
	var i := _snapshots.size() - 2
	while i > 0 and _snapshots[i].t > t:
		i -= 1
	var a: Dictionary = _snapshots[i]
	var b: Dictionary = _snapshots[i + 1]
	var w := inverse_lerp(a.t, b.t, t)
	return {
		"t": t,
		"pos": (a.pos as Vector3).lerp(b.pos, w),
		"yaw": lerp_angle(a.yaw, b.yaw, w),
		"pitch": lerpf(a.pitch, b.pitch, w),
		"height": lerpf(a.height, b.height, w),
		"flags": b.flags,
	}


func _flags() -> int:
	var f := 0
	if player.is_sprinting: f |= Flags.SPRINTING
	if player.is_crouching: f |= Flags.CROUCHING
	if player.is_sliding: f |= Flags.SLIDING
	if player.current_weapon and player.current_weapon.is_aiming: f |= Flags.AIMING
	if player.current_weapon and player.current_weapon.is_reloading: f |= Flags.RELOADING
	if player.lean < -0.5: f |= Flags.LEAN_LEFT
	if player.lean > 0.5: f |= Flags.LEAN_RIGHT
	if player.is_walking: f |= Flags.WALKING
	return f
