class_name PlayerModel
extends Node3D
## Third-person soldier built from code (until real art): helmet, vest and
## shoulder pads in the team colour, fabric uniform, backpack, arms holding the
## current weapon, and legs that swing while walking. Four mesh nodes and five
## draw calls (body + armor, 2 legs, gun); the meshes are built once and shared.

const HIP := Vector3(0.1, 0.9, 0.0)

static var _body_mesh: ArrayMesh
static var _leg_mesh: ArrayMesh

var _body: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _gun: MeshInstance3D
var _armor: ShaderMaterial
var _phase: float = 0.0
var _last_pos: Vector3
var _has_last: bool = false


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
	_gun = MeshInstance3D.new()
	_gun.name = "Gun"
	_gun.position = Vector3(0.1, 1.3, -0.32)
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


## Walk cycle from how far the player moved (works for remote players too).
func animate(delta: float, crouching: bool) -> void:
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
	var l_shoulder := Vector3(-0.23, 1.42, 0.0)
	var l_elbow := Vector3(-0.2, 1.22, -0.3)
	var l_hand := Vector3(0.05, 1.3, -0.52)
	b.limb(&"fabric", r_shoulder, r_elbow, 0.055, 0.05)
	b.limb(&"fabric", r_elbow, r_hand, 0.048, 0.042)
	b.limb(&"fabric", l_shoulder, l_elbow, 0.055, 0.05)
	b.limb(&"fabric", l_elbow, l_hand, 0.048, 0.042)
	b.sphere(&"gear", 0.045, r_hand) # gloves
	b.sphere(&"gear", 0.045, l_hand)
	_body_mesh = b.build()

	# One leg, pivoting at the hip (origin): thigh, knee pad, shin, boot.
	var l := MeshBuilder.new()
	l.limb(&"fabric", Vector3(0, 0.02, 0), Vector3(0, -0.44, -0.02), 0.075, 0.062)
	l.sphere(&"gear", 0.06, Vector3(0, -0.45, -0.06), Vector3(1, 1.1, 0.7)) # knee pad
	l.limb(&"fabric", Vector3(0, -0.44, -0.02), Vector3(0, -0.82, 0.0), 0.058, 0.05)
	l.box(&"gear", Vector3(0.11, 0.09, 0.24), Vector3(0, -0.855, -0.04)) # boot
	_leg_mesh = l.build()
