class_name SoldierRig
extends Node3D
## The realistic third-person soldier (README → Realistic soldiers): 42manako's
## German KSK operator (Sketchfab, CC BY) on its Mixamo skeleton
## (assets/characters/ksk),
## animated with Mixamo's Pro Rifle Pack retargeted onto it
## (tools/retarget_mixamo.gd). PlayerModel drives it through the same calls
## as its code-built soldier:
##   • locomotion — an AnimationTree blends walk / run / sprint in eight
##     directions (standing) or crouch-walk (crouched) by the local ground
##     velocity, plus the jump loop in the air; clips are sped up past their
##     natural speed so the feet don't slide;
##   • the gun — rides the right hand as in the aiming pose, the left hand
##     brought onto its fore-end by IK (RifleGrip);
##   • reload — the left arm drops to the magazine on top of the animation;
##   • death — one of Mixamo's six death clips;
##   • team colour — the armbands round both upper arms (material Team_band).
## The model faces -Z like every other node in the game (the glb faces +Z).

const MODEL := "res://assets/characters/ksk/ksk.glb"
const ANIMS := "res://assets/characters/ksk/ksk_anims.res"
## Clip speeds come from the retarget (Animation meta "speed" / "dir").
const STAND_SETS := ["walk", "run", "sprint"]
const BONE := "mixamorig_"

var skeleton: Skeleton3D
var gun: MeshInstance3D
var _model: Node3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _poser: _Poser
var _band_mat: StandardMaterial3D
var _top_speed := {} # blend space -> fastest clip speed
var _weapon_id := ""
var _lib: AnimationLibrary
var _dead := false
## Animation LOD: far soldiers advance their AnimationTree every 2nd / 3rd
## frame (with the summed time) — the gun is still placed every frame.
const LOD_NEAR := 15.0
const LOD_FAR := 40.0
var _lod_skip := 0
var _lod_time := 0.0
## animate() fed this frame's time (else _process uses its own delta: menus).
var _fed := false
## Fingers hold the rifle the same way in every clip: their tracks are taken
## out of the (shared) library once and the grip pose is set on each
## skeleton instead — over half the tracks, so half the animation work.
static var _finger_pose: Dictionary = {} # bone name -> Quaternion


