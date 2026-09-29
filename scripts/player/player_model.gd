class_name PlayerModel
extends Node3D
## Third-person soldier built from code (until real art) after the player's
## CharacterLook (CharacterMesh: body, face, hair, outfit and kit), with the
## shoulder pads, armbands, a chest patch and the helmet band in the team
## colour; arms holding the current weapon, and legs (thigh + shin, bent
## at the knee) that walk in step with how far the player moves. Reloading tips the gun and swings the left arm down to swap the
## magazine. Five mesh nodes, about eight draw calls; identical looks share
## their meshes.

const HIP := Vector3(0.1, 0.9, 0.0)
## The knee, from the hip.
const KNEE := Vector3(0.0, -0.44, -0.02)
## How far a crouch lowers the model.
const CROUCH_DROP := 0.34
const L_SHOULDER := Vector3(-0.23, 1.42, 0.0)
const GUN_POS := Vector3(0.1, 1.3, -0.32)

var _body: MeshInstance3D
var _legs: Array[MeshInstance3D] = [] # thighs
var _shins: Array[MeshInstance3D] = []
var _gun: MeshInstance3D
var _arm_l: MeshInstance3D
var _reload_time := 0.0
var _reload_left := 0.0
var _armor: ShaderMaterial
var _phase: float = 0.0
var _speed: float = 0.0 # smoothed ground speed
var _crouch: float = 0.0 # 0 standing … 1 crouched
var _last_pos: Vector3
var _has_last: bool = false
## Dead: the death animation owns the pose (animate() leaves it alone).
var _dead: bool = false
var _death_tween: Tween
var _dropped_gun: RigidBody3D
var _look: Dictionary = CharacterLook.default_look()


func _ready() -> void:
	_armor = MeshBuilder.tinted_material()
	_body = MeshInstance3D.new()
	_body.name = "Body"
	add_child(_body)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		leg.position = Vector3(side * HIP.x, HIP.y, 0.0)
		add_child(leg)
		_legs.append(leg)
		var shin := MeshInstance3D.new()
		shin.name = "Shin"
		shin.position = KNEE
		leg.add_child(shin)
		_shins.append(shin)
	_arm_l = MeshInstance3D.new()
	_arm_l.name = "ArmL"
	_arm_l.position = L_SHOULDER
	add_child(_arm_l)
	_gun = MeshInstance3D.new()
	_gun.name = "Gun"
	_gun.position = GUN_POS
	add_child(_gun)
	_apply_meshes()


## Dresses the model after a CharacterLook (see CharacterLook / CharacterMesh).
func set_look(look: Dictionary) -> void:
	var clean: Dictionary = CharacterLook.sanitize(look)
	if CharacterLook.key_of(clean) == CharacterLook.key_of(_look) and _body and _body.mesh:
		return
	_look = clean
	if _body:
		_apply_meshes()


## A glowing edge in `color` round the soldier (teammates); a transparent
## colour removes it.
func set_outline(color: Color) -> void:
	var on := color.a > 0.0
	var mat: ShaderMaterial = null
	if on:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/outline.gdshader")
		mat.set_shader_parameter(&"color", color)
	for mi: MeshInstance3D in [_body, _legs[0], _legs[1], _shins[0], _shins[1], _arm_l]:
		if mi:
			mi.material_overlay = mat


func get_look() -> Dictionary:
	return _look


func _apply_meshes() -> void:
	var meshes: Dictionary = CharacterMesh.get_meshes(_look)
	_body.mesh = meshes.body
	_legs[0].mesh = meshes.leg
	_legs[1].mesh = meshes.leg
	_shins[0].mesh = meshes.shin
	_shins[1].mesh = meshes.shin
	_arm_l.mesh = meshes.arm_l
	for mi: MeshInstance3D in [_body, _legs[0], _legs[1], _shins[0], _shins[1], _arm_l]:
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, null)
		var idx := MeshBuilder.surface_of(mi.mesh, &"armor")
		if idx >= 0:
			mi.set_surface_override_material(idx, _armor)


func set_team_color(color: Color) -> void:
	if _armor:
		_armor.set_shader_parameter(&"tint", color)


func set_weapon(weapon_id: String) -> void:
	if _gun:
		_gun.mesh = WeaponModel.get_mesh(weapon_id) if WeaponModel.has_model(weapon_id) else null


## Plays the reload motion over `duration` seconds.
func start_reload(duration: float) -> void:
	_reload_time = maxf(duration, 0.1)
	_reload_left = _reload_time


func stop_reload() -> void:
	_reload_left = 0.0


func is_reloading() -> bool:
	return _reload_left > 0.0


