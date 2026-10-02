class_name WeaponModel
extends RefCounted
## Low-poly gun models built from code (one mesh per weapon, cached): used as
## the first-person viewmodel and in the third-person player's hands. The
## viewmodel is split so the reload can be animated: gun without magazine,
## magazine (or shotgun shell), right arm, left arm.
## Units are metres, -Z = muzzle. The iron sights keep the exact positions the
## weapons' ADS offsets were tuned for (sight top ≈ -ads_position.y).

static var _cache: Dictionary = {}
static var _arms_cache: Dictionary = {}

## Where the hands hold each gun (weapon space): right hand on the grip,
## left hand under the fore-end / pump / front grip. "grip_tilt" leans the
## right fist with the grip; "left" = "under" (palm under a fore-end),
## "vertical" (fist round a front grip) or "support" (pistol: cupping the
## right hand).
const HANDS := {
	"rifle": { "grip": Vector3(0, -0.085, 0.1), "grip_tilt": -15.0, "left": Vector3(0, 0.004, -0.29), "left_kind": "under",
		"mag": Vector3(0, -0.2, -0.03) },
	"smg": { "grip": Vector3(0, -0.08, 0.08), "grip_tilt": -12.0, "left": Vector3(0, -0.075, -0.14), "left_kind": "vertical",
		"mag": Vector3(0, -0.25, -0.05) },
	"shotgun": { "grip": Vector3(0, -0.06, 0.14), "grip_tilt": -20.0, "left": Vector3(0, -0.035, -0.3), "left_kind": "under",
		"mag": Vector3(0, -0.07, -0.02) },
	"sniper": { "grip": Vector3(0, -0.08, 0.14), "grip_tilt": -15.0, "left": Vector3(0, -0.02, -0.24), "left_kind": "under",
		"mag": Vector3(0, -0.14, -0.02) },
	"pistol": { "grip": Vector3(0, -0.07, 0.07), "grip_tilt": -15.0, "left": Vector3(-0.03, -0.075, 0.075), "left_kind": "support",
		"mag": Vector3(0, -0.15, 0.1) },
	"lmg": { "grip": Vector3(0, -0.09, 0.12), "grip_tilt": -15.0, "left": Vector3(0, -0.015, -0.3), "left_kind": "under",
		"mag": Vector3(-0.03, -0.13, -0.03) },
	# Knife: one hand only (left_kind "none").
	"knife": { "grip": Vector3(0, -0.02, 0.04), "grip_tilt": -10.0, "left": Vector3.ZERO, "left_kind": "none",
		"mag": Vector3.ZERO },
}


## What the hands work on besides the magazine (weapon space): the
## charging handle / bolt / slide; the LMG's top cover hinge.
const CHARGE := {
	"rifle": Vector3(0.036, 0.02, 0.03), "smg": Vector3(-0.03, 0.03, -0.1), "pistol": Vector3(0, 0.02, 0.06),
	"sniper": Vector3(0.088, 0.04, 0.13), "lmg": Vector3(0.042, 0.02, -0.03), "shotgun": Vector3(0, -0.035, -0.3),
}
const COVER_HINGE := Vector3(0, 0.053, 0.08)


## Real gun models (README → Real guns): assets/weapons/<id>/<id>.glb holds
## <id>_Gun (without magazine), <id>_Magazine and <id>_GunFull meshes in
## weapon space (metres, -Z = muzzle, sights at the weapon's ADS height).
## They replace the code-built meshes while Realistic soldiers is on.
const REAL_DIR := "res://assets/weapons"
## Where the hands, the magazine and the muzzle are on a real model, where
## they differ from HANDS (merged over it by hands()); "ads" replaces the
## weapon's ads_position (the sight's height on this model).
const REAL_HANDS := {
	"rifle": { "grip": Vector3(0, -0.085, 0.1), "left": Vector3(0, -0.02, -0.225), "mag": Vector3(0, -0.19, -0.065),
		"muzzle": Vector3(0, 0.019, -0.526), "ads": Vector3(0, -0.082, -0.22), "red_dot": true },
	"smg": { "grip": Vector3(0, -0.08, 0.08), "left": Vector3(0, -0.005, -0.19), "left_kind": "under", "mag": Vector3(0, -0.19, -0.12),
		"muzzle": Vector3(0, 0.022, -0.3), "sight": Vector3(0, 0.064, -0.05), "red_dot": true, "ads_z": -0.17 },
	"shotgun": { "grip": Vector3(0, -0.06, 0.14), "left": Vector3(0, -0.03, -0.26), "muzzle": Vector3(0, 0.035, -0.543),
		"sight": Vector3(0, 0.049, -0.02), "red_dot": true, "ads_z": -0.2 },
	"sniper": { "grip": Vector3(0, -0.08, 0.14), "left": Vector3(0, -0.06, -0.2), "mag": Vector3(0, -0.09, -0.04),
		"muzzle": Vector3(0, 0.0, -0.747), "ads": Vector3(0, -0.058, -0.25) },
	"lmg": { "grip": Vector3(0, -0.09, 0.12), "left": Vector3(0, -0.07, -0.225), "mag": Vector3(0, -0.2, -0.035),
		"muzzle": Vector3(0, 0.036, -0.575), "sight": Vector3(0, 0.088, 0.0), "red_dot": true, "ads_z": -0.2 },
	"pistol": { "grip": Vector3(0, -0.038, 0.078), "left": Vector3(-0.02, -0.068, 0.07), "muzzle": Vector3(0, 0.042, -0.103),
		"sight": Vector3(0, 0.056, 0.03), "red_dot": true, "sight_scale": 0.75, "ads_z": -0.2 },
	"knife": { "grip": Vector3(0, -0.02, 0.06) },
}
static var _real := {}