func _ready() -> void:
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_model.rotation.y = PI # face -Z
	add_child(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	var lib := load(ANIMS) as AnimationLibrary
	_strip_fingers(lib)
	_lib = lib
	_player.add_animation_library("", lib)
	for bone_name: String in _finger_pose:
		var b := skeleton.find_bone(bone_name)
		if b >= 0:
			skeleton.set_bone_pose_rotation(b, _finger_pose[bone_name])
	_build_tree()
	gun = MeshInstance3D.new()
	gun.name = "Gun"
	add_child(gun)
	# The armbands get this soldier's own copy of their material (team colour).
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "Team_band":
				_band_mat = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(i, _band_mat)
	_poser = _Poser.new()
	_poser.rig = self
	skeleton.add_child(_poser)


func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()
	var stand := AnimationNodeBlendSpace2D.new()
	_add_point(stand, "idle_aiming", Vector2.ZERO)
	var top := 0.0
	for set in STAND_SETS:
		for clip in _clips(set):
			var a := _player.get_animation(clip)
			var v := _blend_pos(a)
			_add_point(stand, clip, v)
			top = maxf(top, v.length())
	_top_speed[&"stand"] = top
	var crouch := AnimationNodeBlendSpace2D.new()
	_add_point(crouch, "idle_crouching_aiming", Vector2.ZERO)
	top = 0.0
	for clip in _clips("walk_crouching"):
		var v := _blend_pos(_player.get_animation(clip))
		_add_point(crouch, clip, v)
		top = maxf(top, v.length())
	_top_speed[&"crouch"] = top
	for bs: AnimationNodeBlendSpace2D in [stand, crouch]:
		bs.min_space = Vector2(-8, -8)
		bs.max_space = Vector2(8, 8)
		bs.sync = false # only the clips being blended are processed
	var air := AnimationNodeAnimation.new()
	air.animation = &"jump_loop"
	root.add_node(&"stand", stand, Vector2(0, 0))
	root.add_node(&"stand_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	root.add_node(&"crouch", crouch, Vector2(0, 200))
	root.add_node(&"crouch_speed", AnimationNodeTimeScale.new(), Vector2(200, 200))
	root.add_node(&"crouched", AnimationNodeBlend2.new(), Vector2(400, 100))
	root.add_node(&"air", air, Vector2(400, 300))
	root.add_node(&"in_air", AnimationNodeBlend2.new(), Vector2(600, 150))
	root.connect_node(&"stand_speed", 0, &"stand")
	root.connect_node(&"crouch_speed", 0, &"crouch")
	root.connect_node(&"crouched", 0, &"stand_speed")
	root.connect_node(&"crouched", 1, &"crouch_speed")
	root.connect_node(&"in_air", 0, &"crouched")
	root.connect_node(&"in_air", 1, &"air")
	root.connect_node(&"output", 0, &"in_air")
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = root
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.active = true


func _process(delta: float) -> void:
	if not _tree.active:
		return
	if not _fed:
		_lod_time += delta
	_fed = false
	_lod_skip -= 1
	if _lod_skip > 0:
		return
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(global_position) if cam else 0.0
	_lod_skip = 1 if dist < LOD_NEAR else (2 if dist < LOD_FAR else 3)
	_tree.advance(_lod_time)
	_lod_time = 0.0


static func _strip_fingers(lib: AnimationLibrary) -> void:
	if not _finger_pose.is_empty():
		return
	var grip := lib.get_animation(&"idle_aiming")
	for name in lib.get_animation_list():
		var a := lib.get_animation(name)
		for t in range(a.get_track_count() - 1, -1, -1):
			var bone := String(a.track_get_path(t).get_concatenated_subnames())
			if "Hand" in bone and bone.length() > 0 and bone[-1].is_valid_int():
				if a == grip and a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					_finger_pose[bone] = a.rotation_track_interpolate(t, 0.0)
				a.remove_track(t)
	if _finger_pose.is_empty():
		push_warning("SoldierRig: no finger pose found")


func _clips(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for dir in ["forward", "backward", "left", "right", "forward_left", "forward_right", "backward_left", "backward_right"]:
		var clip := "%s_%s" % [prefix, dir]
		if _player.has_animation(clip):
			out.append(clip)
	return out


## Blend-space position of a clip: its natural ground velocity, x = right,
## y = forward (the retarget measured it facing +Z, where +X is the left).
func _blend_pos(a: Animation) -> Vector2:
	var dir: Vector2 = a.get_meta(&"dir", Vector2.ZERO)
	return Vector2(-dir.x, dir.y) * float(a.get_meta(&"speed", 0.0))


func _add_point(bs: AnimationNodeBlendSpace2D, clip: String, at: Vector2) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName(clip)
	bs.add_blend_point(node, at)


## Locomotion: `velocity` is the ground velocity in the soldier's own frame
## (x = right, y = forward, m/s); `crouch` and `air` 0..1.
func animate(velocity: Vector2, crouch: float, air: float, delta: float = 0.0) -> void:
	if _dead:
		return
	if delta > 0.0:
		_lod_time += delta
		_fed = true
	var speed := velocity.length()
	for bs: StringName in [&"stand", &"crouch"]:
		var top: float = _top_speed[bs]
		var pos := velocity if speed <= top else velocity * (top / speed)
		_tree.set(&"parameters/%s/blend_position" % bs, pos)
		# Past the fastest clip, play it faster rather than slide the feet.
		_tree.set(&"parameters/%s_speed/scale" % bs, maxf(1.0, speed / maxf(top, 0.1)))
	_tree.set(&"parameters/crouched/blend_amount", crouch)
	_tree.set(&"parameters/in_air/blend_amount", air)


func set_weapon(weapon_id: String, mesh: Mesh) -> void:
	_weapon_id = weapon_id
	gun.mesh = mesh


func set_team_color(color: Color) -> void:
	if _band_mat:
		_band_mat.albedo_color = color


func set_outline(mat: Material) -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = mat


## Reload progress 0..1 (or -1: not reloading) for the left-arm motion.
func set_reload(progress: float) -> void:
	_poser.reload = progress


## Death clip by style (0 backwards, 1 forwards, 2 to the side, 3 crumple),
## a headshot one when it was a headshot.
func play_death(style: int, headshot: bool) -> void:
	_dead = true
	_poser.reload = -1.0
	_tree.active = false
	var clip := "death_from_the_front"
	match style % 4:
		0: clip = "death_from_front_headshot" if headshot else "death_from_the_front"
		1: clip = "death_from_back_headshot" if headshot else "death_from_the_back"
		2: clip = "death_from_right"
		_: clip = "death_crouching_headshot_front"
	_player.play(clip, 0.15)


func reset_pose() -> void:
	_dead = false
	_player.stop()
	_tree.active = true
	gun.visible = true


func is_dead() -> bool:
	return _dead


## Lobby / Character screen: the relaxed "idle" clip instead of the combat
## stance, turned so the chest faces the soldier's front (the clips are
## made bladed, left shoulder forward).
func showcase() -> void:
	_tree.active = false
	_player.play(&"idle")
	var pose := RifleGrip.sample_pose(skeleton, _player.get_animation(&"idle"), 0.0)
	var chest: Transform3D = pose[skeleton.find_bone(BONE + "Spine2")]
	var fwd := chest.basis.z
	_model.rotation.y = PI - atan2(fwd.x, fwd.z)


## The left palm as drawn (after the reload motion) — Skeleton3D's own bone
## poses don't include what modifiers change.
func left_palm() -> Vector3:
	return _poser.left_palm


## Runs after the animation every frame: the reload motion on the left arm,
## then the gun between the hands.
class _Poser extends SkeletonModifier3D:
	var rig: SoldierRig
	var reload := -1.0
	## Where the left palm is after this frame's modifications (world).
	var left_palm := Vector3.ZERO

	var _bones := {}

	func _bone(s: Skeleton3D, name: String) -> int:
		if not _bones.has(name):
			_bones[name] = s.find_bone(BONE + name)
		return _bones[name]

	func _process_modification() -> void:
		var s := get_skeleton()
		if s == null or rig == null or not rig.is_inside_tree() or rig._lib == null:
			return
		var id := rig._weapon_id if rig._weapon_id != "" else "rifle"
		var ref := RifleGrip.hold(s, MODEL, rig._lib, id)
		var hands := WeaponModel.hands(id)
		var gun: Transform3D = s.get_bone_global_pose(_bone(s, "RightHand")) * ref.gun_from_rhand
		if reload >= 0.0:
			# Two dips: magazine out (0.1–0.35), new one in (0.35–0.65); the
			# gun tips about its grip while the left hand fetches the magazine.
			var dip := absf(sin(clampf((reload - 0.1) / 0.55, 0.0, 1.0) * TAU))
			var tip := smoothstep(0.0, 0.12, reload) * (1.0 - smoothstep(0.8, 1.0, reload))
			var grip: Vector3 = hands.grip
			gun = gun * Transform3D(Basis.IDENTITY, grip) 				* Transform3D(Basis(Vector3.FORWARD, 0.55 * tip) * Basis(Vector3.RIGHT, 0.15 * tip), Vector3.ZERO) 				* Transform3D(Basis.IDENTITY, -grip)
			var target: Transform3D = gun * ref.lhand_from_gun
			var mag: Vector3 = gun * (hands.get("mag", Vector3(0, -0.2, -0.05)) as Vector3)
			target.origin = target.origin.lerp(mag + Vector3(0, -0.12, 0) * dip, smoothstep(0.0, 0.25, dip))
			RifleGrip.solve_arm(s, "Left", target, _elbow_pole(s))
		elif hands.get("left_kind", "under") != "none":
			RifleGrip.solve_arm(s, "Left", gun * ref.lhand_from_gun, _elbow_pole(s))
		var hand := s.get_bone_global_pose(_bone(s, "LeftHand")).origin
		var knuckle := s.get_bone_global_pose(_bone(s, "LeftHandMiddle1")).origin
		left_palm = s.global_transform * hand.lerp(knuckle, 0.55)
		rig.gun.global_transform = s.global_transform * gun

	## Keep the elbow where the animation has it (out and down).
	func _elbow_pole(s: Skeleton3D) -> Vector3:
		return s.get_bone_global_pose(_bone(s, "LeftForeArm")).origin + Vector3(0, -0.15, 0)
