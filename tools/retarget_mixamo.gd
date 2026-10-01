extends SceneTree
## Retargets Mixamo clips onto the Rifleman (README → Realistic soldiers).
##
## Mixamo's FBX files aren't in the repo (Adobe's terms: use in games, don't
## redistribute the files). To rebuild assets/characters/rifleman/rifleman_anims.res:
##   1. Make a scratch Godot 4.4 project; put the Pro Rifle Pack FBX files
##      (incl. "X Bot.fbx") in res://fbx/ and assets/characters/rifleman/
##      rifleman.glb in res://target/. Open/import it once
##      (`godot --headless --path <scratch> --import`).
##   2. Copy this script there and run
##      `godot --headless --path <scratch> --script res://retarget_mixamo.gd`.
##   3. Copy res://out/rifleman_anims.res into assets/characters/rifleman/.
##
## How: each clip plays on the real X Bot (its rest is the T-pose the clips
## were made against). For every target bone, the world rotation change from
## the source rest is applied to the target rest, after swinging the target
## bone onto the source rest direction (T-pose vs MPFB's A-pose). Hips height
## is scaled; locomotion clips are made in place and get meta "speed" (m/s)
## and "dir" (x = left, y = forward, facing +Z) for SoldierRig's blend spaces.

const FPS := 30.0
const TARGET := "res://target/rifleman.glb"
const OUT := "res://out/rifleman_anims.res"

var T: Skeleton3D
var t_root: Node
var order: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _skel(n: Node) -> Skeleton3D:
	return n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _run() -> void:
	t_root = (load(TARGET) as PackedScene).instantiate()
	get_root().add_child(t_root)
	T = _skel(t_root)
	order = []
	for i in T.get_bone_count():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _depth(a) < _depth(b))
	var lib := AnimationLibrary.new()
	var track_root := String(t_root.get_path_to(T))
	var dir := DirAccess.open("res://fbx")
	for f in dir.get_files():
		if not f.ends_with(".fbx") or f == "X Bot.fbx":
			continue
		var clip := f.get_basename().replace(" ", "_")
		var anim := _retarget("res://fbx/" + f, clip, track_root)
		lib.add_animation(clip, anim)
		print(clip, " ", snappedf(anim.length, 0.01), "s speed ", snappedf(float(anim.get_meta(&"speed", 0.0)), 0.01), " dir ", anim.get_meta(&"dir", Vector2.ZERO))
	print("save ", error_string(ResourceSaver.save(lib, OUT)))
	quit()


func _depth(i: int) -> int:
	var d := 0
	var p := T.get_bone_parent(i)
	while p >= 0:
		d += 1
		p = T.get_bone_parent(p)
	return d


func _loops(clip: String) -> bool:
	return clip.begins_with("walk") or clip.begins_with("run") or clip.begins_with("sprint") \
		or clip.begins_with("idle") or clip == "jump_loop"


func _in_place(clip: String) -> bool:
	return _loops(clip)


func _retarget(path: String, clip: String, track_root: String) -> Animation:
	# Play the clip on the real X Bot (its rest is the true T-pose the clip was
	# made against; the clip files carry a different rest of their own).
	var clip_scene := (load(path) as PackedScene).instantiate()
	var clip_ap := clip_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src := clip_ap.get_animation(clip_ap.get_animation_list()[0]).duplicate() as Animation
	clip_scene.free()
	var root := (load("res://fbx/X Bot.fbx") as PackedScene).instantiate()
	get_root().add_child(root)
	var S := _skel(root)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_lib := AnimationLibrary.new()
	clip_lib.add_animation("c", src)
	ap.add_animation_library("clip", clip_lib)
	var src_name := &"clip/c"
	var n := T.get_bone_count()
	var sidx := PackedInt32Array()
	var s_rest: Array[Quaternion] = []
	var t_rest: Array[Quaternion] = []
	var align: Array[Quaternion] = []
	sidx.resize(n)
	s_rest.resize(n)
	t_rest.resize(n)
	align.resize(n)
	for i in order:
		var name := T.get_bone_name(i)
		sidx[i] = S.find_bone(name)
		t_rest[i] = T.get_bone_global_rest(i).basis.get_rotation_quaternion()
		s_rest[i] = S.get_bone_global_rest(sidx[i]).basis.get_rotation_quaternion() if sidx[i] >= 0 else t_rest[i]
		align[i] = align[T.get_bone_parent(i)] if T.get_bone_parent(i) >= 0 else Quaternion.IDENTITY
		if sidx[i] < 0:
			continue
		for c in T.get_bone_children(i):
			var sc := S.find_bone(T.get_bone_name(c))
			if sc < 0:
				continue
			var dt := T.get_bone_global_rest(c).origin - T.get_bone_global_rest(i).origin
			var ds := S.get_bone_global_rest(sc).origin - S.get_bone_global_rest(sidx[i]).origin
			if dt.length() > 0.001 and ds.length() > 0.001:
				align[i] = Quaternion(dt.normalized(), ds.normalized())
			break
	var hips := T.find_bone("mixamorig_Hips")
	var s_hips := S.find_bone("mixamorig_Hips")
	var ratio := T.get_bone_global_rest(hips).origin.y / S.get_bone_global_rest(s_hips).origin.y
	var frames := maxi(2, int(round(src.length * FPS)) + 1)
	var anim := Animation.new()
	anim.length = (frames - 1) / FPS
	anim.loop_mode = Animation.LOOP_LINEAR if _loops(clip) else Animation.LOOP_NONE
	var rot_tracks := {}
	for i in order:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("%s:%s" % [track_root, T.get_bone_name(i)]))
		rot_tracks[i] = tr
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("%s:%s" % [track_root, T.get_bone_name(hips)]))
	var hip_pos: Array[Vector3] = []
	ap.play(src_name)
	for f in frames:
		var t := minf(f / FPS, src.length)
		ap.seek(t, true)
		S.force_update_all_bone_transforms()
		var world := {}
		for i in order:
			var w: Quaternion
			if sidx[i] >= 0:
				var p := S.get_bone_global_pose(sidx[i]).basis.get_rotation_quaternion()
				w = (p * s_rest[i].inverse()) * align[i] * t_rest[i]
			else:
				var par := T.get_bone_parent(i)
				w = (world[par] as Quaternion) * T.get_bone_rest(i).basis.get_rotation_quaternion()
			world[i] = w.normalized()
			var parent := T.get_bone_parent(i)
			var local: Quaternion = world[i] if parent < 0 else (world[parent] as Quaternion).inverse() * world[i]
			anim.rotation_track_insert_key(rot_tracks[i], f / FPS, local.normalized())
		hip_pos.append(S.get_bone_global_pose(s_hips).origin * ratio)
	if _in_place(clip):
		var drift := hip_pos[-1] - hip_pos[0]
		# Natural ground speed of the clip (m/s, already scaled to the target)
		# and direction (x = right, y = forward; the character faces +Z).
		anim.set_meta(&"speed", Vector2(drift.x, drift.z).length() / maxf(anim.length, 0.001))
		anim.set_meta(&"dir", Vector2(drift.x, drift.z).normalized())
		for f in frames:
			var k := float(f) / float(frames - 1)
			hip_pos[f] -= Vector3(hip_pos[0].x + drift.x * k, 0, hip_pos[0].z + drift.z * k)
	for f in frames:
		anim.position_track_insert_key(pos_track, f / FPS, hip_pos[f])
	root.free()
	return anim
