class_name PlayerController
extends CharacterBody3D
## First-person player: mouse look, walk / sprint / crouch / slide / jump,
## camera effects (head bob, FOV kick, recoil) and weapon handling.
##
## The same scene is used for every player in a match:
##   • local player  (is_local)  – reads input, runs physics, first-person view
##   • remote players            – driven by PlayerNetSync interpolation,
##                                 third-person body + name tag
##
## Scene layout (see scenes/player/player.tscn):
##   Player (CharacterBody3D)          ← authority = owning peer
##   ├── CollisionShape3D (CapsuleShape3D, local to scene)
##   ├── Health                        ← authority = server
##   ├── NetSync (PlayerNetSync)
##   ├── BodyHitbox / Head/HeadHitbox  ← Hitbox (layer 3)
##   ├── Throwables                   ← HE grenade + Molotov (added in _ready)
##   ├── ThirdPerson/Model (PlayerModel: body, legs, gun; shadow-only for the local player) + NameTag
##   └── Head (Node3D)                 ← pitch
##       └── Camera3D                  ← recoil + head bob
##           └── WeaponHolder (Node3D) ← weapons as children

signal respawned

## Footsteps: metres between steps, and [volume dB, heard up to m].
const STRIDE_WALK := 2.2
const STRIDE_SPRINT := 2.9
const STRIDE_CROUCH := 1.6
const STEP_WALK := [-6.0, 25.0]
const STEP_SPRINT := [0.0, 40.0]
const STEP_CROUCH := [-18.0, 8.0]
## Lean (Q / E): the head moves this far sideways and the view rolls.
const LEAN_OFFSET := 0.35
const LEAN_ROLL_DEGREES := 12.0
## Walking (Caps Lock toggle): this share of walk_speed, near-silent steps.
const WALK_TOGGLE_SPEED := 0.55

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.6
@export var ground_acceleration: float = 12.0
## Braking on the ground (also used when reversing direction), so the
## player stops almost on the spot instead of gliding.
@export var ground_deceleration: float = 22.0
@export var air_acceleration: float = 2.5
@export var jump_velocity: float = 5.0
## Grace period after walking off a ledge where jumping is still allowed.
@export var coyote_time: float = 0.12
## A jump pressed this long before landing still triggers.
@export var jump_buffer_time: float = 0.12

@export_group("Crouch & Slide")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
@export var crouch_transition_speed: float = 10.0
## Minimum horizontal speed needed to start a slide (sprinting reaches it).
@export var slide_min_speed: float = 6.5
@export var slide_boost: float = 2.5
@export var slide_friction: float = 7.0
@export var slide_end_speed: float = 3.0
@export var slide_cooldown: float = 0.6

@export_group("Camera")
@export var eye_offset: float = 0.15
@export var max_pitch_degrees: float = 89.0
@export var head_bob_amount: float = 0.035
@export var head_bob_frequency: float = 2.2
@export var sprint_fov_boost: float = 8.0
@export var recoil_recovery: float = 9.0

@export_group("Respawn")
@export var fall_limit_y: float = -30.0
@export var respawn_delay: float = 2.0

## Network peer that owns this player (1 = server / offline).
var peer_id: int = 1
var player_name: String = "Player"
var is_local: bool = true
var input_enabled: bool = true
var is_sprinting: bool = false
var is_crouching: bool = false
var is_sliding: bool = false
var current_weapon: Weapon
## Loadout: primary weapon id (GameConfig.PRIMARY_WEAPONS; "" = none, Bomb
## Defusal before buying one) + the pistol + the knife.
var primary_id: String = GameConfig.DEFAULT_PRIMARY
## 0 = primary, 1 = secondary (pistol), 2 = knife.
var current_slot: int = 0
const SLOT_COUNT := 3
## Walk toggle (Caps Lock): slow and quiet.
var is_walking: bool = false
## Lean -1 (left) .. 1 (right), smoothed; remote players get it from NetSync.
var lean: float = 0.0
var _lean_target: float = 0.0
## weapon_id -> Weapon (every weapon exists on every player; see GameConfig.WEAPONS).
var weapons: Dictionary = {}
## Grenades (quick-throw: G HE, Q Molotov, F flash, Z smoke).
var throwables: Throwables
## Remote players' bodies lie this long after the death animation.
const CORPSE_TIME := 8.0
## Counts lives, so a timer from an earlier death can't hide a respawned player.
var _life: int = 0
## Seconds of flashbang blindness left (local player only; see GrenadeFx.flash).
var blind_time: float = 0.0
## Grenade wheel open (hold 4): the mouse points at a grenade instead of looking.
var grenade_wheel_open: bool = false
## Climbing onto a ledge (see Climb): true while pulling up.
var is_climbing: bool = false
var _climb_time: float = 0.0
var _climb_duration: float = 0.0
var _climb_from: Vector3
var _climb_to: Vector3
## First-person hands on the ledge while climbing (local player).
var _climb_hands: ClimbHands

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var health: Health = $Health
@onready var net_sync: PlayerNetSync = $NetSync
@onready var body_hitbox: Hitbox = $BodyHitbox
@onready var head_hitbox: Hitbox = $Head/HeadHitbox
@onready var hitboxes: Array[Hitbox] = [body_hitbox, head_hitbox]
var _remote_reloading := false
@onready var _third_person: Node3D = $ThirdPerson
@onready var _model: PlayerModel = $ThirdPerson/Model
@onready var _name_tag: Label3D = $NameTag
## Teammates' health under their name (built in _ready).
var _tag_health: Label3D
@onready var _body_hitbox_shape: CapsuleShape3D = $BodyHitbox/CollisionShape3D.shape
@onready var _shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _height: float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _bob_time: float = 0.0
var _recoil := Vector2.ZERO # (pitch, yaw) in radians, applied to the camera
var _fell_reported: bool = false
var _default_regen: float = 0.0
var _crouch_toggled: bool = false
var _step_distance: float = 0.0
var _remote_vy: float = 0.0
var _was_sliding: bool = false


