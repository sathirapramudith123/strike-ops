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
## Index into data.fire_modes (B cycles it).
var fire_mode_index: int = 0
## Index into data.zoom_levels while scoped (mouse wheel).
var zoom_index: int = 0
## Put away while a grenade is in hand (Throwables): hidden, can't fire.
var holstered: bool = false

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
## Gun pulled back from a wall right in front (m), see _wall_distance_pull.
var _wall_pull := 0.0
const WALL_MARGIN := 0.08
const MAX_WALL_PULL := 0.45
var _magazine: MeshInstance3D
var _left_arm: MeshInstance3D
var _server_last_shot: float = -1.0
var _server_reload_done_at: float = 0.0
var _aim_toggled: bool = false
var _burst_left: int = 0
## Knife swing, 1 → 0 over SWING_TIME.
var _swing: float = 0.0
const SWING_TIME := 0.35
## Animation profile (WeaponAnim) and its state.
var _anim: Dictionary = {}
var _right_arm: MeshInstance3D
var _cover: MeshInstance3D
var _time := 0.0
var _bob_phase := 0.0
var _look_lag := Vector2.ZERO
var _last_cam_basis := Basis.IDENTITY
var _has_cam_basis := false
var _equip_left := 0.0
var _cycle_left := 0.0
var _cycle_sound := false
var _kick_roll := 0.0
var _left_hand := Vector3.ZERO
var _right_hand := Vector3.ZERO
## Reload bookkeeping: full length, sounds along it, shells loaded so far.
var _reload_total := 0.0
var _cue_index := 0
var _shells_loaded := 0
var _server_reload_start := 0.0


func _ready() -> void:
	_hip_position = position
	_anim = WeaponAnim.profile(data.weapon_id)
	_reload_total = data.reload_time
	ammo_in_magazine = data.magazine_size
	ammo_reserve = data.starting_reserve
	if muzzle_flash:
		muzzle_flash.visible = false
	if WeaponModel.has_model(data.weapon_id) and not has_node(^"Model"):
		# Viewmodel pieces: the gun, its magazine and both arms are separate
		# so the reload can be animated (see _animate_reload).
		_add_part("Model", WeaponModel.get_mesh(data.weapon_id, false))
		_magazine = _add_part("Magazine", WeaponModel.get_magazine_mesh(data.weapon_id))
		_right_arm = _add_part("ArmR", WeaponModel.get_arm_mesh(data.weapon_id, false))
		_left_arm = _add_part("ArmL", WeaponModel.get_arm_mesh(data.weapon_id, true))
		_cover = _add_part("Cover", WeaponModel.get_cover_mesh(data.weapon_id))
		if _cover:
			_cover.position = WeaponModel.COVER_HINGE
		if data.weapon_id == "shotgun" and _magazine:
			_magazine.visible = false # the shell only shows while loading
	# A real gun model has its own muzzle (WeaponModel.REAL_HANDS).
	var h := WeaponModel.hands(data.weapon_id)
	if muzzle and h.has("muzzle"):
		muzzle.position = h.muzzle
	if h.has("ads"):
		ads_position = h.ads
	_viewmodel_meshes = find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return muzzle_flash == null or not muzzle_flash.is_ancestor_of(n))


func _add_part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func equip(player: PlayerController, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	visible = true
	set_physics_process(true)
	# Remote players show a third-person gun instead of the viewmodel.
	for mesh in _viewmodel_meshes:
		mesh.visible = player.is_local
	if player.is_local:
		_apply_arm_look()
		_attach_fp_arms()
		# The raise: from low and tipped down up into the hands.
		_equip_left = float(_anim.equip)
		_has_cam_basis = false
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)


## First-person gloves and sleeves in the player's outfit (CharacterLook).
func _apply_arm_look() -> void:
	if _right_arm == null:
		return
	var look: Dictionary = NetworkManager.look_of(_player.peer_id)
	_right_arm.mesh = WeaponModel.get_arm_mesh(data.weapon_id, false, look)
	if _left_arm:
		_left_arm.mesh = WeaponModel.get_arm_mesh(data.weapon_id, true, look)


## Realistic first-person arms (FPArms, one per camera) instead of the
## code-built ArmR / ArmL meshes — those parts stay and are the arms' targets.
func _attach_fp_arms() -> void:
	if not SettingsManager.graphics.realistic_characters or _right_arm == null or _camera == null:
		return
	var arms := _camera.get_node_or_null(^"FPArms") as FPArms
	if arms == null:
		arms = FPArms.new()
		arms.name = "FPArms"
		_camera.add_child(arms)
	arms.weapon = self
	_right_arm.mesh = null
	if _left_arm:
		_left_arm.mesh = null


