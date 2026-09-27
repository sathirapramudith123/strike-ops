class_name PlayerController
extends CharacterBody3D
## First-person player: mouse look, walk / sprint / crouch / slide / jump,
## camera effects (head bob, FOV kick, recoil) and weapon handling.
##
## Scene layout (see scenes/player/player.tscn):
##   Player (CharacterBody3D)
##   ├── CollisionShape3D (CapsuleShape3D, local to scene)
##   ├── Health
##   └── Head (Node3D)                 ← pitch
##       └── Camera3D                  ← recoil + head bob
##           └── WeaponHolder (Node3D) ← weapons as children

signal respawned

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.6
@export var ground_acceleration: float = 12.0
@export var ground_deceleration: float = 14.0
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

var input_enabled: bool = true
var is_sprinting: bool = false
var is_crouching: bool = false
var is_sliding: bool = false
var current_weapon: Weapon

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var health: Health = $Health
@onready var _shape: CapsuleShape3D = $CollisionShape3D.shape
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _height: float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _bob_time: float = 0.0
var _recoil := Vector2.ZERO # (pitch, yaw) in radians, applied to the camera
var _spawn_transform: Transform3D
var _respawn_timer: float = 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	_height = stand_height
	_apply_height()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SettingsManager.apply_to_camera(camera)
	SettingsManager.graphics_changed.connect(func(_p: GraphicsPreset) -> void: SettingsManager.apply_to_camera(camera))
	health.died.connect(_on_died)

	for child in weapon_holder.get_children():
		if child is Weapon:
			(child as Weapon).unequip()
	if weapon_holder.get_child_count() > 0:
		equip_weapon(weapon_holder.get_child(0) as Weapon)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := SettingsManager.mouse_sensitivity * 0.01
		if current_weapon:
			sens *= lerpf(1.0, current_weapon.data.ads_sensitivity_multiplier, current_weapon.ads_blend)
		var invert := -1.0 if SettingsManager.invert_y else 1.0
		rotate_y(-motion.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * sens * invert,
			-deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if health.is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return

	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var on_floor := is_on_floor()

	# --- Timers -------------------------------------------------------------
	_coyote_timer = coyote_time if on_floor else _coyote_timer - delta
	_jump_buffer_timer -= delta
	_slide_cooldown_timer -= delta
	if input_enabled and Input.is_action_just_pressed(&"jump"):
		_jump_buffer_timer = jump_buffer_time

	# --- Gravity ------------------------------------------------------------
	if not on_floor:
		velocity.y -= _gravity * delta

	# --- Crouch / slide state -------------------------------------------------
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var crouch_held := input_enabled and (Input.is_action_pressed(&"crouch") or Input.is_action_pressed(&"slide"))
	var crouch_pressed := input_enabled and (Input.is_action_just_pressed(&"crouch") or Input.is_action_just_pressed(&"slide"))

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
		if current_weapon:
			speed *= lerpf(1.0, current_weapon.data.ads_move_speed_multiplier, current_weapon.ads_blend)

		var target := wish_dir * speed
		var accel := air_acceleration
		if on_floor:
			accel = ground_acceleration if wish_dir != Vector3.ZERO else ground_deceleration
		horizontal = horizontal.move_toward(target, accel * speed * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# --- Jump ---------------------------------------------------------------
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not blocked_above:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		if is_sliding:
			_end_slide() # slide-jump keeps the momentum

	move_and_slide()

	_update_height(delta)
	_update_camera(delta, on_floor)

	if global_position.y < fall_limit_y:
		respawn()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func equip_weapon(weapon: Weapon) -> void:
	if current_weapon:
		current_weapon.unequip()
	current_weapon = weapon
	if weapon:
		weapon.equip(self, camera)


## Called by weapons. Values are in degrees.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	_recoil.x += deg_to_rad(pitch_degrees)
	_recoil.y += deg_to_rad(yaw_degrees)


func set_spawn_transform(t: Transform3D) -> void:
	_spawn_transform = t


func respawn() -> void:
	global_transform = _spawn_transform
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_recoil = Vector2.ZERO
	is_sliding = false
	health.revive()
	respawned.emit()


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _start_slide(horizontal: Vector3) -> void:
	is_sliding = true
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
	camera.rotation = Vector3(_recoil.x, _recoil.y, -0.05 if is_sliding else 0.0)

	# FOV: sprint widens, ADS zooms.
	var fov := SettingsManager.field_of_view
	if is_sprinting or is_sliding:
		fov += sprint_fov_boost
	if current_weapon:
		fov *= lerpf(1.0, current_weapon.data.ads_fov_multiplier, current_weapon.ads_blend)
	camera.fov = lerpf(camera.fov, fov, clampf(delta * 10.0, 0.0, 1.0))


func _on_died(_source: Node) -> void:
	_respawn_timer = respawn_delay
	velocity = Vector3.ZERO
	is_sliding = false
