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

## World (1) + hitbox (3) layers.
const HIT_MASK := (1 << 0) | (1 << 2)

@export var data: WeaponData
@export var muzzle: Marker3D
@export var muzzle_flash: Node3D
## Viewmodel offset while aiming down sights (hip offset is the scene position).
@export var ads_position: Vector3 = Vector3(0.0, -0.075, -0.3)
## Optional custom sounds; empty = SfxLibrary's "fire_<weapon_id>", "dry_fire"
## and the reload sequence ("mag_out", "mag_in", "bolt").
@export var fire_sound: AudioStream
@export var dry_fire_sound: AudioStream
@export var reload_sound: AudioStream
## Gunfire is heard up to this far (metres).
@export var fire_sound_distance: float = 150.0

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
var _reload_sounds_left: int = 0
var _last_impact_sound_ms: int = 0
var _rng := RandomNumberGenerator.new()
var _viewmodel_meshes: Array[Node] = []
var _server_last_shot: float = -1.0
var _server_reload_done_at: float = 0.0
var _aim_toggled: bool = false


func _ready() -> void:
	_hip_position = position
	ammo_in_magazine = data.magazine_size
	ammo_reserve = data.starting_reserve
	if muzzle_flash:
		muzzle_flash.visible = false
	if WeaponModel.has_model(data.weapon_id) and not has_node(^"Model"):
		var model := MeshInstance3D.new()
		model.name = "Model"
		model.mesh = WeaponModel.get_mesh(data.weapon_id)
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
	_viewmodel_meshes = find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return muzzle_flash == null or not muzzle_flash.is_ancestor_of(n))


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
	_aim_toggled = false
	is_reloading = false
	_reload_sounds_left = 0
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
	var aim_input := Input.is_action_pressed(&"aim")
	if SettingsManager.aim_toggle:
		if can_act and Input.is_action_just_pressed(&"aim"):
			_aim_toggled = not _aim_toggled
		if _player.is_sprinting or not can_act:
			_aim_toggled = false
		aim_input = _aim_toggled
	is_aiming = can_act and aim_input and not is_reloading and not _player.is_sprinting
	ads_blend = move_toward(ads_blend, 1.0 if is_aiming else 0.0, delta / maxf(data.ads_time, 0.01))

	if is_reloading:
		_reload_timer -= delta
		_reload_sound_step()
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
			_play(dry_fire_sound if dry_fire_sound else &"dry_fire", -4.0, 1.0, 10.0)
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
	_play_fire()
	# Kick scaled by the weapon's recoil (sniper hard, SMG light).
	GamepadInput.rumble(0.25, clampf(data.recoil_pitch * 0.15, 0.1, 0.8), 0.08)
	fired.emit()
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)
	return true


func reload() -> void:
	if is_reloading or ammo_in_magazine >= data.magazine_size or ammo_reserve <= 0:
		return
	is_reloading = true
	_reload_timer = data.reload_time
	if reload_sound:
		_play(reload_sound, -4.0, 1.0, 15.0)
		_reload_sounds_left = 0
	else:
		_play(&"mag_out", -4.0, 1.0, 15.0)
		_reload_sounds_left = 2
	reload_started.emit(data.reload_time)
	if not multiplayer.is_server() and NetworkManager.is_online():
		_server_reload.rpc_id(1)


## Server: a client started reloading. The server keeps its own copy of the
## ammo and only refills it after the reload time has really passed.
@rpc("any_peer", "call_remote", "reliable")
func _server_reload() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _player.peer_id:
		return
	if is_reloading or ammo_in_magazine >= data.magazine_size or ammo_reserve <= 0:
		return
	is_reloading = true
	# 10% tolerance for network jitter.
	_server_reload_done_at = NetworkManager.server_time() + data.reload_time * 0.9


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
		NetworkManager.report_violation(_player.peer_id, "fire rate")
		return
	# Server-side ammo: the server's copy of this weapon counts every shot.
	if is_reloading:
		if now < _server_reload_done_at:
			NetworkManager.report_violation(_player.peer_id, "fired while reloading")
			return
		_finish_reload()
	if ammo_in_magazine <= 0:
		NetworkManager.report_violation(_player.peer_id, "fired with an empty magazine")
		return
	ammo_in_magazine -= 1
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
	_play_fire()
	for i in mini(hit_positions.size(), hit_normals.size()):
		_spawn_impact(hit_positions[i], hit_normals[i])
	# Enemy bullets flying past your head crack.
	if _player and not Match.is_friendly(_player.peer_id, multiplayer.get_unique_id()):
		for i in mini(hit_positions.size(), 3):
			Audio.bullet_passed(global_position, hit_positions[i])


func _show_muzzle_flash() -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		# The flash light is optional on low-end presets (the flash quad stays).
		var light := muzzle_flash.get_node_or_null("FlashLight") as Light3D
		if light:
			light.visible = SettingsManager.graphics.dynamic_lights
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


func _play_fire() -> void:
	var sound: Variant = fire_sound if fire_sound else StringName("fire_" + data.weapon_id)
	_play(sound, 0.0, _rng.randf_range(0.95, 1.05), fire_sound_distance, 12.0)


## Weapon sounds come from the weapon (the local player's is at the camera,
## so it is heard at full volume and centred; others' are positional).
func _play(sound: Variant, volume_db: float = 0.0, pitch: float = 1.0,
		max_distance: float = 20.0, unit_size: float = 6.0) -> void:
	Audio.play_3d(sound, global_position, volume_db, max_distance, pitch, unit_size)


## Magazine in at 55 % of the reload, bolt / slide at 85 %.
func _reload_sound_step() -> void:
	if _reload_sounds_left <= 0:
		return
	var progress := 1.0 - _reload_timer / maxf(data.reload_time, 0.01)
	if _reload_sounds_left == 2 and progress >= 0.55:
		_reload_sounds_left = 1
		_play(&"mag_in", -4.0, 1.0, 15.0)
	elif _reload_sounds_left == 1 and progress >= 0.85:
		_reload_sounds_left = 0
		_play(&"bolt", -4.0, 1.0, 15.0)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	ImpactDecals.get_for(self).add(pos, normal)
	# One impact sound per shot (a shotgun blast is 13 pellets).
	var now := Time.get_ticks_msec()
	if now - _last_impact_sound_ms > 40:
		_last_impact_sound_ms = now
		Audio.play_3d(&"impact", pos, -8.0, 25.0, _rng.randf_range(0.85, 1.15), 3.0)