## The real model's meshes by part ("Gun", "Magazine", "GunFull"), or {}.
static func real_parts(weapon_id: String) -> Dictionary:
	if not SettingsManager.graphics.realistic_characters:
		return {}
	if not _real.has(weapon_id):
		var parts := {}
		var path := "%s/%s/%s.glb" % [REAL_DIR, weapon_id, weapon_id]
		if ResourceLoader.exists(path):
			var root := (load(path) as PackedScene).instantiate()
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				parts[String(mi.name).trim_prefix(weapon_id + "_")] = mi.mesh
			root.free()
			# A red-dot sight on the rail (REAL_HANDS "sight"): added to the
			# gun's own meshes, so it shows in first and third person.
			var h: Dictionary = REAL_HANDS.get(weapon_id, {})
			if h.has("sight"):
				var at := Transform3D(Basis.from_scale(Vector3.ONE * float(h.get("sight_scale", 1.0))), h.sight)
				for k: String in ["Gun", "GunFull"]:
					if parts.has(k):
						parts[k] = _with_mesh(parts[k], red_dot_mesh(), at)
		_real[weapon_id] = parts
	return _real[weapon_id]


## Where the hands hold this gun (HANDS, with the real model's own points
## while it is in use). Unknown guns get the rifle's.
static func hands(weapon_id: String) -> Dictionary:
	var h: Dictionary = HANDS.get(weapon_id, HANDS["rifle"])
	if REAL_HANDS.has(weapon_id) and real_parts(weapon_id).has("Gun"):
		h = h.merged(REAL_HANDS[weapon_id], true)
		# A red-dot sight puts the eye at the centre of its window.
		if h.has("sight"):
			var eye_y: float = (h.sight as Vector3).y + RED_DOT_EYE * float(h.get("sight_scale", 1.0))
			h.ads = Vector3(0, -eye_y, float(h.get("ads_z", -0.3)))
	return h


## Height of the red-dot window's centre above its mount (m, at scale 1).
const RED_DOT_EYE := 0.049
## A real reflex sight (makivic, Sketchfab; docs/CREDITS.md): mount bottom
## at the origin, the window (0.031–0.059 m up) facing -Z; the eye sits
## just above its centre, over the emitter housing.
const RED_DOT_MODEL := "res://assets/weapons/red_dot/red_dot.glb"
static var _red_dot: ArrayMesh


## The red-dot sight (mount at y = 0, window centred RED_DOT_EYE above,
## looking down -Z): the real model with a faint clear glass, or — if it is
## missing — a code-built one (low mount, squared hood, glass, knob).
static func red_dot_mesh() -> ArrayMesh:
	if _red_dot:
		return _red_dot
	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.45, 0.75, 0.8, 0.12)
	glass_mat.roughness = 0.05
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(RED_DOT_MODEL):
		var scene := (load(RED_DOT_MODEL) as PackedScene).instantiate()
		var body: Mesh
		var glass: Mesh
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).contains("glass"):
				glass = mi.mesh
			else:
				body = mi.mesh
		scene.free()
		if body and glass:
			_red_dot = _with_mesh(body, glass, Transform3D.IDENTITY)
			_red_dot.surface_set_material(_red_dot.get_surface_count() - 1, glass_mat)
			return _red_dot
	var b := MeshBuilder.new()
	b.define(&"sight", Color(0.06, 0.065, 0.07), 0.5)
	var e := RED_DOT_EYE
	var w := 0.034 # window
	var t := 0.004 # hood wall
	var d := 0.03 # hood depth
	b.box(&"sight", Vector3(0.026, 0.01, 0.05), Vector3(0, 0.005, 0)) # rail clamp
	b.box(&"sight", Vector3(0.018, e - w * 0.5 - t - 0.008, 0.03), Vector3(0, 0.01 + (e - w * 0.5 - t - 0.008) * 0.5, 0.004)) # riser
	b.box(&"sight", Vector3(w + 2 * t, t, d), Vector3(0, e + w * 0.5 + t * 0.5, 0)) # hood top
	b.box(&"sight", Vector3(w + 2 * t, t, d), Vector3(0, e - w * 0.5 - t * 0.5, 0)) # hood bottom
	for sx: float in [-1.0, 1.0]:
		b.box(&"sight", Vector3(t, w + 2 * t, d), Vector3(sx * (w * 0.5 + t * 0.5), e, 0)) # sides
	b.box(&"sight", Vector3(0.008, 0.008, 0.012), Vector3(0.023, e, 0.004)) # brightness knob
	var frame := b.build()
	var glass := QuadMesh.new()
	glass.size = Vector2(w, w)
	glass.material = glass_mat
	_red_dot = _with_mesh(frame, glass, Transform3D(Basis.IDENTITY, Vector3(0, e, -d * 0.3)))
	return _red_dot