func unequip() -> void:
	_inspect_left = 0.0
	_cycle_left = 0.0
	_equip_left = 0.0
	_burst_left = 0
	zoom_index = 0
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
		if _player.is_bot and multiplayer.is_server():
			_bot_process(delta)
		return

	var can_act := _player.input_enabled and not _player.health.is_dead and Match.can_shoot() and not holstered \
		and not _player.grenade_wheel_open
	var aim_input := Input.is_action_pressed(&"aim")
	if SettingsManager.aim_toggle:
		if can_act and Input.is_action_just_pressed(&"aim"):
			_aim_toggled = not _aim_toggled
		if _player.is_sprinting or not can_act:
			_aim_toggled = false
		aim_input = _aim_toggled
	is_aiming = can_act and aim_input and not is_reloading and not _player.is_sprinting and not data.melee
	if not is_aiming:
		zoom_index = 0
	ads_blend = move_toward(ads_blend, 1.0 if is_aiming else 0.0, delta / maxf(data.ads_time, 0.01))

	_tick_reload(delta)

	if can_act:
		_handle_trigger()
		if Input.is_action_just_pressed("reload"):
			reload()
	else:
		_burst_left = 0

	current_spread = _compute_spread()
	_update_viewmodel(delta)


## Bots (server): BotBrain holds `bot_trigger`; the gun fires as fast as it
## can and reloads on its own clock.
var bot_trigger: bool = false


func _bot_process(delta: float) -> void:
	is_aiming = false
	_tick_reload(delta)
	if bot_trigger and not holstered and not _player.health.is_dead and Match.can_shoot():
		try_fire()
	current_spread = _compute_spread()


## Trigger by fire mode: auto (hold), semi (one per click), burst
## (burst_count shots per click, fired at the weapon's fire rate).
func _handle_trigger() -> void:
	if _burst_left > 0:
		if is_reloading or _player.is_sprinting or ammo_in_magazine <= 0:
			_burst_left = 0
		elif try_fire():
			_burst_left -= 1
		return
	match fire_mode():
		"auto":
			if Input.is_action_pressed("shoot"):
				try_fire()
		"burst":
			if Input.is_action_just_pressed("shoot") and try_fire():
				_burst_left = maxi(data.burst_count - 1, 0)
		_:
			if Input.is_action_just_pressed("shoot"):
				try_fire()


## "auto", "burst" or "semi".
func fire_mode() -> String:
	if data.fire_modes.is_empty():
		return "auto" if data.automatic else "semi"
	return data.fire_modes[fire_mode_index % data.fire_modes.size()]


## Next fire mode (B). Returns false if the weapon has only one.
func cycle_fire_mode() -> bool:
	if data.fire_modes.size() < 2:
		return false
	fire_mode_index = (fire_mode_index + 1) % data.fire_modes.size()
	_burst_left = 0
	_play(&"ui_click", -8.0, 1.4, 5.0)
	ammo_changed.emit(ammo_in_magazine, ammo_reserve) # HUD refreshes the mode label
	return true


## Camera FOV multiplier when fully aimed (the scope's current zoom step).
func current_ads_fov() -> float:
	if data.scoped and zoom_index > 0 and zoom_index < data.zoom_levels.size():
		return data.zoom_levels[zoom_index]
	return data.ads_fov_multiplier


## Mouse sensitivity multiplier when fully aimed (scales with the zoom).
func current_ads_sensitivity() -> float:
	return data.ads_sensitivity_multiplier * current_ads_fov() / maxf(data.ads_fov_multiplier, 0.01)


## Mouse wheel while scoped: next / previous zoom step. False if not scoped
## or the scope has one step (then the wheel switches weapons as usual).
func cycle_zoom(direction: int) -> bool:
	if not is_scoped() or data.zoom_levels.size() < 2:
		return false
	var n := clampi(zoom_index + direction, 0, data.zoom_levels.size() - 1)
	if n != zoom_index:
		zoom_index = n
		_play(&"ui_click", -12.0, 0.8, 5.0)
	return true


## Hidden while a grenade is in hand (see Throwables.hold).
func set_holstered(on: bool) -> void:
	holstered = on
	_burst_left = 0
	if on:
		is_aiming = false
		_aim_toggled = false


## Fires one shot if possible. Returns true if a shot was fired.
func try_fire() -> bool:
	_inspect_left = 0.0
	if _cooldown > 0.0 or _player.is_sprinting:
		return false
	if is_reloading:
		# Shotgun: firing stops the reload with the shells already in.
		if not (data.shell_reload and ammo_in_magazine > 0):
			return false
		_stop_shell_reload()
	if data.melee:
		_cooldown = 60.0 / data.fire_rate
		_swing = 1.0
		_fire_ray()
		_player.add_recoil(data.recoil_pitch * _rng.randf_range(-1.0, 1.0), data.recoil_yaw * _rng.randf_range(-1.0, 1.0))
		_play_fire()
		fired.emit()
		return true
	if ammo_in_magazine <= 0:
		if Input.is_action_just_pressed("shoot"):
			_play(dry_fire_sound as Variant if dry_fire_sound else &"dry_fire" as Variant, -4.0, 1.0, 10.0)
		if ammo_reserve > 0:
			reload()
		return false

	ammo_in_magazine -= 1
	_cooldown = 60.0 / data.fire_rate
	_fire_ray()
	_bloom = minf(_bloom + data.spread_per_shot, data.max_bloom)
	_kick = 1.0
	_kick_roll = randf_range(-1.0, 1.0) # not _rng: that stream is the bullet spread
	if _anim.cycle != "" and not _player.is_bot:
		_cycle_left = WeaponAnim.cycle_time(data) # bolt / pump after the shot
		_cycle_sound = false

	var recoil_mult := lerpf(1.0, data.ads_recoil_multiplier, ads_blend)
	_player.add_recoil(
		data.recoil_pitch * _rng.randf_range(0.8, 1.2) * recoil_mult,
		_rng.randf_range(-data.recoil_yaw, data.recoil_yaw) * recoil_mult)

	if not _player.is_bot: # a bot's shot plays its effects from the server trace
		_show_muzzle_flash()
		_play_fire()
	# Kick scaled by the weapon's recoil (sniper hard, SMG light).
	if _player.is_local:
		GamepadInput.rumble(0.25, clampf(data.recoil_pitch * 0.15, 0.1, 0.8), 0.08)
	fired.emit()
	ammo_changed.emit(ammo_in_magazine, ammo_reserve)
	return true


