class_name Weapon
extends Node3D
## Hitscan weapon: firing, spread/bloom, recoil, ammo, reload, ADS and viewmodel motion.
##
## The node itself is the first-person viewmodel. It must be placed under the
## player's camera and is activated by PlayerController.equip_weapon().
##
## Networking: the shooter predicts effects locally (muzzle flash, sound,
## impact) and sends the shot to the server. The server validates it, runs
## LagCompensation.trace() and applies damage; other peers get the effects.

signal fired
signal ammo_changed(in_magazine: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal hit_confirmed(is_kill: bool, is_headshot: bool)

const IMPACT_POOL_SIZE := 32
## World (1) + hitbox (3) layers.
const HIT_MASK := (1 << 0) | (1 << 2)

@export var data: WeaponData
@export var muzzle: Marker3D
@export var muzzle_flash: Node3D
## Viewmodel offset while aiming down sights (hip offset is the scene position).
@export var ads_position: Vector3 = Vector3(0.0, -0.075, -0.3)
@export var fire_sound: AudioStream
@export var dry_fire_sound: AudioStream
@export var reload_sound: AudioStream

var ammo_in_magazine: int
var ammo_reserve: int
var is_reloading: bool = false
var is_aiming: bool = false
## 0 = hip, 1 = fully aimed. Used for FOV, spread and viewmodel position.
var ads_blend: float = 0.0
## Current total spread in degrees (read by the HUD crosshair).
var current_spread: float = 0.0

var _player: PlayerController
var _camera: Camera3D
var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _bloom: float = 0.0
var _hip_position: Vector3
var _kick: float = 0.0
var _flash_timer: float = 0.0
var _impacts: Array[MeshInstance3D] = []
var _impact_index: int = 0
var _audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _viewmodel_meshes: Array[Node] = []
var _server_last_shot: float = -1.0


func _ready() -> void:
	_hip_position = position
	ammo_in_magazine = data.magazine_size
	ammo_reserve = data.starting_reserve
	if muzzle_flash:
		muzzle_flash.visible = false
	if fire_sound == null:
		fire_sound = ProceduralSfx.noise_burst(0.25, 22.0, 0.35)
	if dry_fire_sound == null:
		dry_fire_sound = ProceduralSfx.click(1400.0)
	if reload_sound == null:
		reload_sound = ProceduralSfx.click(600.0, 0.08)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.max_polyphony = 4
	add_child(_audio)
	_viewmodel_meshes = find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return muzzle_flash == null or not muzzle_flash.is_ancestor_of(n))
	_build_impact_pool()


func equip(player: PlayerController, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	visible = true
	set_physics_process(true)
	# Remote players show a third-person gun instead of the viewmodel.
	for mesh in _viewmodel_meshes:
		mesh.visible = player.is_local
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)


func unequip() -> void:
	is_aiming = false
	is_reloading = false
	ads_blend = 0.0
	visible = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_bloom = move_toward(_bloom, 0.0, data.bloom_recovery * delta)
	_update_flash(delta)
	if not _player.is_local:
		return

	var can_act := _player.input_enabled and not _player.health.is_dead and Match.can_shoot()
	is_aiming = can_act and Input.is_action_pressed("aim") and not is_reloading and not _player.is_sprinting
	ads_blend = move_toward(ads_blend, 1.0 if is_aiming else 0.0, delta / maxf(data.ads_time, 0.01))

	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()

	if can_act:
		var trigger := Input.is_action_pressed("shoot") if data.automatic \
			else Input.is_action_just_pressed("shoot")
		if trigger:
			try_fire()
		if Input.is_action_just_pressed("reload"):
			reload()

	current_spread = _compute_spread()
	_update_viewmodel(delta)


## Fires one shot if possible. Returns true if a shot was fired.
func try_fire() -> bool:
	if _cooldown > 0.0 or is_reloading or _player.is_sprinting:
		return false
	if ammo_in_magazine <= 0:
		if Input.is_action_just_pressed("shoot"):
			_play(dry_fire_sound)
		if ammo_reserve > 0:
			reload()
		return false

	ammo_in_magazine -= 1
	_cooldown = 60.0 / data.fire_rate
	_fire_ray()
	_bloom = minf(_bloom + data.spread_per_shot, data.max_bloom)
	_kick = 1.0

	var recoil_mult := lerpf(1.0, data.ads_recoil_multiplier, ads_blend)
	_player.add_recoil(
		data.recoil_pitch * _rng.randf_range(0.8, 1.2) * recoil_mult,
		_rng.randf_range(-data.recoil_yaw, data.recoil_yaw) * recoil_mult)

	_show_muzzle_flash()
	_play(fire_sound, _rng.randf_range(0.95, 1.05))
	fired.emit()
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)
	return true


