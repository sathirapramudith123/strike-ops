class_name FPArms
extends Node3D
## Realistic first-person arms (README → Realistic soldiers): the rifleman's
## multicam sleeves and tan gloves (assets/characters/rifleman/fp_arms.glb,
## the same skeleton as the soldier) instead of the code-built ArmR / ArmL
## meshes. Those parts keep moving as before — recoil, sway, reload, inspect
## — and are used as targets: a two-bone IK bends each elbow so the wrist
## reaches its part, the hand turned as it holds a rifle in Mixamo's aiming
## pose and the fingers in its grip. The shoulders stay put under the camera,
## the left one forward as in a rifle stance.

const SCENE := "res://assets/characters/rifleman/fp_arms.glb"
const BONE := "mixamorig_"
## Where the shoulders sit, camera space (the left forward for a rifle).
const SHOULDER_R := Vector3(0.22, -0.38, 0.08)
const SHOULDER_L := Vector3(0.04, -0.4, -0.22)
## The hands relative to the gun in the rifleman's aiming pose (measured):
## wrist minus palm (gun space) and the hand's rotation.
const WRIST_FROM_PALM_R := Vector3(-0.010, -0.028, 0.056)
const HAND_ROT_R := Quaternion(-0.53914, 0.048417, -0.041376, 0.839805)
const WRIST_FROM_PALM_L := Vector3(-0.059, -0.012, 0.018)
const HAND_ROT_L := Quaternion(0.57739, 0.808362, -0.071025, -0.090146)

var weapon: Weapon
var skeleton: Skeleton3D
var _ik: _ArmIK


func _ready() -> void:
	var model := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fingers in the rifle grip (the soldier's clips, see SoldierRig).
	var lib := load(SoldierRig.ANIMS) as AnimationLibrary
	SoldierRig._strip_fingers(lib)
	for bone_name: String in SoldierRig._finger_pose:
		var b := skeleton.find_bone(bone_name)
		if b >= 0:
			skeleton.set_bone_pose_rotation(b, SoldierRig._finger_pose[bone_name])
	# Turn and place the skeleton so its shoulders land on SHOULDER_R / _L
	# (it is modelled facing +Z; the camera looks down -Z).
	var sr := skeleton.get_bone_global_rest(skeleton.find_bone(BONE + "RightArm")).origin
	var sl := skeleton.get_bone_global_rest(skeleton.find_bone(BONE + "LeftArm")).origin
	var have := Vector2(sl.x - sr.x, sl.z - sr.z)
	var want := Vector2(SHOULDER_L.x - SHOULDER_R.x, SHOULDER_L.z - SHOULDER_R.z)
	var yaw := have.angle() - want.angle()
	model.basis = Basis(Vector3.UP, yaw)
	model.position = SHOULDER_R - model.basis * sr
	_ik = _ArmIK.new()
	_ik.arms = self
	skeleton.add_child(_ik)


func _process(_delta: float) -> void:
	# Shown with the gun's own model (not while scoped or holding a grenade).
	var model := weapon.get_node_or_null(^"Model") as Node3D if is_instance_valid(weapon) else null
	visible = model != null and model.is_visible_in_tree()


## How far each wrist is from where the gun wants it (m), after the last frame.
func wrist_miss(side: String) -> float:
	return float(_ik.miss.get(side, 0.0))


## Where a hand's wrist should be and how it is turned (global), from the
## weapon's arm part: the palm on `palm` (weapon space) of that part.
func _hand_target(part: Node3D, palm: Vector3, wrist_from_palm: Vector3, rot: Quaternion) -> Transform3D:
	var t := weapon.global_transform * part.transform
	return Transform3D(t.basis * Basis(rot), t * (palm + wrist_from_palm))


class _ArmIK extends SkeletonModifier3D:
	var arms: FPArms
	## After the last solve: how far each wrist ended from its target (m).
	var miss := { "Right": 0.0, "Left": 0.0 }

	func _process_modification() -> void:
		var s := get_skeleton()
		var w := arms.weapon if arms and is_instance_valid(arms.weapon) else null
		if s == null or w == null or not w.is_inside_tree() or not arms.visible:
			return
		var hands: Dictionary = WeaponModel.HANDS.get(w.data.weapon_id, WeaponModel.HANDS["rifle"])
		if w._right_arm:
			_solve(s, "Right", arms._hand_target(w._right_arm, hands.grip, FPArms.WRIST_FROM_PALM_R, FPArms.HAND_ROT_R), Vector3(1, -1, 0.3))
		if w._left_arm and hands.left_kind != "none":
			_solve(s, "Left", arms._hand_target(w._left_arm, hands.left, FPArms.WRIST_FROM_PALM_L, FPArms.HAND_ROT_L), Vector3(-1, -1, 0.3))

	## Two-bone IK: upper arm + forearm so the hand bone's origin reaches the
	## target, the elbow bending towards `pole` (camera space: out and down);
	## then the hand takes the target's rotation.
	func _solve(s: Skeleton3D, side: String, target: Transform3D, pole: Vector3) -> void:
		var arm := s.find_bone(FPArms.BONE + side + "Arm")
		var fore := s.find_bone(FPArms.BONE + side + "ForeArm")
		var hand := s.find_bone(FPArms.BONE + side + "Hand")
		var to_skel := s.global_transform.affine_inverse()
		var t := to_skel * target.origin
		var t_basis := to_skel.basis * target.basis
		var a_g := s.get_bone_global_pose(arm)
		var f_g := s.get_bone_global_pose(fore)
		var h_g := s.get_bone_global_pose(hand)
		var a_len := a_g.origin.distance_to(f_g.origin)
		var b_len := f_g.origin.distance_to(h_g.origin)
		var root := a_g.origin
		var to_t := t - root
		var d := clampf(to_t.length(), absf(a_len - b_len) + 0.01, a_len + b_len - 0.001)
		var dir := to_t.normalized()
		var pole_dir := (to_skel.basis * (arms.get_parent_node_3d().global_basis * pole)).normalized() if arms.get_parent_node_3d() else Vector3.DOWN
		var bend := (pole_dir - dir * dir.dot(pole_dir)).normalized()
		var x := (a_len * a_len - b_len * b_len + d * d) / (2.0 * d)
		var h := sqrt(maxf(a_len * a_len - x * x, 0.0))
		var elbow := root + dir * x + bend * h
		var wrist := root + dir * d
		# Upper arm: swing its bone axis (+Y) onto shoulder -> elbow.
		var a_new := Basis(Quaternion(a_g.basis.y.normalized(), (elbow - root).normalized())) * a_g.basis
		_set_global(s, arm, a_new)
		# Forearm: the same, from the elbow to the wrist.
		f_g = s.get_bone_global_pose(fore)
		var f_new := Basis(Quaternion(f_g.basis.y.normalized(), (wrist - elbow).normalized())) * f_g.basis
		_set_global(s, fore, f_new)
		_set_global(s, hand, t_basis.orthonormalized() * Basis.from_scale(h_g.basis.get_scale()))
		miss[side] = s.get_bone_global_pose(hand).origin.distance_to(t)

	func _set_global(s: Skeleton3D, bone: int, global_basis: Basis) -> void:
		var parent := s.get_bone_parent(bone)
		var p := s.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		s.set_bone_pose_rotation(bone, (p.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())