func reload() -> void:
	_inspect_left = 0.0
	if is_reloading or ammo_in_magazine >= data.magazine_size or ammo_reserve <= 0:
		return
	is_reloading = true
	_cycle_left = 0.0
	_reload_total = _reload_length()
	_reload_timer = _reload_total
	_shells_loaded = 0
	_cue_index = 0
	_reload_sounds_left = 0
	if reload_sound:
		_play(reload_sound, -4.0, 1.0, 15.0)
		_cue_index = 99
	elif data.shell_reload:
		_reload_sounds_left = 1 # the pump at the end
	reload_started.emit(_reload_total)
	if not multiplayer.is_server() and NetworkManager.is_online():
		_server_reload.rpc_id(1)


## Seconds this reload takes: the magazine's reload time, or the shotgun's
## start + a shell per missing round + the pump.
func _reload_length() -> float:
	if not data.shell_reload:
		return data.reload_time
	var shells := mini(data.magazine_size - ammo_in_magazine, ammo_reserve)
	return data.reload_start + shells * data.shell_time + data.reload_end


## Runs the reload clock (local player and bots): sounds on cue, the
## shotgun's shells one by one, the magazine at the end.
func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_timer -= delta
	if data.shell_reload:
		var elapsed := _reload_total - _reload_timer
		var due := int(floor((elapsed - data.reload_start) / data.shell_time))
		while _shells_loaded < due and ammo_in_magazine < data.magazine_size and ammo_reserve > 0:
			_shells_loaded += 1
			ammo_in_magazine += 1
			ammo_reserve -= 1
			_play(&"shell_in", -5.0, _rng.randf_range(0.95, 1.05), 12.0)
			ammo_changed.emit(ammo_in_magazine, ammo_reserve)
		if _reload_sounds_left > 0 and _reload_timer <= data.reload_end * 0.8:
			_reload_sounds_left = 0
			_play(&"pump", -4.0, 1.0, 15.0)
		if _reload_timer <= 0.0:
			is_reloading = false
			reload_finished.emit()
		return
	_reload_sound_step()
	if _reload_timer <= 0.0:
		_finish_reload()


## Shotgun: stop loading (to fire) with the shells already in.
func _stop_shell_reload() -> void:
	is_reloading = false
	reload_finished.emit()
	if not multiplayer.is_server() and NetworkManager.is_online():
		_server_shells.rpc_id(1, _shells_loaded)


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
	_server_reload_start = NetworkManager.server_time()
	_server_reload_done_at = _server_reload_start + _reload_length() * 0.9