## `base` with `extra`'s surfaces appended, moved by `at`.
static func _with_mesh(base: Mesh, extra: Mesh, at: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for pair: Array in [[base, Transform3D.IDENTITY], [extra, at]]:
		var m := pair[0] as Mesh
		var xf := pair[1] as Transform3D
		for i in m.get_surface_count():
			var arrays := m.surface_get_arrays(i)
			# Only the standard channels (custom ones need their own format flags).
			for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				arrays[c] = null
			if xf != Transform3D.IDENTITY:
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for j in v.size():
					v[j] = xf * v[j]
				arrays[Mesh.ARRAY_VERTEX] = v
				if arrays[Mesh.ARRAY_NORMAL] != null:
					var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					for j in n.size():
						n[j] = (xf.basis * n[j]).normalized()
					arrays[Mesh.ARRAY_NORMAL] = n
				if arrays[Mesh.ARRAY_TANGENT] != null:
					var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
					for j in range(0, tg.size(), 4):
						var tv := (xf.basis * Vector3(tg[j], tg[j + 1], tg[j + 2])).normalized()
						tg[j] = tv.x
						tg[j + 1] = tv.y
						tg[j + 2] = tv.z
					arrays[Mesh.ARRAY_TANGENT] = tg
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, m.surface_get_material(i))
	return out


static func has_model(weapon_id: String) -> bool:
	return weapon_id in ["rifle", "smg", "shotgun", "sniper", "pistol", "knife", "lmg"]


## The whole gun (third person). `with_magazine = false`: the viewmodel's
## gun, whose magazine is a separate node (see get_magazine_mesh).
static func get_mesh(weapon_id: String, with_magazine: bool = true) -> ArrayMesh:
	var real := real_parts(weapon_id)
	if real.has("Gun"):
		return (real.get("GunFull", real.Gun) if with_magazine else real.Gun) as ArrayMesh
	var key := weapon_id if with_magazine else weapon_id + ":nomag"
	if not _cache.has(key):
		var b := MeshBuilder.new()
		match weapon_id:
			"rifle": _rifle(b)
			"smg": _smg(b)
			"shotgun": _shotgun(b)
			"sniper": _sniper(b)
			"pistol": _pistol(b)
			"knife": _knife(b)
			"lmg": _lmg(b)
		if with_magazine and weapon_id != "shotgun" and weapon_id != "knife":
			_magazine(b, weapon_id)
		if with_magazine and weapon_id == "lmg":
			_cover(b, COVER_HINGE)
		_cache[key] = b.build()
	return _cache[key]


## The magazine (shotgun: one shell), in weapon space where it sits in the gun.
static func get_magazine_mesh(weapon_id: String) -> ArrayMesh:
	var key := weapon_id + ":mag"
	if weapon_id == "knife":
		return null
	if real_parts(weapon_id).has("Magazine"):
		return real_parts(weapon_id).Magazine as ArrayMesh
	if not _cache.has(key) and has_model(weapon_id):
		var b := MeshBuilder.new()
		_magazine(b, weapon_id)
		_cache[key] = b.build()
	return _cache.get(key)


## LMG top cover, in hinge space (the viewmodel lifts it to load the belt).
static func get_cover_mesh(weapon_id: String) -> ArrayMesh:
	if weapon_id != "lmg" or real_parts(weapon_id).has("Gun"):
		return null # (the real LMG's cover is part of its model)
	if not _cache.has("lmg:cover"):
		var b := MeshBuilder.new()
		_cover(b, Vector3.ZERO)
		_cache["lmg:cover"] = b.build()
	return _cache["lmg:cover"]


static func _cover(b: MeshBuilder, at: Vector3) -> void:
	b.box(&"steel", Vector3(0.066, 0.022, 0.2), at + Vector3(0, 0.011, -0.1))
	b.box(&"polymer", Vector3(0.03, 0.01, 0.16), at + Vector3(0, 0.027, -0.1)) # rail
	b.box(&"steel", Vector3(0.012, 0.012, 0.03), at + Vector3(-0.036, 0.01, -0.19)) # latch


