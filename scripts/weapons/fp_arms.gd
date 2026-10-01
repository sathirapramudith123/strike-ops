class_name FPArms
extends Node3D
## Realistic first-person arms (README → Realistic soldiers): the soldier's
## own sleeves and gloves (assets/characters/ksk/ksk_fp_arms.glb, the same
## skeleton as SoldierRig) instead of the code-built ArmR / ArmL meshes.
## Those parts keep moving as before — recoil, sway, reload, inspect — and
## are the targets: each hand goes where it sits on the gun in the soldier's
## aiming pose (RifleGrip.hold) relative to its part, a two-bone IK bending
## the elbow, fingers in the rifle grip. A left fist round a grip (pistol
## support, vertical front grip) is the right hand's grip mirrored. The
## shoulders stay put under the camera, the left one forward.

const SCENE := "res://assets/characters/ksk/ksk_fp_arms.glb"
const BONE := "mixamorig_"
## Where the shoulders sit, camera space (the left forward for a rifle).
const SHOULDER_R := Vector3(0.22, -0.38, 0.08)
const SHOULDER_L := Vector3(0.04, -0.4, -0.22)
const MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

var weapon: Weapon
var skeleton: Skeleton3D
var _ik: _ArmIK
var _lib: AnimationLibrary
## Left/right hand bone axes differ by a mirror: fix-up for mirrored fists.
var _mirror_fix := Basis.IDENTITY


func _ready() -> void:
	var model := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fingers in the rifle grip (the soldier's clips, see SoldierRig).
	_lib = load(SoldierRig.ANIMS) as AnimationLibrary
	SoldierRig._strip_fingers(_lib)
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
	model.basis = Basis(Vector3.UP, have.angle() - want.angle())
	model.position = SHOULDER_R - model.basis * sr
	var r_rest := skeleton.get_bone_global_rest(skeleton.find_bone(BONE + "RightHand")).basis.orthonormalized()
	var l_rest := skeleton.get_bone_global_rest(skeleton.find_bone(BONE + "LeftHand")).basis.orthonormalized()
	_mirror_fix = (MIRROR_X * r_rest * MIRROR_X).inverse() * l_rest
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


class _ArmIK extends SkeletonModifier3D:
	var arms: FPArms
	## After the last solve: how far each wrist ended from its target (m).
	var miss := { "Right": 0.0, "Left": 0.0 }

	func _process_modification() -> void:
		var s := get_skeleton()
		var w := arms.weapon if arms and is_instance_valid(arms.weapon) else null
		if s == null or w == null or not w.is_inside_tree() or not arms.visible:
			return
		var id := w.data.weapon_id
		var hands: Dictionary = WeaponModel.hands(id)
		var ref := RifleGrip.hold(s, FPArms.SCENE, arms._lib, id)
		var to_skel := s.global_transform.affine_inverse()
		var cam := arms.get_parent_node_3d().global_basis if arms.get_parent_node_3d() else Basis.IDENTITY
		if w._right_arm:
			var t := to_skel * w.global_transform * w._right_arm.transform * (ref.rhand_from_gun as Transform3D)
			miss.Right = RifleGrip.solve_arm(s, "Right", t, _pole(s, "Right", to_skel, cam * Vector3(1, -1, 0.3)))
		if w._left_arm and hands.left_kind != "none":
			var rel: Transform3D = ref.lhand_from_gun
			if hands.left_kind in ["support", "vertical"]:
				# A fist: the right hand's grip mirrored across the gun's middle.
				var r: Transform3D = ref.rhand_from_gun
				var wrist := FPArms.MIRROR_X * (r.origin - (hands.grip as Vector3))
				rel = Transform3D(FPArms.MIRROR_X * r.basis * FPArms.MIRROR_X * arms._mirror_fix, (hands.left as Vector3) + wrist)
			var t := to_skel * w.global_transform * w._left_arm.transform * rel
			miss.Left = RifleGrip.solve_arm(s, "Left", t, _pole(s, "Left", to_skel, cam * Vector3(-1, -1, 0.3)))

	## A point out and down from the shoulder (skeleton space): where the elbow bends.
	func _pole(s: Skeleton3D, side: String, to_skel: Transform3D, dir_global: Vector3) -> Vector3:
		return s.get_bone_global_pose(s.find_bone(FPArms.BONE + side + "Arm")).origin + to_skel.basis * dir_global