## Server: a client stopped loading shells after `count` (to fire). It gets
## at most what the time since it started allows.
@rpc("any_peer", "call_remote", "reliable")
func _server_shells(count: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _player.peer_id or not is_reloading:
		return
	_server_load_shells(count)


func _server_load_shells(count: int) -> void:
	var elapsed := NetworkManager.server_time() - _server_reload_start
	var allowed := int(floor((elapsed - data.reload_start * 0.5) / (data.shell_time * 0.8))) + 1
	var loaded := clampi(mini(count, allowed), 0, mini(data.magazine_size - ammo_in_magazine, ammo_reserve))
	ammo_in_magazine += loaded
	ammo_reserve -= loaded
	is_reloading = false


## Reload progress 0..1 (0 when not reloading).
func get_reload_progress() -> float:
	return clampf(1.0 - _reload_timer / maxf(_reload_total, 0.01), 0.0, 1.0) if is_reloading else 0.0


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
		if data.shell_reload:
			_server_load_shells(data.magazine_size) # a full load, as far as the time allows
		elif now < _server_reload_done_at:
			NetworkManager.report_violation(_player.peer_id, "fired while reloading")
			return
		else:
			_finish_reload()
	if not data.melee:
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


## Server: one pellet through breakable glass (it cracks or shatters and
## the bullet goes on) up to what it stops at; a door piece it hits takes the
## damage (Door / GlassPane.server_hit).
func _trace_through_breakables(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, players: Array,
		render_time: float, teammates: Array) -> Dictionary:
	var skip: Array[RID] = []
	var hit := {}
	for i in 4:
		hit = LagCompensation.trace(space, origin, dir, data.max_range, _player, players, render_time, teammates, skip)
		var col: Object = hit.get("collider")
		if col == null or not col.has_meta(&"breakable") or not Match.can_shoot():
			break
		var falloff := remap(hit.distance, data.falloff_start, data.max_range, 1.0, data.min_damage_multiplier)
		var target: Object = col.get_meta(&"breakable")
		target.server_hit(col, hit.position, data.damage * clampf(falloff, data.min_damage_multiplier, 1.0))
		if not target is GlassPane:
			break
		skip.append((col as CollisionObject3D).get_rid())
	return hit


## Server: trace every pellet with lag compensation, apply damage, broadcast effects.
func _server_process_shot(origin: Vector3, dirs: PackedVector3Array, render_time: float) -> void:
	# Teammates are not hit — bullets pass through them (unless friendly fire is on).
	var players: Array = get_tree().get_nodes_in_group(&"player")
	var teammates: Array = players.filter(
		func(p: PlayerController) -> bool: return p != _player and Match.shields(_player.peer_id, p.peer_id))
	var space := get_world_3d().direct_space_state
	var hit_positions := PackedVector3Array()
	var hit_normals := PackedVector3Array()
	var any_kill := false
	var any_head := false
	var any_hit := false
	for dir in dirs:
		var hit := _trace_through_breakables(space, origin, dir, players, render_time, teammates)
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
		var zone: StringName = hit.get("zone", &"head" if hitbox.is_head else &"chest")
		if hitbox.is_head:
			# The weapon decides the headshot multiplier; cancel the hitbox's own one.
			damage *= data.headshot_multiplier / maxf(hitbox.damage_multiplier, 0.001)
		else:
			damage *= Hitbox.ZONE_MULTIPLIERS.get(zone, 1.0)
		any_hit = true
		any_head = any_head or hitbox.is_head
		any_kill = hitbox.apply_hit(damage, _player, data.armor_penetration, zone in Hitbox.ARMORED_ZONES) or any_kill

	if any_hit:
		if _player.is_local:
			hit_confirmed.emit(any_kill, any_head)
		elif not _player.is_bot:
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
	if _player and not data.melee and not Match.is_friendly(_player.peer_id, multiplayer.get_unique_id()):
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


## How far (m) to pull the gun back so it doesn't poke through the world:
## rays from the eye along the barrel and straight ahead (world layer only).
func _wall_distance_pull(target: Vector3) -> float:
	if _camera == null or not is_inside_tree():
		return 0.0
	var muzzle_z := muzzle.position.z if muzzle else -0.5
	var tip_local := Vector3(target.x, target.y, target.z + muzzle_z - WALL_MARGIN)
	var eye := _camera.global_position
	var space := get_world_3d().direct_space_state
	var pull := 0.0
	for local: Vector3 in [tip_local, Vector3(0.0, 0.0, tip_local.z)]:
		var reach := local.length()
		var to := _camera.global_transform * local
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, to, 1))
		if not hit.is_empty():
			pull = maxf(pull, reach - eye.distance_to(hit.position))
	return clampf(pull, 0.0, MAX_WALL_PULL)


## Inspect (I): each gun its own way (WeaponAnim "inspect"): the pistol is
## turned side to side, the SMG's magazine checked, the rifle turned and its
## charging handle eased back, the shotgun shows a shell, the sniper is
## raised to look along the scope, the LMG's cover is lifted to show the
## belt, the knife is flipped. Any action cancels it.
const INSPECT_TIME := 2.6
var _inspect_left := 0.0


func start_inspect() -> void:
	if is_reloading or is_aiming or holstered or _player == null or not _player.is_local:
		return
	_inspect_left = INSPECT_TIME


func is_inspecting() -> bool:
	return _inspect_left > 0.0


func cancel_inspect() -> void:
	_inspect_left = 0.0