static func _magazine(b: MeshBuilder, weapon_id: String) -> void:
	match weapon_id:
		"lmg":
			# Box magazine hanging under the left side, the belt running up into the feed tray.
			b.box(&"olive", Vector3(0.07, 0.1, 0.12), Vector3(-0.012, -0.1, -0.03))
			b.box(&"polymer", Vector3(0.072, 0.012, 0.122), Vector3(-0.012, -0.146, -0.03))
			for i in 5:
				b.box(&"brass", Vector3(0.012, 0.012, 0.05), Vector3(-0.045 + i * 0.004, -0.045 + i * 0.016, -0.03 + i * 0.001),
					Vector3(0, 0, -25))
		"rifle":
			b.box(&"polymer", Vector3(0.035, 0.14, 0.06), Vector3(0, -0.1, -0.06), Vector3(15, 0, 0))
			b.box(&"polymer", Vector3(0.037, 0.02, 0.064), Vector3(0, -0.168, -0.042), Vector3(15, 0, 0))
		"smg":
			b.box(&"polymer", Vector3(0.03, 0.2, 0.045), Vector3(0, -0.13, -0.05))
			b.box(&"steel", Vector3(0.032, 0.012, 0.047), Vector3(0, -0.232, -0.05))
		"sniper":
			b.box(&"polymer", Vector3(0.045, 0.075, 0.1), Vector3(0, -0.075, -0.02))
			b.box(&"steel", Vector3(0.047, 0.012, 0.102), Vector3(0, -0.113, -0.02))
		"pistol":
			b.box(&"polymer", Vector3(0.022, 0.1, 0.034), Vector3(0, -0.075, 0.072), Vector3(-15, 0, 0))
			b.box(&"steel", Vector3(0.028, 0.012, 0.042), Vector3(0, -0.126, 0.086), Vector3(-15, 0, 0))
		"shotgun":
			b.cylinder_z(&"shell", 0.011, 0.06, Vector3(0, -0.07, -0.02))
			b.cylinder_z(&"brass", 0.0115, 0.014, Vector3(0, -0.07, 0.012))


## First-person arm for a weapon: a gloved hand on the gun and a sleeved
## forearm running back out of view. Right = on the grip; left = on the
## fore-end / pump / front grip (pistol: round the right hand). Separate
## meshes so the left hand can fetch a new magazine while reloading.
## `look` (CharacterLook) colours the gloves and sleeves like the player's
## outfit; empty = the default black gloves and green sleeves.
static func get_arm_mesh(weapon_id: String, left: bool, look: Dictionary = {}) -> ArrayMesh:
	var key := weapon_id + (":L" if left else ":R") + ("" if look.is_empty() else ":" + _arm_look_key(look))
	if not _arms_cache.has(key) and HANDS.has(weapon_id):
		var h: Dictionary = HANDS[weapon_id]
		var b := MeshBuilder.new()
		if not look.is_empty():
			_define_arm_look(b, look)
		if not left:
			_right_hand(b, h.grip, h.grip_tilt)
		else:
			match h.left_kind:
				"under": _left_hand_under(b, h.left)
				"vertical": _left_hand_vertical(b, h.left)
				"none": return null
				_: _left_hand_support(b, h.left)
		_arms_cache[key] = b.build()
	return _arms_cache.get(key)


static func _arm_look_key(look: Dictionary) -> String:
	var clean: Dictionary = CharacterLook.sanitize(look)
	return "%d,%d,%d,%d" % [clean.body, clean.face, clean.outfit, clean.gloves]


## Gloves in the look's colour (bare hands for "None"), sleeves in the
## outfit's shirt colour and camouflage.
static func _define_arm_look(b: MeshBuilder, look: Dictionary) -> void:
	var clean: Dictionary = CharacterLook.sanitize(look)
	var glove: Dictionary = CharacterLook.GLOVES[int(clean.gloves)]
	var outfit: Dictionary = CharacterLook.OUTFITS[int(clean.outfit)]
	var skin: Color = CharacterLook.face_of(clean).skin
	var gc: Color = glove.color
	var glove_color := skin if gc.r < 0.0 else gc
	b.define(&"glove", glove_color)
	b.define(&"glove_pad", skin if bool(glove.fingerless) else glove_color.lightened(0.12))
	b.define(&"sleeve", outfit.shirt, 0.0, int(outfit.pattern))