## Death: a stagger, the knees give, a fall to the ground with a small
## bounce, arms flopping, the gun dropping out of the hands. `style` picks
## the fall (0 backwards, 1 forwards, 2 twisting to the side, 3 crumpling
## down); a headshot snaps the head back first.
func play_death(style: int, headshot: bool) -> void:
	_dead = true
	if _death_tween:
		_death_tween.kill()
	_reload_left = 0.0
	var fall_x := 0.0 # pitch of the whole body (+ = backwards)
	var fall_z := 0.0 # roll
	var twist := 0.0
	match style % 4:
		0:
			fall_x = 1.5
		1:
			fall_x = -1.45
		2:
			fall_x = 0.4
			fall_z = 1.45 * (1.0 if style % 8 < 4 else -1.0)
			twist = 0.7
		_:
			# Crumple to the knees, then slump onto the side.
			fall_x = -0.5
			fall_z = -1.35
	var t := create_tween()
	_death_tween = t
	# Stagger: jolted by the hit (a headshot throws the upper body back).
	t.set_parallel(true)
	t.tween_property(self, "rotation:x", 0.35 if headshot else 0.12 * signf(fall_x + 0.01), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_arm_l, "rotation:x", -1.6, 0.25)
	t.tween_property(_arm_l, "rotation:z", -0.6, 0.25)
	t.chain().set_parallel(true)
	# The knees give way.
	for leg: MeshInstance3D in _legs:
		t.tween_property(leg, "rotation:x", -1.3, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for shin: MeshInstance3D in _shins:
		t.tween_property(shin, "rotation:x", -0.9, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", -0.3 if style % 4 != 3 else -0.5, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "rotation:y", twist, 0.5)
	t.chain().set_parallel(true)
	# Topple over — gravity: slow start, fast finish — and a little bounce.
	t.tween_property(self, "rotation:x", fall_x * 1.05, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "rotation:z", fall_z * 1.05, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", 0.1 if style % 4 != 3 else 0.0, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for i in _legs.size():
		t.tween_property(_legs[i], "rotation:x", -0.2 - 0.5 * i, 0.42)
		t.tween_property(_shins[i], "rotation:x", -0.3 - 0.4 * i, 0.42)
	t.chain().set_parallel(true)
	t.tween_property(self, "rotation:x", fall_x, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation:z", fall_z, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_drop_gun()


## Back to standing (respawn).
func reset_pose() -> void:
	_dead = false
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	for leg: MeshInstance3D in _legs:
		leg.rotation = Vector3.ZERO
	for shin: MeshInstance3D in _shins:
		shin.rotation = Vector3.ZERO
	_speed = 0.0
	_has_last = false
	_arm_l.rotation = Vector3.ZERO
	_gun.visible = true
	if is_instance_valid(_dropped_gun):
		_dropped_gun.queue_free()


## The gun falls out of the hands and clatters to the ground (visual only).
func _drop_gun() -> void:
	if _gun.mesh == null or not is_inside_tree():
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = _gun.mesh
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.14, 0.7)
	shape.shape = box
	body.add_child(shape)
	var parent: Node = get_tree().current_scene if get_tree().current_scene else self
	parent.add_child(body)
	body.global_transform = _gun.global_transform
	body.linear_velocity = global_basis * Vector3(randf_range(-0.8, 0.8), 1.2, -1.0)
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	_gun.visible = false
	_dropped_gun = body
	get_tree().create_timer(12.0).timeout.connect(body.queue_free)


## Walk cycle from how far the player moved (works for remote players too).
## Positions change at the physics rate, not every drawn frame, so the
## speed is smoothed over a few frames. The legs step in time with the
## distance covered (a stride as long as the swing reaches — no sliding
## feet): the thigh swings, the knee bends as the leg comes through, the
## body bobs twice a cycle. Crouching lowers the model onto bent knees
## (both feet on the ground, one knee lower).
func animate(delta: float, crouching: bool) -> void:
	if _dead or delta <= 0.0:
		return
	_animate_reload(delta)
	var pos := global_position
	var moved := 0.0
	if _has_last:
		moved = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if moved > 3.0:
			moved = 0.0 # teleport / respawn
	_last_pos = pos
	_has_last = true
	_speed = lerpf(_speed, moved / delta, 1.0 - exp(-delta * 8.0))
	if _speed < 0.05:
		_speed = 0.0
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 6.0)
	var amount := clampf(_speed / 4.0, 0.0, 1.0)
	# Thigh swing either way; one step covers the ground the feet span (a
	# little more: running has a moment with both feet off the ground).
	var swing := lerpf(0.22, 0.5, clampf(_speed / 6.5, 0.0, 1.0)) * (1.0 - 0.45 * _crouch)
	var step := maxf(2.0 * (-KNEE.y + 0.45) * sin(swing) * lerpf(1.0, 1.4, amount), 0.25)
	_phase = fmod(_phase + _speed * delta * PI / step, TAU)
	var k := clampf(delta * 16.0, 0.0, 1.0)
	for i in 2:
		var ph := _phase + PI * i
		# Crouch pose: thighs forward, shins folded back under, one knee lower.
		var thigh := sin(ph) * swing * amount + _crouch * (1.05 - 0.35 * i)
		var knee := -maxf(cos(ph), 0.0) * (0.35 + 0.6 * amount) * amount - 0.08 * amount - _crouch * 1.75
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, thigh, k)
		_shins[i].rotation.x = lerpf(_shins[i].rotation.x, knee, k)
	var drop := CROUCH_DROP * _crouch
	var bob := -absf(cos(_phase)) * 0.035 * amount + 0.02 * amount
	_body.position.y = bob - drop
	_arm_l.position.y = L_SHOULDER.y + bob - drop
	_gun.position.y = GUN_POS.y + bob - drop
	for i in 2:
		_legs[i].position.y = HIP.y + bob - drop


## Reload: gun tips over, left hand drops to pull the magazine, goes down
## again for a fresh one and pushes it in, then back to the hand-guard.
func _animate_reload(delta: float) -> void:
	var arm := 0.0
	var tip := 0.0
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		var p := 1.0 - _reload_left / _reload_time
		tip = smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.8, 1.0, p))
		# Two dips: magazine out (0.1–0.35), new magazine in (0.35–0.65).
		arm = -0.55 * absf(sin(clampf((p - 0.1) / 0.55, 0.0, 1.0) * TAU))
	var k := clampf(delta * 16.0, 0.0, 1.0)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm, k)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.25 * absf(arm), k)
	_gun.rotation.z = lerpf(_gun.rotation.z, 0.55 * tip, k)
	_gun.rotation.x = lerpf(_gun.rotation.x, 0.15 * tip, k)