## Pose for the inspect: gun { offset, yaw, pitch, roll }, hands { left,
## right } (offsets from where they hold the gun), magazine offset (and
## whether it shows, -1 = leave it), LMG cover angle.
func _inspect_pose(delta: float) -> Dictionary:
	var pose := { "offset": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "roll": 0.0, "left": Vector3.ZERO,
		"right": Vector3.ZERO, "mag": Vector3.ZERO, "mag_show": -1, "cover": 0.0 }
	if _inspect_left <= 0.0:
		return pose
	if is_aiming or is_reloading or holstered:
		_inspect_left = 0.0
		return pose
	var before := 1.0 - _inspect_left / INSPECT_TIME
	_inspect_left = maxf(_inspect_left - delta, 0.0)
	var p := 1.0 - _inspect_left / INSPECT_TIME
	var first := _smooth(p, 0.0, 0.15) * (1.0 - _smooth(p, 0.45, 0.55))
	var second := _smooth(p, 0.5, 0.62) * (1.0 - _smooth(p, 0.85, 1.0))
	var h: Dictionary = WeaponModel.hands(data.weapon_id) if WeaponModel.HANDS.has(data.weapon_id) else {}
	var charge: Vector3 = WeaponModel.CHARGE.get(data.weapon_id, Vector3.ZERO)
	match String(_anim.inspect):
		"flip": # the blade flipped over, then a look along its edge
			pose.pitch = TAU * _smooth(p, 0.3, 0.6)
			pose.yaw = 0.8 * first - 0.4 * second
			pose.offset = Vector3(-0.1, 0.06, -0.05) * maxf(first, second)
			return pose
		"rotate": # pistol: quick turns, a press-check of the slide
			pose.yaw = 0.9 * first - 0.5 * second
			pose.roll = 0.6 * first - 0.7 * second
			pose.offset = Vector3(-0.06, 0.05, -0.03) * first + Vector3(0.02, 0.06, -0.03) * second
			pose.offset.z += 0.012 * sin(clampf((p - 0.68) / 0.1, 0.0, 1.0) * PI)
			return pose
		"mag_check": # SMG: tip it, drop the magazine a little, look, push it home
			pose.roll = -0.5 * first - 0.5 * second
			pose.yaw = 0.35 * first - 0.3 * second
			pose.offset = Vector3(-0.07, 0.06, -0.02) * first + Vector3(0.02, 0.07, -0.03) * second
			if not h.is_empty():
				var to_mag: Vector3 = h.mag - h.left
				var reach := _smooth(p, 0.08, 0.18) * (1.0 - _smooth(p, 0.46, 0.56))
				var drop := _smooth(p, 0.2, 0.3) * (1.0 - _smooth(p, 0.36, 0.44))
				pose.left = to_mag * reach + Vector3(0, -0.06, 0) * drop
				pose.mag = Vector3(0, -0.06, 0) * drop
			_inspect_cue(before, p, 0.36, &"mag_in")
		"shells": # shotgun: turned to the camera, a shell held up to look at
			pose.roll = 0.45 * first
			pose.yaw = 0.3 * first - 0.45 * second
			pose.offset = Vector3(-0.07, 0.05, -0.02) * first + Vector3(0.02, 0.07, -0.03) * second
			if not h.is_empty():
				var shown := _smooth(p, 0.1, 0.22) * (1.0 - _smooth(p, 0.38, 0.48))
				var held: Vector3 = h.left + Vector3(-0.04, 0.07, 0.04) # up off the pump, not back into the view
				pose.left = (held - h.left) * shown
				pose.mag = (held + Vector3(0.0, 0.035, -0.03) - Vector3(0, -0.07, -0.02)) * shown
				pose.mag_show = 1 if shown > 0.05 else 0
		"scope": # sniper: raised to look along the scope, then turned over
			pose.yaw = 1.1 * first - 0.35 * second
			pose.pitch = 0.15 * first
			pose.roll = -0.6 * second
			pose.offset = Vector3(-0.13, 0.1, 0.03) * first + Vector3(0.02, 0.07, -0.03) * second
			if not h.is_empty():
				pose.right = (charge - h.grip) * (_smooth(p, 0.62, 0.7) * (1.0 - _smooth(p, 0.8, 0.88))) * 0.8
		"belt": # LMG: the cover lifted, the belt shown, the cover shut
			pose.roll = 0.35 * first
			pose.yaw = 0.3 * first - 0.4 * second
			pose.offset = Vector3(-0.06, 0.06, -0.02) * first + Vector3(0.02, 0.07, -0.03) * second
			var lift := _smooth(p, 0.12, 0.24) * (1.0 - _smooth(p, 0.4, 0.48))
			pose.cover = -1.25 * lift
			if not h.is_empty():
				# Up to the front of the cover (up, not back: the forearm would fill the view).
				var at_cover := Vector3(-0.02, 0.075, 0.04)
				pose.left = at_cover * (_smooth(p, 0.04, 0.12) * (1.0 - _smooth(p, 0.48, 0.56)))
				pose.left += Vector3(0, 0.05, 0.0) * lift
			_inspect_cue(before, p, 0.14, &"cover_open")
			_inspect_cue(before, p, 0.44, &"cover_close")
		_: # rifle: turned side to side, the charging handle eased back
			pose.yaw = 0.75 * first - 0.35 * second
			pose.roll = 0.5 * first - 0.6 * second
			pose.pitch = 0.2 * second
			pose.offset = Vector3(-0.08, 0.05, -0.02) * first + Vector3(0.02, 0.07, -0.04) * second
			if not h.is_empty():
				var at := _smooth(p, 0.6, 0.66) * (1.0 - _smooth(p, 0.78, 0.84))
				pose.left = (charge - (h.left as Vector3)) * at + Vector3(0, 0, 0.04) * _smooth(p, 0.66, 0.72) \
					* (1.0 - _smooth(p, 0.74, 0.78))
	return pose


func _inspect_cue(before: float, now: float, at: float, sound: StringName) -> void:
	if before < at and now >= at:
		_play(sound, -8.0, 1.0, 10.0)