## Fist round a pistol grip, thumb over the top, forearm back and down-right.
static func _right_hand(b: MeshBuilder, grip: Vector3, tilt: float) -> void:
	var rot := Vector3(tilt, 0, 0)
	b.box(&"glove", Vector3(0.062, 0.085, 0.075), grip + Vector3(0.006, 0.0, 0.012), rot) # palm + fingers
	b.box(&"glove_pad", Vector3(0.066, 0.08, 0.018), grip + Vector3(0.006, -0.002, -0.028), rot) # knuckle pads
	b.box(&"glove", Vector3(0.02, 0.022, 0.06), grip + Vector3(-0.03, 0.045, -0.005), Vector3(0, 12, 0)) # thumb
	b.box(&"glove", Vector3(0.02, 0.02, 0.045), grip + Vector3(0.0, 0.035, -0.045), Vector3(0, 0, 0)) # trigger finger
	var wrist := grip + Vector3(0.018, -0.03, 0.07)
	var elbow := grip + Vector3(0.09, -0.24, 0.34)
	b.limb(&"glove", grip + Vector3(0.01, -0.01, 0.04), wrist, 0.034, 0.033) # cuff
	b.limb(&"sleeve", wrist, elbow, 0.038, 0.05, 8)
	b.limb(&"sleeve", elbow, elbow + Vector3(0.05, -0.12, 0.2), 0.052, 0.06, 8)


## Palm under a fore-end, fingers up the right side, thumb up the left.
static func _left_hand_under(b: MeshBuilder, fore: Vector3) -> void:
	b.box(&"glove", Vector3(0.07, 0.03, 0.1), fore + Vector3(0, -0.05, 0.0)) # palm
	b.box(&"glove", Vector3(0.016, 0.055, 0.09), fore + Vector3(0.036, -0.022, -0.005)) # fingers
	b.box(&"glove_pad", Vector3(0.018, 0.012, 0.09), fore + Vector3(0.037, 0.004, -0.005))
	b.box(&"glove", Vector3(0.016, 0.04, 0.06), fore + Vector3(-0.036, -0.03, 0.01), Vector3(0, 0, 8)) # thumb
	var wrist := fore + Vector3(-0.045, -0.07, 0.05)
	var elbow := fore + Vector3(-0.3, -0.2, 0.2)
	b.limb(&"glove", fore + Vector3(-0.015, -0.055, 0.03), wrist, 0.034, 0.033)
	b.limb(&"sleeve", wrist, elbow, 0.04, 0.055, 8)
	b.limb(&"sleeve", elbow, elbow + Vector3(-0.12, -0.1, 0.2), 0.056, 0.064, 8)


## Fist round a vertical front grip.
static func _left_hand_vertical(b: MeshBuilder, grip: Vector3) -> void:
	b.box(&"glove", Vector3(0.06, 0.07, 0.07), grip + Vector3(-0.004, -0.005, 0.004))
	b.box(&"glove_pad", Vector3(0.064, 0.066, 0.016), grip + Vector3(-0.004, -0.005, -0.034))
	b.box(&"glove", Vector3(0.02, 0.02, 0.05), grip + Vector3(-0.032, 0.035, 0.0)) # thumb
	var wrist := grip + Vector3(-0.04, -0.05, 0.04)
	var elbow := grip + Vector3(-0.28, -0.2, 0.2)
	b.limb(&"glove", grip + Vector3(-0.01, -0.03, 0.03), wrist, 0.033, 0.032)
	b.limb(&"sleeve", wrist, elbow, 0.037, 0.05, 8)
	b.limb(&"sleeve", elbow, elbow + Vector3(-0.08, -0.1, 0.22), 0.052, 0.06, 8)


## Pistol: the left hand wraps round the right fist from the left.
static func _left_hand_support(b: MeshBuilder, pos: Vector3) -> void:
	b.box(&"glove", Vector3(0.03, 0.08, 0.08), pos, Vector3(-15, 0, 0))
	b.box(&"glove_pad", Vector3(0.05, 0.07, 0.016), pos + Vector3(0.018, -0.005, -0.038), Vector3(-15, 0, 0)) # fingers over the front
	b.box(&"glove", Vector3(0.018, 0.02, 0.05), pos + Vector3(0.0, 0.04, -0.02), Vector3(0, -10, 0)) # thumb along the frame
	var wrist := pos + Vector3(-0.03, -0.04, 0.06)
	var elbow := pos + Vector3(-0.17, -0.2, 0.3)
	b.limb(&"glove", pos + Vector3(-0.01, -0.02, 0.03), wrist, 0.032, 0.031)
	b.limb(&"sleeve", wrist, elbow, 0.036, 0.05, 8)
	b.limb(&"sleeve", elbow, elbow + Vector3(-0.08, -0.1, 0.22), 0.052, 0.06, 8)