func reload() -> void:
	if is_reloading or ammo_in_magazine >= data.magazine_size or ammo_reserve <= 0:
		return
	is_reloading = true
	_reload_timer = data.reload_time
	_play(reload_sound)
	reload_started.emit(data.reload_time)


## Reload progress 0..1 (0 when not reloading).
func get_reload_progress() -> float:
	return 1.0 - _reload_timer / data.reload_time if is_reloading else 0.0


## Full magazine and reserve (on respawn).
func refill_ammo() -> void:
	ammo_in_magazine = data.magazine_size
	ammo_reserve = data.starting_reserve
	is_reloading = false
	_bloom = 0.0
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)


## True while looking through a sniper scope (HUD shows the overlay).
func is_scoped() -> bool:
	return data.scoped and ads_blend > 0.85


func add_reserve_ammo(amount: int) -> void:
	ammo_reserve += amount
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _finish_reload() -> void:
	var needed := data.magazine_size - ammo_in_magazine
	var taken := mini(needed, ammo_reserve)
	ammo_in_magazine += taken
	ammo_reserve -= taken
	is_reloading = false
	reload_finished.emit()
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)


func _compute_spread() -> float:
	var spread := lerpf(data.hip_spread, data.ads_spread, ads_blend) + _bloom
	if _player:
		var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
		spread += data.moving_spread * clampf(horizontal / _player.walk_speed, 0.0, 1.5) * (1.0 - ads_blend * 0.7)
		if not _player.is_on_floor():
			spread += data.air_spread
	return spread


func _fire_ray() -> void:
	var from := _camera.global_position
	var forward := -_camera.global_basis.z
	var right := _camera.global_basis.x
	var up := _camera.global_basis.y
	# One random direction inside the spread cone per pellet.
	var dirs := PackedVector3Array()
	for i in data.pellets:
		var angle := deg_to_rad(current_spread) * sqrt(_rng.randf())
		var around := _rng.randf() * TAU
		dirs.append(forward.rotated(right, angle * sin(around)).rotated(up, angle * cos(around)).normalized())

	if multiplayer.is_server():
		# Offline / host: we are the authority.
		_server_process_shot(from, dirs, NetworkManager.server_time())
	else:
		# Client: predict the impacts now, let the server decide the damage.
		# Remote players are drawn INTERPOLATION_DELAY in the past — tell the
		# server which moment we were looking at.
		var render_time := NetworkManager.server_time() - NetworkManager.INTERPOLATION_DELAY
		var exclude: Array[RID] = [_player.get_rid()]
		for hb: Hitbox in _player.hitboxes:
			exclude.append(hb.get_rid())
		var space := get_world_3d().direct_space_state
		for dir in dirs:
			var query := PhysicsRayQueryParameters3D.create(from, from + dir * data.max_range, HIT_MASK, exclude)
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				_spawn_impact(hit.position, hit.normal)
		_server_fire.rpc_id(1, render_time, from, dirs)


## Server: validate a client's shot.
@rpc("any_peer", "call_remote", "reliable")
func _server_fire(render_time: float, origin: Vector3, dirs: PackedVector3Array) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _player.peer_id:
		return
	if _player.health.is_dead or _player.current_weapon != self or dirs.is_empty():
		return
	var now := NetworkManager.server_time()
	# Fire-rate check (20% tolerance for network jitter).
	if _server_last_shot >= 0.0 and now - _server_last_shot < 60.0 / data.fire_rate * 0.8:
		return
	_server_last_shot = now
	# The shot must come from roughly where the server thinks the head is.
	var eye := _player.global_position + Vector3.UP * (_player.current_height() - _player.eye_offset)
	if origin.distance_to(eye) > 2.0:
		origin = eye
	render_time = clampf(render_time, now - NetworkManager.MAX_REWIND, now)
	# No more pellets than the weapon has, all within a sane cone of the first.
	var max_cone := deg_to_rad(data.hip_spread + data.max_bloom + data.moving_spread * 1.5 + data.air_spread) * 1.5
	var checked := PackedVector3Array()
	for i in mini(dirs.size(), data.pellets):
		var d := dirs[i].normalized()
		if i > 0 and d.angle_to(checked[0]) > max_cone * 2.0:
			continue
		checked.append(d)
	_server_process_shot(origin, checked, render_time)