## The viewmodel every frame: the WeaponAnim profile's idle sway, walk /
## run bob, lag behind the mouse, the equip raise, fire kick, the bolt /
## pump cycle, reload and inspect poses, pulled back from walls.
func _update_viewmodel(delta: float) -> void:
	var a := _anim
	_time += delta
	_kick = move_toward(_kick, 0.0, delta * float(a.recover))
	var inspect := _inspect_pose(delta)
	var aim := ads_blend
	var target := _hip_position.lerp(ads_position, aim) + (inspect.offset as Vector3)
	target.z += _kick * float(a.kick_back)
	target.y += _kick * float(a.kick_up)
	# Knife: a slash from the right across to the left and back.
	_swing = move_toward(_swing, 0.0, delta / SWING_TIME)
	var slash := sin((1.0 - _swing) * PI) if _swing > 0.0 else 0.0
	target += Vector3(-0.16, 0.04, -0.1) * slash
	# Idle sway (breathing), much less when aiming.
	var loose := 1.0 - 0.85 * aim
	var sway := float(a.sway) * loose
	target += Vector3(sin(_time * 1.3) * 0.004, sin(_time * 2.6) * 0.0028, 0.0) * sway
	# Walk / run bob with the steps (bigger when sprinting, heavy guns more).
	var ground_speed := Vector2(_player.velocity.x, _player.velocity.z).length() if _player.is_on_floor() else 0.0
	_bob_phase += delta * ground_speed * 1.8
	var bob := float(a.bob) * clampf(ground_speed / 5.0, 0.0, 1.5) * loose
	target += Vector3(sin(_bob_phase) * 0.011, -absf(cos(_bob_phase)) * 0.009, 0.0) * bob
	# The gun lags a little behind the mouse.
	_update_look_lag(delta)
	var lag := _look_lag * float(a.lag) * (1.0 - 0.7 * aim)
	target += Vector3(lag.x * 0.05, -lag.y * 0.04, 0.0)
	# Equip: raised from low, tipped down.
	var raise := 0.0
	if _equip_left > 0.0:
		_equip_left = maxf(_equip_left - delta, 0.0)
		raise = smoothstep(0.0, 1.0, _equip_left / maxf(float(a.equip), 0.01))
	target += Vector3(0.03, -0.22, 0.06) * raise
	var pose := _animate_reload(get_reload_progress() if is_reloading else -1.0, inspect)
	var cycle := _animate_cycle(delta)
	target += (pose.offset as Vector3) + (cycle.offset as Vector3)
	rotation.y = lerpf(rotation.y, 0.9 * slash + float(inspect.yaw) + lag.x * 0.12, clampf(delta * 20.0, 0.0, 1.0))
	# Lower the weapon while sprinting.
	if _player.is_sprinting and not is_reloading:
		target += Vector3(-0.05, -0.08, 0.05)
	# Up against a wall, ceiling or slab (typically on stairs and ramps):
	# pull the gun back and tip it down instead of pushing it through.
	_wall_pull = move_toward(_wall_pull, _wall_distance_pull(target), delta * 3.0)
	target += Vector3(0.0, -_wall_pull * 0.2, _wall_pull)
	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	var k := clampf(delta * 14.0, 0.0, 1.0)
	rotation.x = lerpf(rotation.x, _kick * float(a.kick_rot) + float(pose.pitch) + float(cycle.pitch) - _wall_pull * 0.8
		+ float(inspect.pitch) - raise * 0.9 + lag.y * 0.08, k)
	rotation.z = lerpf(rotation.z, float(pose.roll) + float(inspect.roll) + float(cycle.roll)
		+ _kick * _kick_roll * float(a.kick_roll) + sin(_bob_phase) * 0.02 * bob - raise * 0.3, k)
	# Hands: where the reload / cycle / inspect want them, at the gun's hand speed.
	var hk := clampf(delta * 30.0 * float(a.hands), 0.0, 1.0)
	if _left_arm:
		_left_arm.position = _left_arm.position.lerp(_left_hand + (inspect.left as Vector3), hk)
	if _right_arm:
		_right_arm.position = _right_arm.position.lerp(_right_hand + (inspect.right as Vector3), hk)
	# Looking through a scope: the HUD draws the scope, hide the gun (also
	# while a grenade is in hand).
	var show_model := not is_scoped() and not holstered
	if _viewmodel_meshes and _viewmodel_meshes[0].visible != show_model:
		for mesh in _viewmodel_meshes:
			mesh.visible = show_model
		if show_model and _magazine and data.weapon_id == "shotgun" and not is_reloading:
			_magazine.visible = false


## How much the view turned this frame (yaw, pitch), eased back to zero.
func _update_look_lag(delta: float) -> void:
	if _camera == null:
		return
	var b := _camera.global_basis.orthonormalized()
	if _has_cam_basis:
		var turn := (_last_cam_basis.inverse() * b).get_euler()
		_look_lag += Vector2(turn.y, turn.x)
	_last_cam_basis = b
	_has_cam_basis = true
	_look_lag = _look_lag.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0)).limit_length(0.35)