## Combat knife, held in a fist with the blade forward (-Z).
static func _knife(b: MeshBuilder) -> void:
	b.box(&"polymer", Vector3(0.028, 0.034, 0.11), Vector3(0, 0.0, 0.04)) # handle
	for z in [0.0, 0.03, 0.06]:
		b.box(&"gear", Vector3(0.03, 0.036, 0.008), Vector3(0, 0.0, z)) # grip ridges
	b.box(&"steel", Vector3(0.07, 0.012, 0.012), Vector3(0, 0.0, -0.018)) # guard
	b.box(&"steel", Vector3(0.03, 0.036, 0.016), Vector3(0, 0.0, 0.1)) # pommel
	b.box(&"blade", Vector3(0.006, 0.032, 0.16), Vector3(0, 0.004, -0.1)) # blade
	b.box(&"blade", Vector3(0.005, 0.02, 0.04), Vector3(0, -0.002, -0.19), Vector3(-18, 0, 0)) # point
	b.box(&"steel", Vector3(0.007, 0.006, 0.12), Vector3(0, 0.02, -0.09)) # spine


static func _iron_sights(b: MeshBuilder, rear_y: float, rear_z: float, front_y: float, front_z: float, gap: float = 0.009) -> void:
	for sx in [-1.0, 1.0]:
		b.box(&"steel", Vector3(0.006, 0.03, 0.02), Vector3(sx * gap, rear_y, rear_z))
	b.box(&"steel", Vector3(0.004, 0.03, 0.01), Vector3(0, front_y, front_z))
	b.box(&"steel", Vector3(0.022, 0.016, 0.022), Vector3(0, front_y - 0.018, front_z))


static func _rifle(b: MeshBuilder) -> void: # AR-7
	b.box(&"steel", Vector3(0.06, 0.09, 0.42), Vector3.ZERO)
	b.box(&"polymer", Vector3(0.04, 0.012, 0.3), Vector3(0, 0.051, -0.02)) # top rail
	b.box(&"tan", Vector3(0.062, 0.072, 0.2), Vector3(0, 0.004, -0.29)) # handguard
	for z in [-0.23, -0.27, -0.31, -0.35]:
		b.box(&"polymer", Vector3(0.064, 0.012, 0.018), Vector3(0, 0.012, z)) # vents
	b.cylinder_z(&"steel", 0.012, 0.28, Vector3(0, 0.015, -0.34))
	b.cylinder_z(&"steel", 0.017, 0.05, Vector3(0, 0.015, -0.47)) # muzzle brake
	b.box(&"polymer", Vector3(0.035, 0.1, 0.045), Vector3(0, -0.085, 0.1), Vector3(-15, 0, 0)) # grip
	b.box(&"steel", Vector3(0.008, 0.012, 0.06), Vector3(0, -0.055, 0.04)) # trigger guard
	b.cylinder_z(&"steel", 0.012, 0.1, Vector3(0, 0.01, 0.23)) # buffer tube
	b.box(&"tan", Vector3(0.045, 0.08, 0.18), Vector3(0, -0.01, 0.28)) # stock
	b.box(&"polymer", Vector3(0.05, 0.1, 0.02), Vector3(0, -0.02, 0.375)) # butt pad
	b.box(&"steel", Vector3(0.012, 0.012, 0.03), Vector3(0.036, 0.02, 0.03)) # charging handle
	_iron_sights(b, 0.055, 0.12, 0.06, -0.18)


static func _smg(b: MeshBuilder) -> void: # V-10
	b.box(&"steel", Vector3(0.055, 0.085, 0.3), Vector3.ZERO)
	b.box(&"olive", Vector3(0.058, 0.05, 0.12), Vector3(0, -0.01, -0.08)) # side panels
	b.cylinder_z(&"steel", 0.011, 0.12, Vector3(0, 0.012, -0.21))
	b.cylinder_z(&"polymer", 0.02, 0.07, Vector3(0, 0.012, -0.17)) # barrel shroud
	b.box(&"polymer", Vector3(0.035, 0.1, 0.04), Vector3(0, -0.08, 0.08), Vector3(-12, 0, 0)) # grip
	b.box(&"polymer", Vector3(0.03, 0.07, 0.03), Vector3(0, -0.075, -0.14)) # front grip
	for sx in [-1.0, 1.0]:
		b.cylinder_z(&"steel", 0.006, 0.16, Vector3(sx * 0.018, 0.0, 0.22)) # folding stock rails
	b.box(&"polymer", Vector3(0.05, 0.08, 0.015), Vector3(0, -0.01, 0.3))
	b.box(&"polymer", Vector3(0.03, 0.01, 0.2), Vector3(0, 0.047, 0.0)) # rail
	_iron_sights(b, 0.055, 0.1, 0.055, -0.13)


