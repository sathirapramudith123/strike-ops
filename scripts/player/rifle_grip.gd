class_name RifleGrip
extends RefCounted
## How a soldier holds a gun (README → Realistic soldiers), shared by the
## third-person SoldierRig and the first-person FPArms:
##   • the reference: the soldier's "idle_aiming" clip, sampled once — the
##     gun is fitted to that pose (grip in the right palm, fore-end along
##     the line to the left palm, upright), then the right hand's and the
##     left hand's places on the gun are remembered, the left palm moved
##     onto the gun's fore-end point (WeaponModel.hands().left);
##   • every frame the gun rides the right hand (hand × gun_from_rhand) and
##     a two-bone IK brings the left hand to its place on the gun.
## References are cached per model and weapon.

const BONE := "mixamorig_"
const REFERENCE_CLIP := &"idle_aiming"

static var _cache := {}


## The reference for `weapon_id` on this skeleton: { gun_from_rhand,
## rhand_from_gun, lhand_from_gun } (Transform3D, skeleton / gun space).
static func hold(s: Skeleton3D, key: String, lib: AnimationLibrary, weapon_id: String) -> Dictionary:
	var k := key + ":" + weapon_id
	if _cache.has(k):
		return _cache[k]
	var pose := sample_pose(s, lib.get_animation(REFERENCE_CLIP), 0.5)
	var rh: Transform3D = pose[s.find_bone(BONE + "RightHand")]
	var lh: Transform3D = pose[s.find_bone(BONE + "LeftHand")]
	var rp := palm(s, pose, "Right")
	var lp := palm(s, pose, "Left")
	var hands := WeaponModel.hands(weapon_id)
	var grip: Vector3 = hands.grip
	var left: Vector3 = hands.left
	# Gun turned so grip -> fore-end lies along right palm -> left palm, upright.
	var fwd := (lp - rp).normalized()
	var up := (Vector3.UP - fwd * fwd.dot(Vector3.UP)).normalized()
	var world := Basis(fwd.cross(up).normalized(), up, -fwd).orthonormalized()
	var w := left - grip
	if w.length() < 0.05:
		w = Vector3.FORWARD # (pistol: the left hand is by the grip)
	var wd := w.normalized()
	var wup := (Vector3.UP - wd * wd.dot(Vector3.UP)).normalized()
	var weapon := Basis(wd.cross(wup).normalized(), wup, -wd).orthonormalized()
	var b := world * weapon.inverse()
	var gun := Transform3D(b, rp - b * grip)
	var ref := {
		"gun_from_rhand": rh.affine_inverse() * gun,
		"rhand_from_gun": gun.affine_inverse() * rh,
	}
	# Left hand: as in the clip relative to the gun, its palm moved onto the
	# fore-end point.
	var l_in_gun := gun.affine_inverse() * lh
	var lpalm_in_gun := gun.affine_inverse() * lp
	l_in_gun.origin += left - lpalm_in_gun
	ref.lhand_from_gun = l_in_gun
	_cache[k] = ref
	return ref


## Global (skeleton-space) bone transforms of `anim` at time `t`, from its
## rotation tracks and the hips' position track; other bones keep their rest.
static func sample_pose(s: Skeleton3D, anim: Animation, t: float) -> Array[Transform3D]:
	var n := s.get_bone_count()
	var local: Array[Transform3D] = []
	for i in n:
		local.append(s.get_bone_rest(i))
	for tr in anim.get_track_count():
		var bone := s.find_bone(String(anim.track_get_path(tr).get_concatenated_subnames()))
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				var scale := local[bone].basis.get_scale()
				local[bone].basis = Basis(anim.rotation_track_interpolate(tr, t)).scaled(scale)
			Animation.TYPE_POSITION_3D:
				local[bone].origin = anim.position_track_interpolate(tr, t)
	var out: Array[Transform3D] = []
	out.resize(n)
	var done: Array[bool] = []
	done.resize(n)
	for i in n:
		_global(s, local, out, done, i)
	return out


static func _global(s: Skeleton3D, local: Array[Transform3D], out: Array[Transform3D], done: Array[bool], i: int) -> Transform3D:
	if done[i]:
		return out[i]
	var p := s.get_bone_parent(i)
	out[i] = local[i] if p < 0 else _global(s, local, out, done, p) * local[i]
	done[i] = true
	return out[i]


## A palm: between the wrist and the middle knuckle.
static func palm(s: Skeleton3D, pose: Array[Transform3D], side: String) -> Vector3:
	var hand := pose[s.find_bone(BONE + side + "Hand")].origin
	var knuckle := pose[s.find_bone(BONE + side + "HandMiddle1")].origin
	return hand.lerp(knuckle, 0.55)


## Two-bone IK in skeleton space: bends upper arm + forearm so the hand bone
## reaches `target` (and takes its rotation), the elbow towards `pole`.
static func solve_arm(s: Skeleton3D, side: String, target: Transform3D, pole: Vector3) -> float:
	var arm := s.find_bone(BONE + side + "Arm")
	var fore := s.find_bone(BONE + side + "ForeArm")
	var hand := s.find_bone(BONE + side + "Hand")
	var a_g := s.get_bone_global_pose(arm)
	var f_g := s.get_bone_global_pose(fore)
	var h_g := s.get_bone_global_pose(hand)
	var a_len := a_g.origin.distance_to(f_g.origin)
	var b_len := f_g.origin.distance_to(h_g.origin)
	var root := a_g.origin
	var t := target.origin
	var to_t := t - root
	var d := clampf(to_t.length(), absf(a_len - b_len) + 0.01, a_len + b_len - 0.001)
	var dir := to_t.normalized()
	var pd := pole - root
	var bend := (pd - dir * dir.dot(pd))
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * dir.dot(Vector3.DOWN)
	bend = bend.normalized()
	var x := (a_len * a_len - b_len * b_len + d * d) / (2.0 * d)
	var h := sqrt(maxf(a_len * a_len - x * x, 0.0))
	var elbow := root + dir * x + bend * h
	var wrist := root + dir * d
	_set_global(s, arm, Basis(Quaternion(a_g.basis.y.normalized(), (elbow - root).normalized())) * a_g.basis)
	f_g = s.get_bone_global_pose(fore)
	_set_global(s, fore, Basis(Quaternion(f_g.basis.y.normalized(), (wrist - elbow).normalized())) * f_g.basis)
	_set_global(s, hand, target.basis.orthonormalized().scaled(h_g.basis.get_scale()))
	return s.get_bone_global_pose(hand).origin.distance_to(t)


static func _set_global(s: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var parent := s.get_bone_parent(bone)
	var p := s.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	s.set_bone_pose_rotation(bone, (p.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())