## After a shot: the sniper's right hand works the bolt, the shotgun's
## left hand racks the pump (sound a third of the way in).
func _animate_cycle(delta: float) -> Dictionary:
	var pose := { "offset": Vector3.ZERO, "pitch": 0.0, "roll": 0.0 }
	if _cycle_left <= 0.0 or is_reloading:
		_cycle_left = 0.0
		return pose
	var total := WeaponAnim.cycle_time(data)
	_cycle_left = maxf(_cycle_left - delta, 0.0)
	var c := 1.0 - _cycle_left / total
	if not _cycle_sound and c >= 0.3:
		_cycle_sound = true
		_play(&"bolt" if _anim.cycle == "bolt" else &"pump", -5.0, 1.0, 15.0)
	var h: Dictionary = WeaponModel.hands(data.weapon_id) if WeaponModel.HANDS.has(data.weapon_id) else {}
	if h.is_empty():
		return pose
	if _anim.cycle == "bolt":
		var to_bolt: Vector3 = (WeaponModel.CHARGE[data.weapon_id] as Vector3) - (h.grip as Vector3)
		var reach := _smooth(c, 0.0, 0.22) * (1.0 - _smooth(c, 0.8, 1.0))
		var pull := _smooth(c, 0.25, 0.45) * (1.0 - _smooth(c, 0.55, 0.75))
		_right_hand = to_bolt * reach + Vector3(0, 0.015, 0.08) * pull
		pose.roll = 0.12 * reach
		pose.pitch = -0.04 * reach
	else:
		var rack := _smooth(c, 0.08, 0.4) * (1.0 - _smooth(c, 0.45, 0.8))
		_left_hand = Vector3(0, 0, 0.08) * rack
		pose.offset = Vector3(0, 0.005, 0.015) * rack
		pose.pitch = 0.05 * rack
	return pose


## First-person reload after the gun's profile: it rolls towards you by its
## tilt, the left hand pulls the magazine out and down, fetches a new one
## and seats it, then works the charging handle / slide (the sniper's right
## hand the bolt). Shotgun: one shell per shell_time fed into the port, a
## pump at the end. LMG: the hand lifts the top cover, swaps the box, shuts
## the cover, charges. `p` = progress 0..1, or < 0 when not reloading.
## Sets the hand targets and the magazine; returns the gun pose.
func _animate_reload(p: float, inspect: Dictionary) -> Dictionary:
	var pose := { "offset": Vector3.ZERO, "pitch": 0.0, "roll": 0.0 }
	_left_hand = Vector3.ZERO
	_right_hand = Vector3.ZERO
	var mag := Vector3.ZERO
	var mag_visible := data.weapon_id != "shotgun"
	var cover := 0.0
	if p >= 0.0 and WeaponModel.HANDS.has(data.weapon_id):
		var h: Dictionary = WeaponModel.hands(data.weapon_id)
		var to_mag: Vector3 = h.mag - h.left
		var charge: Vector3 = WeaponModel.CHARGE.get(data.weapon_id, Vector3.ZERO)
		var tilt := _smooth(p, 0.0, 0.12) * (1.0 - _smooth(p, 0.82, 1.0))
		# Raise the gun towards the centre and roll its underside to the camera.
		# (The LMG rolls its top towards you instead, to look into the feed tray.)
		pose.roll = deg_to_rad(float(_anim.tilt)) * 3.5 * tilt * (1.0 if data.weapon_id == "lmg" else -1.0)
		pose.pitch = -0.08 * tilt
		pose.offset = Vector3(-0.07, 0.05, -0.03) * tilt
		if data.shell_reload:
			var elapsed := _reload_total - _reload_timer
			var feeding := elapsed > data.reload_start and _reload_timer > data.reload_end
			var cycle := fposmod((elapsed - data.reload_start) / data.shell_time, 1.0)
			mag_visible = false
			if feeding:
				# A shell from below up into the port, then down for the next.
				var up := sin(cycle * PI)
				_left_hand = to_mag * up + Vector3(0, -0.18, 0.06) * (1.0 - up)
				mag = _left_hand - to_mag
				mag_visible = cycle < 0.55
			elif _reload_timer <= data.reload_end: # rack the pump
				var t := 1.0 - _reload_timer / maxf(data.reload_end, 0.01)
				_left_hand = Vector3(0, 0, 0.08) * sin(t * PI)
		elif data.weapon_id == "lmg":
			# Up to the front of the cover (up, not back: the forearm would fill the view).
			var at_cover := Vector3(-0.02, 0.075, 0.04)
			cover = -1.3 * _smooth(p, 0.1, 0.2) * (1.0 - _smooth(p, 0.68, 0.76))
			var drop := Vector3(0, -0.32, 0.1)
			if p < 0.1:
				_left_hand = at_cover * _smooth(p, 0.02, 0.1)
			elif p < 0.2:
				_left_hand = at_cover + Vector3(0, 0.05, 0.0) * _smooth(p, 0.1, 0.2)
			elif p < 0.3:
				_left_hand = (at_cover + Vector3(0, 0.05, 0.0)).lerp(to_mag, _smooth(p, 0.2, 0.3))
			elif p < 0.42:
				var t := _smooth(p, 0.3, 0.42)
				_left_hand = to_mag + drop * t
				mag = drop * t
			elif p < 0.52:
				_left_hand = to_mag + drop
				mag_visible = false
			elif p < 0.62:
				var t := 1.0 - _smooth(p, 0.52, 0.62)
				_left_hand = to_mag + drop * t
				mag = drop * t
			elif p < 0.68:
				_left_hand = to_mag.lerp(at_cover + Vector3(0, 0.05, 0.0), _smooth(p, 0.62, 0.68))
			elif p < 0.76:
				_left_hand = (at_cover + Vector3(0, 0.05, 0.0)).lerp(at_cover, _smooth(p, 0.68, 0.74))
			elif p < 0.84:
				_left_hand = at_cover * (1.0 - _smooth(p, 0.76, 0.84))
			elif p < 0.96:
				var t := _smooth(p, 0.84, 0.88) * (1.0 - _smooth(p, 0.92, 0.96))
				_left_hand = (charge - (h.left as Vector3)) * t + Vector3(0, 0, 0.06) * sin(clampf((p - 0.87) / 0.06, 0.0, 1.0) * PI)
		else:
			var drop := Vector3(0, -0.34, 0.08)
			if p < 0.12:
				_left_hand = to_mag * _smooth(p, 0.0, 0.12)
			elif p < 0.3:
				var t := _smooth(p, 0.12, 0.3)
				_left_hand = to_mag + drop * t
				mag = drop * t
			elif p < 0.42:
				_left_hand = to_mag + drop
				mag_visible = false # the old magazine is gone, reaching for a new one
			elif p < 0.55:
				var t := 1.0 - _smooth(p, 0.42, 0.55)
				_left_hand = to_mag + drop * t
				mag = drop * t
			elif p < 0.7:
				_left_hand = to_mag * (1.0 - _smooth(p, 0.55, 0.7))
			if data.weapon_id == "sniper":
				# The right hand works the bolt to chamber a round.
				var reach := _smooth(p, 0.7, 0.76) * (1.0 - _smooth(p, 0.9, 0.96))
				var pull := sin(clampf((p - 0.76) / 0.12, 0.0, 1.0) * PI)
				_right_hand = (charge - (h.grip as Vector3)) * reach + Vector3(0, 0.015, 0.08) * pull
			elif p >= 0.72 and p < 0.94:
				# The left hand to the charging handle / slide and a pull back.
				var reach := _smooth(p, 0.72, 0.8) * (1.0 - _smooth(p, 0.88, 0.94))
				var pull := sin(clampf((p - 0.8) / 0.08, 0.0, 1.0) * PI)
				_left_hand = (charge - (h.left as Vector3)) * reach + Vector3(0, 0, 0.05) * pull
				pose.offset.z += 0.012 * pull
	# The inspect can move the magazine (SMG check) or show a shell.
	mag += inspect.mag as Vector3
	if int(inspect.mag_show) >= 0:
		mag_visible = int(inspect.mag_show) == 1
	if _cover:
		_cover.rotation.x = lerpf(_cover.rotation.x, cover + float(inspect.cover), 0.35)
	if _magazine:
		_magazine.position = mag
		if _magazine.visible != mag_visible and not is_scoped() and not holstered:
			_magazine.visible = mag_visible and _player != null and _player.is_local
	return pose