static func _shotgun(b: MeshBuilder) -> void: # M-12
	b.box(&"steel", Vector3(0.06, 0.09, 0.36), Vector3.ZERO)
	b.cylinder_z(&"steel", 0.018, 0.42, Vector3(0, 0.02, -0.38))
	b.cylinder_z(&"steel", 0.014, 0.34, Vector3(0, -0.018, -0.35)) # tube magazine
	b.box(&"steel", Vector3(0.012, 0.006, 0.4), Vector3(0, 0.041, -0.36)) # vent rib
	b.box(&"wood", Vector3(0.056, 0.055, 0.18), Vector3(0, -0.035, -0.3)) # pump
	for z in [-0.25, -0.28, -0.31, -0.34]:
		b.box(&"gear", Vector3(0.058, 0.01, 0.008), Vector3(0, -0.035, z)) # pump grooves
	b.box(&"wood", Vector3(0.042, 0.07, 0.07), Vector3(0, -0.06, 0.14), Vector3(-20, 0, 0)) # wrist
	b.box(&"wood", Vector3(0.05, 0.09, 0.24), Vector3(0, -0.03, 0.3), Vector3(-6, 0, 0)) # stock
	b.box(&"gear", Vector3(0.052, 0.1, 0.02), Vector3(0, -0.04, 0.42), Vector3(-6, 0, 0)) # recoil pad
	b.box(&"steel", Vector3(0.008, 0.012, 0.05), Vector3(0, -0.055, 0.05)) # trigger guard
	b.sphere(&"lens", 0.005, Vector3(0, 0.046, -0.56)) # bead sight


static func _sniper(b: MeshBuilder) -> void: # LR-50 (big-scope bolt-action)
	# Receiver, fore-end and fluted barrel.
	b.box(&"olive", Vector3(0.06, 0.085, 0.36), Vector3(0, 0.0, 0.02))
	b.box(&"steel", Vector3(0.05, 0.03, 0.3), Vector3(0, 0.05, -0.02)) # action
	b.box(&"olive", Vector3(0.062, 0.07, 0.26), Vector3(0, -0.005, -0.28)) # fore-end
	b.box(&"polymer", Vector3(0.064, 0.012, 0.2), Vector3(0, 0.022, -0.28)) # fore-end cap
	b.cylinder_z(&"steel", 0.014, 0.52, Vector3(0, 0.015, -0.5), 0.012)
	for z in [-0.44, -0.5, -0.56]:
		b.box(&"polymer", Vector3(0.006, 0.006, 0.05), Vector3(0.013, 0.015, z)) # flutes
	b.cylinder_z(&"steel", 0.022, 0.08, Vector3(0, 0.015, -0.79)) # muzzle brake
	for z in [-0.77, -0.8]:
		b.box(&"polymer", Vector3(0.046, 0.012, 0.012), Vector3(0, 0.015, z)) # brake ports
	# Scope: long tube, big objective, eyepiece, turrets, rings on a rail.
	b.box(&"polymer", Vector3(0.024, 0.012, 0.3), Vector3(0, 0.07, -0.02)) # rail
	b.cylinder_z(&"polymer", 0.027, 0.34, Vector3(0, 0.085, -0.02), -1.0, 12)
	b.cylinder_z(&"polymer", 0.027, 0.1, Vector3(0, 0.085, -0.23), 0.046, 12) # objective bell
	b.cylinder_z(&"polymer", 0.046, 0.03, Vector3(0, 0.085, -0.295), -1.0, 12)
	b.cylinder_z(&"lens", 0.04, 0.004, Vector3(0, 0.085, -0.312), -1.0, 12)
	b.cylinder_z(&"polymer", 0.034, 0.07, Vector3(0, 0.085, 0.175), 0.027, 12) # eyepiece
	b.cylinder_z(&"gear", 0.035, 0.02, Vector3(0, 0.085, 0.215), -1.0, 12)
	b.cylinder_y(&"polymer", 0.017, 0.035, Vector3(0, 0.125, -0.02), 10) # elevation turret
	b.cylinder_y(&"steel", 0.018, 0.008, Vector3(0, 0.145, -0.02), 10)
	b.cylinder_x(&"polymer", 0.016, 0.035, Vector3(0.043, 0.085, -0.02), 10) # windage turret
	b.cylinder_x(&"polymer", 0.013, 0.03, Vector3(-0.04, 0.085, 0.03), 10) # parallax knob
	for z in [-0.1, 0.07]:
		b.box(&"steel", Vector3(0.064, 0.012, 0.024), Vector3(0, 0.085, z)) # ring clamps
		b.box(&"steel", Vector3(0.03, 0.03, 0.024), Vector3(0, 0.062, z)) # ring bases
	# Bolt, trigger group, magazine.
	b.cylinder_x(&"steel", 0.007, 0.06, Vector3(0.055, 0.045, 0.13))
	b.sphere(&"steel", 0.014, Vector3(0.088, 0.04, 0.13))
	b.box(&"steel", Vector3(0.008, 0.012, 0.06), Vector3(0, -0.058, 0.09)) # trigger guard
	# Thumbhole stock: grip, upper comb, lower butt, cheek piece and pad.
	b.box(&"olive", Vector3(0.04, 0.1, 0.05), Vector3(0, -0.08, 0.14), Vector3(-15, 0, 0)) # grip
	b.box(&"olive", Vector3(0.05, 0.04, 0.26), Vector3(0, 0.03, 0.33)) # comb
	b.box(&"olive", Vector3(0.05, 0.06, 0.2), Vector3(0, -0.1, 0.38), Vector3(-8, 0, 0)) # lower butt
	b.box(&"olive", Vector3(0.05, 0.12, 0.05), Vector3(0, -0.03, 0.21)) # front of the thumbhole
	b.box(&"polymer", Vector3(0.056, 0.05, 0.11), Vector3(0, 0.058, 0.33)) # cheek piece
	b.box(&"gear", Vector3(0.054, 0.17, 0.025), Vector3(0, -0.04, 0.47)) # butt pad
	# Folded bipod under the fore-end.
	for sx in [-1.0, 1.0]:
		b.cylinder_z(&"steel", 0.005, 0.16, Vector3(sx * 0.016, -0.05, -0.33))
		b.sphere(&"gear", 0.009, Vector3(sx * 0.016, -0.05, -0.41))
	b.box(&"steel", Vector3(0.05, 0.014, 0.03), Vector3(0, -0.045, -0.25))