func _enter_tree() -> void:
	# Must be set before _ready so RPCs route correctly from the first frame.
	set_multiplayer_authority(peer_id)
	$Health.set_multiplayer_authority(1)


func _ready() -> void:
	is_local = peer_id == multiplayer.get_unique_id() and not NetworkManager.is_dedicated()
	_height = stand_height
	_apply_height()
	health.died.connect(_on_died)
	_default_regen = health.regen_per_second
	_name_tag.text = player_name
	_tag_health = Label3D.new()
	_tag_health.name = "TagHealth"
	_tag_health.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_health.no_depth_test = true
	_tag_health.fixed_size = true
	_tag_health.pixel_size = _name_tag.pixel_size
	_tag_health.font_size = 22
	_tag_health.outline_size = 6
	_tag_health.offset = Vector2(0, -34)
	_tag_health.visible = false
	_name_tag.add_child(_tag_health)
	# Built here (not in the scene) but under a fixed name, so its RPC path
	# is the same on every peer.
	throwables = Throwables.new()
	throwables.name = "Throwables"
	add_child(throwables)
	NetworkManager.roster_changed.connect(_update_team_visuals)
	_update_team_visuals()

	if is_local:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		SettingsManager.apply_to_camera(camera)
		SettingsManager.graphics_changed.connect(func(_p: GraphicsPreset) -> void: SettingsManager.apply_to_camera(camera))
		# Own body only casts shadows; own name tag hidden.
		for mesh: GeometryInstance3D in _third_person.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_name_tag.visible = false
	else:
		camera.current = false
		input_enabled = false
		set_process_unhandled_input(false)

	for child in weapon_holder.get_children():
		if child is Weapon:
			var w := child as Weapon
			weapons[w.data.weapon_id] = w
			w.unequip()
	apply_loadout(primary_id, current_slot)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not grenade_wheel_open:
		var motion := event as InputEventMouseMotion
		var sens := SettingsManager.mouse_sensitivity * 0.01
		if current_weapon:
			sens *= lerpf(1.0, current_weapon.current_ads_sensitivity() * SettingsManager.ads_sensitivity_scale,
				current_weapon.ads_blend)
		var invert := -1.0 if SettingsManager.invert_y else 1.0
		rotate_y(-motion.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * sens * invert,
			-deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	elif event.is_action_pressed(&"interact") and not event.is_echo() and not _bomb_action_here() and use_door():
		pass # opened / closed the door in front
	elif event.is_action(&"interact") and not event.is_echo():
		# Plant / defuse in Bomb Defusal (the server checks everything).
		if Match.mode == GameConfig.Mode.BOMB:
			Match.bomb.request_interact(event.is_pressed())
	elif event.is_action_pressed(&"weapon_1"):
		select_slot(0)
	elif event.is_action_pressed(&"weapon_2"):
		select_slot(1)
	elif event.is_action_pressed(&"weapon_3"):
		select_slot(2)
	elif event.is_action_pressed(&"weapon_next") or event.is_action_pressed(&"weapon_prev"):
		var step := 1 if event.is_action_pressed(&"weapon_next") else -1
		# Looking through a scope, the wheel zooms instead of switching.
		if current_weapon and current_weapon.cycle_zoom(step):
			return
		if throwables and throwables.is_holding():
			select_slot(current_slot, true)
		else:
			select_slot(_next_slot(current_slot, step))
	elif event.is_action_pressed(&"inspect"):
		if current_weapon:
			current_weapon.start_inspect()
	elif event.is_action_pressed(&"fire_mode"):
		if current_weapon:
			current_weapon.cycle_fire_mode()
	elif event.is_action_pressed(&"walk_toggle"):
		is_walking = not is_walking
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Controller look runs every rendered frame (smooth at any FPS).
func _process(delta: float) -> void:
	blind_time = maxf(blind_time - delta, 0.0)
	if is_local and not health.is_dead:
		_lean_target = _local_lean_target()
	lean = move_toward(lean, _lean_target, delta * 6.0)
	_apply_lean()
	if is_local and input_enabled and not health.is_dead and not grenade_wheel_open:
		_pad_look(delta)
	if not is_local and visible:
		_model.animate(delta, is_crouching)
		_update_name_tag()


func _physics_process(delta: float) -> void:
	if not is_local or health.is_dead:
		return

	var input_dir := Vector2.ZERO
	if input_enabled and Match.can_move():
		input_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var on_floor := is_on_floor()

	# --- Timers -------------------------------------------------------------
	_coyote_timer = coyote_time if on_floor else _coyote_timer - delta
	_jump_buffer_timer -= delta
	_slide_cooldown_timer -= delta
	if input_enabled and Match.can_move() and Input.is_action_just_pressed(&"jump"):
		_jump_buffer_timer = jump_buffer_time

	# --- Climbing -----------------------------------------------------------
	if is_climbing:
		_update_climb(delta)
		return
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and _try_climb(Climb.MIN_HEIGHT):
		_jump_buffer_timer = 0.0
		return
	# Jumped at something too high to jump onto: keep Jump held to pull up.
	if not on_floor and velocity.y < 2.0 and input_enabled and Input.is_action_pressed(&"jump") \
			and _try_climb(0.2):
		return

	# --- Gravity ------------------------------------------------------------
	if not on_floor:
		velocity.y -= _gravity * delta

	# --- Crouch / slide state -------------------------------------------------
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	# Only the Slide key slides — crouching while running just slows you down.
	var crouch_pressed := input_enabled and Input.is_action_just_pressed(&"slide")
	if SettingsManager.crouch_toggle:
		# Toggle mode: press crouch to switch; sprint or jump stands you up.
		if input_enabled and Input.is_action_just_pressed(&"crouch"):
			_crouch_toggled = not _crouch_toggled
		if input_enabled and (Input.is_action_pressed(&"sprint") or Input.is_action_just_pressed(&"jump")):
			_crouch_toggled = false
	else:
		_crouch_toggled = false
	var crouch_held := input_enabled and (_crouch_toggled or Input.is_action_pressed(&"slide") \
		or (not SettingsManager.crouch_toggle and Input.is_action_pressed(&"crouch")))

	if crouch_pressed and on_floor and not is_sliding and _slide_cooldown_timer <= 0.0 \
			and horizontal.length() >= slide_min_speed:
		_start_slide(horizontal)

	var blocked_above := _is_ceiling_blocked()
	is_crouching = crouch_held or is_sliding or (is_crouching and blocked_above)

	var aiming := current_weapon != null and current_weapon.is_aiming
	var shooting := input_enabled and Input.is_action_pressed(&"shoot")
	is_sprinting = input_enabled and Input.is_action_pressed(&"sprint") and input_dir.y < -0.1 \
		and not is_crouching and not aiming and not shooting

	# --- Horizontal movement -----------------------------------------------
	if is_sliding:
		_update_slide(delta, on_floor, crouch_held)
	else:
		var speed := walk_speed
		if is_crouching:
			speed = crouch_speed
		elif is_sprinting:
			speed = sprint_speed
		elif is_walking:
			speed = walk_speed * WALK_TOGGLE_SPEED
		if absf(lean) > 0.3:
			speed = minf(speed, walk_speed * 0.7)
		if current_weapon:
			speed *= lerpf(1.0, current_weapon.data.ads_move_speed_multiplier, current_weapon.ads_blend)

		var target := wish_dir * speed
		var accel := air_acceleration
		if on_floor:
			# Brake hard when letting go or pushing against the current motion.
			var braking := wish_dir == Vector3.ZERO or horizontal.dot(wish_dir) < 0.0
			accel = ground_deceleration if braking else ground_acceleration
		horizontal = horizontal.move_toward(target, accel * speed * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# --- Jump ---------------------------------------------------------------
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not blocked_above:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_movement_sound(&"jump", -10.0, 12.0)
		if is_sliding:
			_end_slide() # slide-jump keeps the momentum

	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not on_floor and fall_speed > 3.0:
		_landed(fall_speed)
	_advance_footsteps(Vector2(velocity.x, velocity.z).length() * delta, is_on_floor())

	_update_height(delta)
	_update_camera(delta, on_floor)

	if global_position.y < fall_limit_y and not _fell_reported:
		_fell_reported = true
		net_sync.report_fell()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Bomb Defusal: F plants / defuses here, so it must not work a door.
func _bomb_action_here() -> bool:
	if Match.mode != GameConfig.Mode.BOMB:
		return false
	var b := Match.bomb
	if b.bomb_carrier == peer_id and b.site_at(global_position) != "":
		return true
	return b.bomb_state == BombRules.BombState.PLANTED \
		and global_position.distance_to(b.bomb_position) <= BombRules.DEFUSE_RANGE + 0.5


## Interact (F) on the door in front (within Door.USE_RANGE): opens it away
## from us, or closes it. Returns false if there is no door there.
func use_door() -> bool:
	if health.is_dead:
		return false
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * Door.USE_RANGE, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = hit.get("collider")
	var door: Door = null
	if col and col.has_meta(&"breakable") and col.get_meta(&"breakable") is Door:
		door = col.get_meta(&"breakable")
	else:
		# Looking into a doorway (an open door stands aside): the nearest
		# door we roughly face.
		var look := -camera.global_basis.z
		var best := 2.5
		for d: Door in get_tree().get_nodes_in_group(Door.GROUP):
			var to := (d.global_position + Vector3.UP * 1.2) - from
			var dist := to.length()
			if dist < best and look.dot(to / maxf(dist, 0.01)) > 0.7:
				best = dist
				door = d
	if door == null:
		return false
	door.request_toggle(global_position)
	return true


## Pulls the player up onto a climbable ledge in front (at least
## `min_height` high). Returns false if there is none.
func _try_climb(min_height: float) -> bool:
	if not input_enabled or not Match.can_move() or is_sliding:
		return false
	var forward := -global_basis.z
	var ledge := Climb.find_ledge(get_world_3d().direct_space_state, global_position, forward)
	if ledge.is_empty() or not ledge.climbable or ledge.height < min_height:
		return false
	is_climbing = true
	_climb_time = 0.0
	_climb_duration = 0.3 + 0.16 * ledge.height
	_climb_from = global_position
	_climb_to = (ledge.top as Vector3) + Vector3.UP * 0.02
	velocity = Vector3.ZERO
	is_crouching = true
	if current_weapon and not throwables.is_holding():
		current_weapon.set_holstered(true)
	_movement_sound(&"jump", -8.0, 14.0)
	if is_local:
		_climb_hands = ClimbHands.new()
		add_child(_climb_hands)
		_climb_hands.grab(_climb_to, forward, camera)
	return true


## Up first (hands on the edge), then forward onto the top.
func _update_climb(delta: float) -> void:
	_climb_time += delta
	var t := clampf(_climb_time / _climb_duration, 0.0, 1.0)
	var up := clampf(t / 0.7, 0.0, 1.0)
	var over := clampf((t - 0.55) / 0.45, 0.0, 1.0)
	var pos := _climb_from
	pos.y = lerpf(_climb_from.y, _climb_to.y + 0.05, 1.0 - pow(1.0 - up, 2.0))
	pos.x = lerpf(_climb_from.x, _climb_to.x, over * over)
	pos.z = lerpf(_climb_from.z, _climb_to.z, over * over)
	global_position = pos
	velocity = Vector3.ZERO
	is_crouching = true
	_update_height(delta)
	_update_camera(delta, false)
	if t >= 1.0:
		_end_climb()
		_movement_sound(&"land", -12.0, 14.0)


func _end_climb() -> void:
	if is_instance_valid(_climb_hands):
		_climb_hands.release()
	_climb_hands = null
	if not is_climbing:
		return
	is_climbing = false
	is_crouching = _is_ceiling_blocked()
	if current_weapon and not (throwables and throwables.is_holding()):
		current_weapon.set_holstered(false)


## Weapons in slot order: [primary (null if none), secondary, knife].
func loadout_weapons() -> Array[Weapon]:
	var primary: Weapon = weapons.get(primary_id) if primary_id != "" else null
	return [primary, weapons.get(GameConfig.SECONDARY_WEAPON), weapons.get(GameConfig.MELEE_WEAPON)]


## Sets the primary weapon, refills ammo and equips `slot` (spawn / respawn);
## the pistol if there is no primary.
func apply_loadout(primary: String, slot: int = 0) -> void:
	primary_id = primary if primary == "" or weapons.has(primary) else GameConfig.DEFAULT_PRIMARY
	# No health regeneration in Bomb Defusal (damage carries through a round).
	health.regen_per_second = 0.0 if Match.mode == GameConfig.Mode.BOMB else _default_regen
	for w: Weapon in weapons.values():
		w.refill_ammo()
	current_slot = -1
	slot = clampi(slot, 0, SLOT_COUNT - 1)
	if loadout_weapons()[slot] == null:
		slot = 1
	_equip_slot(slot)


## A bought primary (Bomb Defusal): replaces the old one, full ammo, in hand.
func give_primary(primary: String) -> void:
	if not weapons.has(primary):
		return
	if throwables and throwables.is_holding():
		throwables.put_away()
	primary_id = primary
	(weapons[primary] as Weapon).refill_ammo()
	_equip_slot(0)
	play_equip_sound()


## The next slot that holds a weapon, going `step` from `slot`.
func _next_slot(slot: int, step: int) -> int:
	var ws := loadout_weapons()
	for i in range(1, SLOT_COUNT + 1):
		var s := posmod(slot + step * i, SLOT_COUNT)
		if ws[s] != null:
			return s
	return slot


## Local player switches weapon (keys 1/2/3, mouse wheel); replicated via
## NetSync. Also puts a grenade in hand away (`force`: even to the same slot).
func select_slot(slot: int, force: bool = false) -> void:
	if health.is_dead:
		return
	if throwables and throwables.is_holding():
		throwables.put_away()
		if slot == current_slot:
			play_equip_sound()
			return
	if slot == current_slot and not force:
		return
	if loadout_weapons()[slot] == null:
		return
	_equip_slot(slot)
	play_equip_sound()
	net_sync.send_slot(slot)


func play_equip_sound() -> void:
	_movement_sound(&"equip", -6.0, 12.0)


## Applies a slot change without replicating it (used by NetSync).
func _equip_slot(slot: int) -> void:
	var w: Weapon = loadout_weapons()[slot]
	if w == null:
		return
	current_slot = slot
	equip_weapon(w)


func equip_weapon(weapon: Weapon) -> void:
	if current_weapon == weapon:
		return
	if current_weapon:
		current_weapon.unequip()
	current_weapon = weapon
	if weapon:
		weapon.equip(self, camera)
		_model.set_weapon(weapon.data.weapon_id)


## Blinds the local player for `seconds` (a flashbang went off in view).
func flash(seconds: float) -> void:
	if seconds <= 0.0:
		return
	blind_time = maxf(blind_time, seconds)
	if is_local:
		Audio.play_local(&"flash_ring", remap(clampf(seconds, 0.0, GrenadeFx.FLASH_MAX_BLIND),
			0.0, GrenadeFx.FLASH_MAX_BLIND, -24.0, -6.0))
		GamepadInput.rumble(0.3, 0.2, 0.2)


## White-out strength 0..1 for the HUD: full while there is more than
## GrenadeFx.FLASH_FADE seconds left, then fading.
func blind_alpha() -> float:
	return clampf(blind_time / GrenadeFx.FLASH_FADE, 0.0, 1.0)


## Called by weapons. Values are in degrees.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	_recoil.x += deg_to_rad(pitch_degrees)
	_recoil.y += deg_to_rad(yaw_degrees)


## Called on every peer by PlayerNetSync when the server respawns this
## player. `nades`: grenade counts carried into the round (Bomb Defusal).
func respawn_at(xform: Transform3D, primary: String, nades: Array = []) -> void:
	apply_loadout(primary, 0)
	throwables.refill(nades)
	blind_time = 0.0
	global_transform = xform
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_recoil = Vector2.ZERO
	is_sliding = false
	_fell_reported = false
	_end_climb()
	_life += 1
	_model.reset_pose()
	camera.rotation.z = 0.0
	_apply_height()
	if current_weapon:
		current_weapon.set_holstered(false)
	visible = true
	_set_hitboxes_enabled(true)
	is_walking = false
	lean = 0.0
	_lean_target = 0.0
	respawned.emit()


## Called by PlayerNetSync for remote players (interpolated state).
func apply_remote_state(pos: Vector3, yaw: float, pitch: float, height: float, flags: int) -> void:
	var previous := global_position
	global_position = pos
	rotation.y = yaw
	head.rotation.x = pitch
	is_sprinting = flags & PlayerNetSync.Flags.SPRINTING != 0
	is_crouching = flags & PlayerNetSync.Flags.CROUCHING != 0
	is_sliding = flags & PlayerNetSync.Flags.SLIDING != 0
	is_walking = flags & PlayerNetSync.Flags.WALKING != 0
	_lean_target = (1.0 if flags & PlayerNetSync.Flags.LEAN_RIGHT != 0 else 0.0) \
		- (1.0 if flags & PlayerNetSync.Flags.LEAN_LEFT != 0 else 0.0)
	# Others see the reload: the model swaps the magazine, with sound.
	var reloading := flags & PlayerNetSync.Flags.RELOADING != 0
	if reloading and not _remote_reloading and current_weapon:
		_model.start_reload(current_weapon.data.reload_time)
		Audio.play_3d(&"mag_out", global_position + Vector3.UP, -6.0, 15.0)
	elif not reloading and _remote_reloading and _model.is_reloading():
		_model.stop_reload()
	_remote_reloading = reloading
	if not is_equal_approx(height, _height):
		_height = height
		_apply_height()
	_remote_movement_sounds(previous, pos)


func current_height() -> float:
	return _height


## Team colour on the body; name tags of enemies are hidden behind walls
## (no wallhack), teammates' tags are always visible.
func _update_team_visuals() -> void:
	var team := Match.get_team(peer_id)
	var local_id := multiplayer.get_unique_id()
	var friendly := Match.is_team_mode() and Match.is_friendly(peer_id, local_id)
	_model.set_team_color(GameConfig.team_color(team))
	_name_tag.no_depth_test = friendly
	_name_tag.outline_modulate = Color(0.1, 0.25, 0.6, 0.9) if friendly else Color(0.45, 0.05, 0.05, 0.9)


## Name over the head (remote players, every frame):
## • teammates: always, through walls, with a health bar under the name;
## • enemies: only when the crosshair is on them (within TAG_AIM_DEGREES) or
##   they are close (TAG_NEAR), never through walls (depth test) or smoke.
const TAG_AIM_DEGREES := 4.0
const TAG_NEAR := 6.0
const TAG_RANGE := 70.0


func _update_name_tag() -> void:
	var viewer := get_viewport().get_camera_3d()
	if viewer == null or health.is_dead:
		_name_tag.visible = false
		return
	var friendly := Match.is_team_mode() and Match.is_friendly(peer_id, multiplayer.get_unique_id())
	var to := _name_tag.global_position - viewer.global_position
	var dist := to.length()
	var show := friendly
	if not friendly and dist < TAG_RANGE:
		var aim := (-viewer.global_basis.z).dot(to / maxf(dist, 0.01))
		show = dist < TAG_NEAR or aim > cos(deg_to_rad(TAG_AIM_DEGREES))
		if show and get_tree().has_group(SmokeCloud.GROUP):
			show = not SmokeCloud.blocks_line(get_tree(), viewer.global_position, _name_tag.global_position)
	_name_tag.visible = show
	if not show:
		return
	# Fade a little with distance so far tags don't clutter the view.
	_name_tag.modulate.a = clampf(remap(dist, 30.0, TAG_RANGE, 1.0, 0.45), 0.45, 1.0)
	_tag_health.visible = friendly
	if friendly:
		var hp := clampf(health.current / health.max_health, 0.0, 1.0)
		var n := ceili(hp * 10.0)
		_tag_health.text = "▮".repeat(n) + "▯".repeat(10 - n)
		_tag_health.modulate = Color(0.45, 0.95, 0.5).lerp(Color(1, 0.3, 0.25), 1.0 - hp)
		_tag_health.modulate.a = _name_tag.modulate.a


## Voice chat indicator on the name tag.
func set_speaking(speaking: bool) -> void:
	_name_tag.modulate = Color(0.45, 1, 0.55) if speaking else Color(1, 1, 1, 0.9)
	_name_tag.text = ("» %s «" if speaking else "%s") % player_name


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _start_slide(horizontal: Vector3) -> void:
	is_sliding = true
	_movement_sound(&"slide", -4.0, 25.0)
	var boosted := horizontal + horizontal.normalized() * slide_boost
	velocity.x = boosted.x
	velocity.z = boosted.z


func _update_slide(delta: float, on_floor: bool, crouch_held: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		horizontal = horizontal.move_toward(Vector3.ZERO, slide_friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if horizontal.length() < slide_end_speed or not crouch_held:
		_end_slide()


func _end_slide() -> void:
	is_sliding = false
	_slide_cooldown_timer = slide_cooldown


func _is_ceiling_blocked() -> bool:
	if _height >= stand_height - 0.01:
		return false
	return test_move(global_transform, Vector3.UP * (stand_height - _height))


func _update_height(delta: float) -> void:
	var target := crouch_height if is_crouching else stand_height
	if is_equal_approx(_height, target):
		return
	_height = move_toward(_height, target, crouch_transition_speed * delta)
	_apply_height()


func _apply_height() -> void:
	_shape.height = _height
	_collision.position.y = _height * 0.5
	head.position.y = _height - eye_offset
	# Keep hitboxes in sync with LagCompensation's analytic shapes.
	var head_center := _height - LagCompensation.HEAD_DROP
	head_hitbox.position.y = head_center - head.position.y
	var body_height := maxf(head_center - LagCompensation.HEAD_RADIUS, LagCompensation.BODY_RADIUS * 2.0)
	_body_hitbox_shape.height = body_height
	body_hitbox.position.y = body_height * 0.5
	_third_person.scale.y = _height / stand_height


func _update_camera(delta: float, on_floor: bool) -> void:
	# Head bob while moving on the ground.
	var speed := Vector2(velocity.x, velocity.z).length()
	var bob := Vector3.ZERO
	if on_floor and speed > 0.5 and not is_sliding:
		_bob_time += delta * speed * head_bob_frequency
		var amount := head_bob_amount * (0.3 if current_weapon and current_weapon.is_aiming else 1.0)
		bob = Vector3(cos(_bob_time * 0.5) * amount, sin(_bob_time) * amount, 0.0)
	camera.position = camera.position.lerp(bob, clampf(delta * 10.0, 0.0, 1.0))

	# Recoil recovers back to centre.
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * recoil_recovery, 0.0, 1.0))
	camera.rotation = Vector3(_recoil.x, _recoil.y, (-0.05 if is_sliding else 0.0) - lean * deg_to_rad(LEAN_ROLL_DEGREES))

	# FOV: sprint widens, ADS zooms.
	var fov := SettingsManager.field_of_view
	if is_sprinting or is_sliding:
		fov += sprint_fov_boost
	if current_weapon:
		fov *= lerpf(1.0, current_weapon.current_ads_fov(), current_weapon.ads_blend)
	camera.fov = lerpf(camera.fov, fov, clampf(delta * 10.0, 0.0, 1.0))


# --- Movement sounds ----------------------------------------------------------

## Footsteps every stride on the ground; louder when sprinting, near-silent crouched.
func _advance_footsteps(moved: float, grounded: bool) -> void:
	if not grounded or is_sliding or moved <= 0.0 or not Audio.is_active():
		return
	_step_distance += moved
	var quiet := is_crouching or (is_walking and not is_sprinting)
	var stride := STRIDE_CROUCH if quiet else (STRIDE_SPRINT if is_sprinting else STRIDE_WALK)
	if _step_distance < stride:
		return
	_step_distance = 0.0
	if not is_local and not _ground_below():
		return
	var loudness: Array = STEP_CROUCH if quiet else (STEP_SPRINT if is_sprinting else STEP_WALK)
	_movement_sound(StringName("step%d" % randi_range(1, 4)), loudness[0], loudness[1])


# --- Controller ----------------------------------------------------------------

## Right-stick look: deadzone + response curve, degrees per second at full
## tilt, ADS slows it like the mouse, aim assist slows it over enemies.
func _pad_look(delta: float) -> void:
	var look := GamepadInput.look_vector(SettingsManager.pad_deadzone,
		GamepadInput.RESPONSE_CURVES[SettingsManager.pad_curve])
	if look == Vector2.ZERO:
		return
	var speed := deg_to_rad(SettingsManager.pad_sensitivity) * delta
	if current_weapon:
		speed *= lerpf(1.0, current_weapon.current_ads_sensitivity() * SettingsManager.ads_sensitivity_scale,
			current_weapon.ads_blend)
	speed *= aim_assist_factor()
	var invert := -1.0 if SettingsManager.pad_invert_y else 1.0
	rotate_y(-look.x * speed)
	# Vertical a bit slower than horizontal, like most console shooters.
	head.rotation.x = clampf(head.rotation.x - look.y * speed * 0.75 * invert,
		-deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))


## < 1 while a controller player's crosshair is on an enemy (or a target dummy):
## makes tracking easier without moving the aim for them.
func aim_assist_factor() -> float:
	if not SettingsManager.aim_assist or not GamepadInput.using_pad:
		return 1.0
	var from := camera.global_position
	var exclude: Array[RID] = [get_rid()]
	for hb: Hitbox in hitboxes:
		exclude.append(hb.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * GamepadInput.AIM_ASSIST_RANGE,
		Weapon.HIT_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hb := hit.get("collider") as Hitbox
	if hb == null or hb.health == null or hb.health.is_dead:
		return 1.0
	var target := hb.health.get_parent() as PlayerController
	if target and Match.is_friendly(peer_id, target.peer_id):
		return 1.0
	if get_tree().has_group(SmokeCloud.GROUP) and SmokeCloud.blocks_line(get_tree(), from, hit.position):
		return 1.0 # no help aiming into smoke
	return GamepadInput.AIM_ASSIST_SLOWDOWN


func _landed(fall_speed: float) -> void:
	_step_distance = STRIDE_WALK * 0.5 # first step comes soon after landing
	_movement_sound(&"land", remap(clampf(fall_speed, 3.0, 12.0), 3.0, 12.0, -10.0, 0.0), 30.0)
	if is_local and fall_speed > 6.0:
		GamepadInput.rumble(0.3, 0.2, 0.12)


## Remote players: steps, jumps and landings guessed from their movement.
func _remote_movement_sounds(previous: Vector3, pos: Vector3) -> void:
	if health.is_dead or not Audio.is_active():
		return
	var moved := Vector2(pos.x - previous.x, pos.z - previous.z).length()
	if moved > 3.0:
		_remote_vy = 0.0 # teleport / respawn
		return
	var vy := (pos.y - previous.y) / get_physics_process_delta_time()
	if _remote_vy < -3.0 and vy > -0.5:
		_landed(-_remote_vy)
	elif vy > 3.5 and _remote_vy < 1.0:
		_movement_sound(&"jump", -10.0, 12.0)
	_remote_vy = vy
	if is_sliding and not _was_sliding:
		_movement_sound(&"slide", -4.0, 25.0)
	_was_sliding = is_sliding
	_advance_footsteps(moved, absf(vy) < 3.0)


func _ground_below() -> bool:
	var from := global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.45, 1)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The local player hears their own movement without panning; others hear it in 3D.
func _movement_sound(sound: StringName, volume_db: float, max_distance: float) -> void:
	if is_local:
		Audio.play_local(sound, volume_db - 8.0, randf_range(0.92, 1.08))
	else:
		Audio.play_3d(sound, global_position + Vector3.UP * 0.2, volume_db, max_distance,
			randf_range(0.92, 1.08), 3.0)


func _on_died(_source: Node) -> void:
	_end_climb()
	if is_local and Match.mode == GameConfig.Mode.BOMB:
		Match.bomb.request_interact(false)
	if throwables and throwables.is_holding():
		throwables.put_away()
	_lean_target = 0.0
	velocity = Vector3.ZERO
	is_sliding = false
	_set_hitboxes_enabled(false)
	_name_tag.visible = false
	if is_local:
		_death_cam()
	elif health.silent_death:
		visible = false
	else:
		# The body falls and stays a while, then it is cleared away.
		_model.play_death(randi() % 8, health.last_hit_headshot)
		var life := _life
		get_tree().create_timer(CORPSE_TIME).timeout.connect(func() -> void:
			if is_instance_valid(self) and health.is_dead and _life == life:
				visible = false)


## Local player: the view drops to the floor and rolls over; the gun goes.
func _death_cam() -> void:
	if current_weapon:
		current_weapon.set_holstered(true)
	var t := create_tween().set_parallel(true)
	t.tween_property(head, "position:y", 0.35, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(camera, "rotation:z", deg_to_rad(randf_range(55.0, 75.0) * (1 if randf() < 0.5 else -1)), 0.8) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(head, "rotation:x", deg_to_rad(-12.0), 0.8)


## Q / E held: -1 / 1, shortened when a wall is in the way; 0 while
## sprinting, sliding or in the air.
func _local_lean_target() -> float:
	if not input_enabled or is_sprinting or is_sliding or not Match.can_move():
		return 0.0
	var want := Input.get_action_strength(&"lean_right") - Input.get_action_strength(&"lean_left")
	if is_zero_approx(want):
		return 0.0
	var side := global_basis.x * signf(want)
	var from := global_position + Vector3.UP * head.position.y
	var reach := LEAN_OFFSET + 0.25
	var q := PhysicsRayQueryParameters3D.create(from, from + side * reach, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var room := maxf(from.distance_to(hit.position) - 0.25, 0.0)
		want = signf(want) * minf(absf(want), room / LEAN_OFFSET)
	return clampf(want, -1.0, 1.0)


## Head (camera, head hitbox) slides sideways; the third-person body tilts
## so its head ends up in the same place.
func _apply_lean() -> void:
	head.position.x = lean * LEAN_OFFSET
	_third_person.rotation.z = -lean * asin(LEAN_OFFSET / maxf(_height - LagCompensation.HEAD_DROP, 1.0))


func _set_hitboxes_enabled(enabled: bool) -> void:
	for hb: Hitbox in hitboxes:
		hb.get_node("CollisionShape3D").set_deferred("disabled", not enabled)