## Server: trace every pellet with lag compensation, apply damage, broadcast effects.
func _server_process_shot(origin: Vector3, dirs: PackedVector3Array, render_time: float) -> void:
	# Teammates are not hit — bullets pass through them.
	var players: Array = get_tree().get_nodes_in_group(&"player")
	var teammates: Array = players.filter(
		func(p: PlayerController) -> bool: return p != _player and Match.is_friendly(_player.peer_id, p.peer_id))
	var space := get_world_3d().direct_space_state
	var hit_positions := PackedVector3Array()
	var hit_normals := PackedVector3Array()
	var any_kill := false
	var any_head := false
	var any_hit := false
	for dir in dirs:
		var hit := LagCompensation.trace(space, origin, dir, data.max_range, _player, players, render_time, teammates)
		if hit.is_empty():
			continue
		hit_positions.append(hit.position)
		hit_normals.append(hit.normal)
		if _player.is_local:
			_spawn_impact(hit.position, hit.normal)
		var hitbox: Hitbox = hit.get("hitbox")
		if hitbox == null or not Match.can_shoot():
			continue
		var falloff := remap(hit.distance, data.falloff_start, data.max_range, 1.0, data.min_damage_multiplier)
		var damage := data.damage * clampf(falloff, data.min_damage_multiplier, 1.0)
		if hitbox.is_head:
			# The weapon decides the headshot multiplier; cancel the hitbox's own one.
			damage *= data.headshot_multiplier / maxf(hitbox.damage_multiplier, 0.001)
		any_hit = true
		any_head = any_head or hitbox.is_head
		any_kill = hitbox.apply_hit(damage, _player) or any_kill

	if any_hit:
		if _player.is_local:
			hit_confirmed.emit(any_kill, any_head)
		else:
			_client_hit_confirmed.rpc_id(_player.peer_id, any_kill, any_head)

	# Effects for everyone except the shooter (who already predicted them).
	if not _player.is_local and not NetworkManager.is_dedicated():
		_play_remote_fx(hit_positions, hit_normals)
	NetworkManager.send_to_ready(self, &"_remote_fire_fx", [hit_positions, hit_normals], [_player.peer_id])


@rpc("any_peer", "call_remote", "reliable")
func _client_hit_confirmed(killed: bool, is_head: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		hit_confirmed.emit(killed, is_head)


@rpc("any_peer", "call_remote", "unreliable")
func _remote_fire_fx(hit_positions: PackedVector3Array, hit_normals: PackedVector3Array) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_play_remote_fx(hit_positions, hit_normals)


func _play_remote_fx(hit_positions: PackedVector3Array, hit_normals: PackedVector3Array) -> void:
	_show_muzzle_flash()
	_play(fire_sound, _rng.randf_range(0.95, 1.05))
	for i in mini(hit_positions.size(), hit_normals.size()):
		_spawn_impact(hit_positions[i], hit_normals[i])


func _show_muzzle_flash() -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.rotation.z = _rng.randf() * TAU
		_flash_timer = 0.04


func _update_viewmodel(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 12.0)
	var target := _hip_position.lerp(ads_position, ads_blend)
	target.z += _kick * 0.06
	target.y += _kick * 0.01
	if is_reloading:
		target.y -= 0.12
	# Lower the weapon while sprinting.
	if _player.is_sprinting:
		target += Vector3(-0.05, -0.08, 0.05)
	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	rotation.x = lerpf(rotation.x, _kick * 0.08 + (-0.5 if is_reloading else 0.0), clampf(delta * 14.0, 0.0, 1.0))
	# Looking through a scope: the HUD draws the scope, hide the gun.
	var show_model := not is_scoped()
	if _viewmodel_meshes and _viewmodel_meshes[0].visible != show_model:
		for mesh in _viewmodel_meshes:
			mesh.visible = show_model


func _update_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and muzzle_flash:
			muzzle_flash.visible = false


func _play(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null:
		return
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()


func _build_impact_pool() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	for i in IMPACT_POOL_SIZE:
		var impact := MeshInstance3D.new()
		impact.mesh = mesh
		impact.top_level = true
		impact.visible = false
		impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(impact)
		_impacts.append(impact)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var impact := _impacts[_impact_index]
	_impact_index = (_impact_index + 1) % _impacts.size()
	impact.visible = true
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	impact.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.005)