static func _lmg(b: MeshBuilder) -> void: # K-100 (belt-fed, box magazine, bipod)
	b.box(&"steel", Vector3(0.068, 0.1, 0.44), Vector3(0, 0.0, 0.0)) # receiver
	b.box(&"steel", Vector3(0.05, 0.02, 0.1), Vector3(0, 0.055, 0.13)) # rear of the top (behind the cover)
	b.box(&"polymer", Vector3(0.074, 0.075, 0.2), Vector3(0, -0.005, -0.31)) # handguard
	for z in [-0.24, -0.29, -0.34, -0.39]:
		b.box(&"steel", Vector3(0.076, 0.012, 0.02), Vector3(0, 0.02, z)) # heat vents
	b.cylinder_z(&"steel", 0.014, 0.36, Vector3(0, 0.015, -0.5)) # barrel
	b.cylinder_z(&"polymer", 0.02, 0.05, Vector3(0, 0.015, -0.66)) # flash hider
	b.box(&"steel", Vector3(0.012, 0.05, 0.012), Vector3(0, 0.045, -0.52)) # front sight post base
	b.box(&"steel", Vector3(0.016, 0.07, 0.04), Vector3(0, 0.1, -0.12)) # carry handle post
	b.box(&"steel", Vector3(0.016, 0.014, 0.16), Vector3(0, 0.135, -0.16)) # carry handle
	b.box(&"polymer", Vector3(0.035, 0.1, 0.045), Vector3(0, -0.09, 0.12), Vector3(-15, 0, 0)) # grip
	b.box(&"steel", Vector3(0.008, 0.012, 0.06), Vector3(0, -0.058, 0.06)) # trigger guard
	b.box(&"steel", Vector3(0.012, 0.014, 0.04), Vector3(0.042, 0.02, -0.03)) # charging handle
	b.box(&"polymer", Vector3(0.05, 0.085, 0.22), Vector3(0, -0.02, 0.33)) # stock
	b.box(&"gear", Vector3(0.054, 0.11, 0.02), Vector3(0, -0.025, 0.45)) # butt pad
	b.box(&"steel", Vector3(0.06, 0.03, 0.03), Vector3(0, -0.06, -0.02)) # feed tray / magazine well
	for sx in [-1.0, 1.0]: # folded bipod
		b.cylinder_z(&"steel", 0.006, 0.2, Vector3(sx * 0.02, -0.05, -0.47))
		b.sphere(&"gear", 0.01, Vector3(sx * 0.02, -0.05, -0.57))
	_iron_sights(b, 0.055, 0.14, 0.06, -0.52)


static func _pistol(b: MeshBuilder) -> void: # P-9
	b.box(&"steel", Vector3(0.035, 0.04, 0.19), Vector3(0, 0.02, 0)) # slide
	for z in [0.05, 0.062, 0.074]:
		b.box(&"gear", Vector3(0.037, 0.028, 0.004), Vector3(0, 0.022, z)) # serrations
	b.box(&"polymer", Vector3(0.032, 0.03, 0.16), Vector3(0, -0.012, 0.005)) # frame
	b.box(&"polymer", Vector3(0.03, 0.11, 0.045), Vector3(0, -0.07, 0.07), Vector3(-15, 0, 0)) # grip
	b.box(&"polymer", Vector3(0.006, 0.012, 0.045), Vector3(0, -0.038, -0.01)) # trigger guard
	b.cylinder_z(&"steel", 0.007, 0.012, Vector3(0, 0.02, -0.098))
	for sx in [-1.0, 1.0]:
		b.box(&"steel", Vector3(0.005, 0.012, 0.01), Vector3(sx * 0.007, 0.046, 0.085))
	b.box(&"steel", Vector3(0.005, 0.012, 0.01), Vector3(0, 0.046, -0.085))
