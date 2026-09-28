class_name ClimbHands
extends Node3D
## First-person hands while climbing (Climb): both gloved hands slap down on
## the ledge and stay there while the player pulls up past them, the
## forearms reaching back to the shoulders; they let go at the top.
## Local player only, visual only.

const HAND_SPREAD := 0.28
const REACH_TIME := 0.12

var _camera: Camera3D
var _hands: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
var _grip: Array[Vector3] = []
var _age := 0.0

static var _hand_mesh: ArrayMesh
static var _arm_mesh: CylinderMesh


## `edge`: the landing point on top of the ledge; `forward`: towards the ledge.
func grab(edge: Vector3, forward: Vector3, camera: Camera3D) -> void:
	_camera = camera
	top_level = true
	if _hand_mesh == null:
		var b := MeshBuilder.new()
		b.box(&"glove", Vector3(0.09, 0.035, 0.11), Vector3(0, 0.017, 0))
		b.box(&"glove_pad", Vector3(0.095, 0.02, 0.03), Vector3(0, 0.03, -0.04))
		b.box(&"glove", Vector3(0.03, 0.025, 0.05), Vector3(-0.05, 0.012, 0.03), Vector3(0, 25, 0))
		_hand_mesh = b.build()
		_arm_mesh = CylinderMesh.new()
		_arm_mesh.top_radius = 0.038
		_arm_mesh.bottom_radius = 0.05
		_arm_mesh.height = 1.0
		_arm_mesh.radial_segments = 8
		_arm_mesh.rings = 1
		_arm_mesh.material = MeshBuilder.shared_material()
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	# Hands on the edge (a little back from the landing point).
	var at := edge - forward * 0.3 + Vector3.UP * 0.01
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.22, 0.25, 0.2)
	sleeve.roughness = 0.9
	for side in [-1.0, 1.0]:
		var hand := MeshInstance3D.new()
		hand.mesh = _hand_mesh
		hand.material_override = null
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hand)
		hand.global_position = at + right * side * HAND_SPREAD
		hand.global_basis = Basis.looking_at(forward, Vector3.UP)
		_hands.append(hand)
		_grip.append(hand.global_position)
		var arm := MeshInstance3D.new()
		arm.mesh = _arm_mesh
		arm.material_override = sleeve
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arm)
		_arms.append(arm)
	_update_arms()


func _process(delta: float) -> void:
	_age += delta
	_update_arms()


## Each forearm from the wrist back towards its shoulder, below the camera.
func _update_arms() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var cam := _camera.global_transform
	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		# The hand drops onto the edge from a little higher up.
		var drop := clampf(1.0 - _age / REACH_TIME, 0.0, 1.0)
		_hands[i].global_position = _grip[i] + Vector3.UP * 0.25 * drop
		var wrist := _hands[i].global_position + (cam.origin - _hands[i].global_position).normalized() * 0.08
		var shoulder := cam.origin + cam.basis.x * side * 0.2 - cam.basis.y * 0.28 + cam.basis.z * 0.05
		var mid := (wrist + shoulder) * 0.5
		var length := wrist.distance_to(shoulder)
		var up := (wrist - shoulder).normalized()
		var arm := _arms[i]
		var basis := Basis.looking_at(up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD), up)
		arm.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, length, 1)), mid)


## Let go (end of the climb): the hands are gone next frame.
func release() -> void:
	queue_free()
