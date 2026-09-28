class_name PlayerModel
extends Node3D
## Third-person soldier built from code (until real art): helmet, vest and
## shoulder pads in the team colour, fabric uniform, backpack, arms holding the
## current weapon, and legs that swing while walking. Reloading tips the gun
## and swings the left arm down to swap the magazine. Five mesh nodes, six
## draw calls (body + armor, 2 legs, left arm, gun); the meshes are shared.

const HIP := Vector3(0.1, 0.9, 0.0)
const L_SHOULDER := Vector3(-0.23, 1.42, 0.0)
const GUN_POS := Vector3(0.1, 1.3, -0.32)

static var _body_mesh: ArrayMesh
static var _leg_mesh: ArrayMesh
static var _arm_l_mesh: ArrayMesh

var _body: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _gun: MeshInstance3D
var _arm_l: MeshInstance3D
var _reload_time := 0.0
var _reload_left := 0.0
var _armor: ShaderMaterial
var _phase: float = 0.0
var _last_pos: Vector3
var _has_last: bool = false
## Dead: the death animation owns the pose (animate() leaves it alone).
var _dead: bool = false
var _death_tween: Tween
var _dropped_gun: RigidBody3D


func _ready() -> void:
	if _body_mesh == null:
		_build_meshes()
	_armor = MeshBuilder.tinted_material()
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = _body_mesh
	add_child(_body)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		leg.mesh = _leg_mesh
		leg.position = Vector3(side * HIP.x, HIP.y, 0.0)
		add_child(leg)
		_legs.append(leg)
	_arm_l = MeshInstance3D.new()
	_arm_l.name = "ArmL"
	_arm_l.mesh = _arm_l_mesh
	_arm_l.position = L_SHOULDER
	add_child(_arm_l)
	_gun = MeshInstance3D.new()
	_gun.name = "Gun"
	_gun.position = GUN_POS
	add_child(_gun)
	for mi: MeshInstance3D in [_body, _legs[0], _legs[1]]:
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
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.queue_free())


## Walk cycle from how far the player moved (works for remote players too).
func animate(delta: float, crouching: bool) -> void:
	if _dead:
		return
	_animate_reload(delta)
	var pos := global_position
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	_has_last = true
	if speed > 12.0:
		speed = 0.0 # teleport / respawn
	var amount := clampf(speed / 5.0, 0.0, 1.0)
	_phase += delta * speed * 1.9
	var swing := sin(_phase) * 0.55 * amount
	var target_l := swing
	var target_r := -swing
	if crouching:
		target_l = -0.9
		target_r = -0.9
	var k := clampf(delta * 14.0, 0.0, 1.0)
	_legs[0].rotation.x = lerpf(_legs[0].rotation.x, target_l, k)
	_legs[1].rotation.x = lerpf(_legs[1].rotation.x, target_r, k)
	_body.position.y = absf(sin(_phase)) * 0.03 * amount


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


static func _build_meshes() -> void:
	var b := MeshBuilder.new()
	# Torso, vest, belt, backpack.
	b.box(&"fabric", Vector3(0.38, 0.5, 0.22), Vector3(0, 1.22, 0))
	b.box(&"armor", Vector3(0.42, 0.34, 0.27), Vector3(0, 1.28, -0.005))
	b.box(&"gear", Vector3(0.1, 0.07, 0.03), Vector3(-0.1, 1.2, -0.145)) # pouches
	b.box(&"gear", Vector3(0.1, 0.07, 0.03), Vector3(0.05, 1.2, -0.145))
	b.box(&"gear", Vector3(0.36, 0.06, 0.24), Vector3(0, 0.98, 0)) # belt
	b.box(&"fabric", Vector3(0.34, 0.14, 0.22), Vector3(0, 0.92, 0)) # hips
	b.box(&"gear", Vector3(0.3, 0.36, 0.14), Vector3(0, 1.28, 0.19)) # backpack
	b.box(&"gear", Vector3(0.26, 0.08, 0.1), Vector3(0, 1.5, 0.19))
	# Neck, head, helmet, visor.
	b.cylinder_y(&"skin", 0.055, 0.1, Vector3(0, 1.5, 0))
	b.sphere(&"skin", 0.105, Vector3(0, 1.62, -0.01), Vector3(1, 1.1, 1))
	b.sphere(&"armor", 0.135, Vector3(0, 1.64, 0.005), Vector3(1, 0.85, 1.05), true)
	b.box(&"armor", Vector3(0.27, 0.025, 0.28), Vector3(0, 1.645, 0.005)) # helmet rim
	b.box(&"visor", Vector3(0.19, 0.055, 0.04), Vector3(0, 1.63, -0.105))
	# Shoulders + arms holding the gun at chest height.
	for sx in [-1.0, 1.0]:
		b.sphere(&"armor", 0.075, Vector3(sx * 0.23, 1.44, 0), Vector3(1, 0.8, 1))
	var r_shoulder := Vector3(0.23, 1.42, 0.0)
	var r_elbow := Vector3(0.26, 1.2, -0.12)
	var r_hand := Vector3(0.1, 1.27, -0.3)
	b.limb(&"fabric", r_shoulder, r_elbow, 0.055, 0.05)
	b.limb(&"fabric", r_elbow, r_hand, 0.048, 0.042)
	b.sphere(&"gear", 0.045, r_hand) # glove
	_body_mesh = b.build()

	# Left arm on its own node, pivoting at the shoulder (reload motion).
	var a := MeshBuilder.new()
	var l_elbow := Vector3(-0.2, 1.22, -0.3) - L_SHOULDER
	var l_hand := Vector3(0.05, 1.3, -0.52) - L_SHOULDER
	a.limb(&"fabric", Vector3.ZERO, l_elbow, 0.055, 0.05)
	a.limb(&"fabric", l_elbow, l_hand, 0.048, 0.042)
	a.sphere(&"gear", 0.045, l_hand)
	_arm_l_mesh = a.build()

	# One leg, pivoting at the hip (origin): thigh, knee pad, shin, boot.
	var l := MeshBuilder.new()
	l.limb(&"fabric", Vector3(0, 0.02, 0), Vector3(0, -0.44, -0.02), 0.075, 0.062)
	l.sphere(&"gear", 0.06, Vector3(0, -0.45, -0.06), Vector3(1, 1.1, 0.7)) # knee pad
	l.limb(&"fabric", Vector3(0, -0.44, -0.02), Vector3(0, -0.82, 0.0), 0.058, 0.05)
	l.box(&"gear", Vector3(0.11, 0.09, 0.24), Vector3(0, -0.855, -0.04)) # boot
	_leg_mesh = l.build()