static func _smooth(x: float, a: float, b: float) -> float:
	return smoothstep(a, b, x)


func _update_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and muzzle_flash:
			muzzle_flash.visible = false


func _play_fire() -> void:
	var sound: Variant = fire_sound as Variant if fire_sound else StringName("fire_" + data.weapon_id) as Variant
	_play(sound, 0.0, _rng.randf_range(0.95, 1.05), fire_sound_distance, 12.0)


## Weapon sounds come from the weapon (the local player's is at the camera,
## so it is heard at full volume and centred; others' are positional).
func _play(sound: Variant, volume_db: float = 0.0, pitch: float = 1.0,
		max_distance: float = 20.0, unit_size: float = 6.0) -> void:
	Audio.play_3d(sound, global_position, volume_db, max_distance, pitch, unit_size)


## Reload sounds on the profile's cues (magazine out / in, cover, bolt).
func _reload_sound_step() -> void:
	var cues: Array = _anim.reload_cues
	var progress := get_reload_progress()
	while _cue_index < cues.size() and progress >= float(cues[_cue_index][0]):
		_play(StringName(cues[_cue_index][1]), -4.0, 1.0, 15.0)
		_cue_index += 1


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	if data.melee:
		Audio.play_3d(&"knife_hit", pos, -4.0, 20.0, _rng.randf_range(0.9, 1.1), 3.0)
		return
	# Doors and glass show their own damage (splinters, cracks) — a decal
	# would hang in the air once the piece breaks.
	if not _is_breakable_at(pos, normal):
		ImpactDecals.get_for(self).add(pos, normal)
	# One impact sound per shot (a shotgun blast is 13 pellets).
	var now := Time.get_ticks_msec()
	if now - _last_impact_sound_ms > 40:
		_last_impact_sound_ms = now
		Audio.play_3d(&"impact", pos, -8.0, 25.0, _rng.randf_range(0.85, 1.15), 3.0)


func _is_breakable_at(pos: Vector3, normal: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos - normal * 0.01
	q.collision_mask = 1
	for r: Dictionary in get_world_3d().direct_space_state.intersect_point(q, 4):
		var c: Object = r.get("collider")
		if c and c.has_meta(&"breakable"):
			return true
	return false
