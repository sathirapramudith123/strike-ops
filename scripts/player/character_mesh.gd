class_name CharacterMesh
extends RefCounted
## Builds the third-person character meshes for a CharacterLook: the body
## (torso, head and face, hair, headwear, vest, backpack, right arm), one leg
## (both legs share it) and the left arm (its own node for the reload
## motion). Same skeleton as PlayerModel for every look; a female body is
## slimmer at the shoulders and waist, wider at the hips, with a smaller head.
##
## Team colour ("armor", tinted per player) stays on the shoulder pads, the
## armbands, a patch on the vest and the helmet band, so teams are told apart
## whatever the outfit. Meshes are cached per look (identical looks share).

const HEAD := Vector3(0, 1.62, -0.01)

static var _cache: Dictionary = {}


## { "body", "leg" (thigh), "shin", "arm_l": ArrayMesh } for `look`.
static func get_meshes(look: Dictionary) -> Dictionary:
	var clean: Dictionary = CharacterLook.sanitize(look)
	var key: String = CharacterLook.key_of(clean)
	if not _cache.has(key):
		_cache[key] = _build(clean)
	return _cache[key]


static func _build(look: Dictionary) -> Dictionary:
	var female := int(look.body) == 1
	var face: Dictionary = CharacterLook.face_of(look)
	var torso: Dictionary = CharacterLook.TORSO[int(look.torso)]
	var pack: Dictionary = CharacterLook.BACKPACKS[int(look.backpack)]
	var gloves: Dictionary = CharacterLook.GLOVES[int(look.gloves)]
	var boots: Dictionary = CharacterLook.BOOTS[int(look.boots)]

	var b := MeshBuilder.new()
	_define(b, look)
	var w := 0.9 if female else 1.0 # shoulder / chest width

	# --- Torso ------------------------------------------------------------------
	if female:
		b.box(&"shirt", Vector3(0.34, 0.26, 0.21), Vector3(0, 1.34, 0))
		b.box(&"shirt", Vector3(0.28, 0.24, 0.18), Vector3(0, 1.11, 0))
		b.box(&"pants", Vector3(0.35, 0.15, 0.22), Vector3(0, 0.92, 0)) # hips
	else:
		b.box(&"shirt", Vector3(0.38, 0.5, 0.22), Vector3(0, 1.22, 0))
		b.box(&"pants", Vector3(0.34, 0.14, 0.22), Vector3(0, 0.92, 0))
	b.box(&"gear", Vector3(0.36 if not female else 0.34, 0.06, 0.24), Vector3(0, 0.99, 0)) # belt
	b.box(&"steel", Vector3(0.05, 0.04, 0.02), Vector3(0, 0.99, -0.125)) # buckle
	_vest(b, int(torso.style), w)
	_backpack(b, int(pack.style), w)

	# --- Neck, head, face -------------------------------------------------------
	var r := 0.1 if female else 0.105
	b.cylinder_y(&"skin_c", 0.05 if female else 0.055, 0.1, Vector3(0, 1.5, 0))
	b.sphere(&"skin_c", r, HEAD, Vector3(1, 1.1, 1), false, 12)
	var hw := int(look.headwear)
	var masked := hw == 5 # balaclava: only the eyes show
	_face(b, look, face, r, masked)
	if not masked:
		_hair(b, int(face.style), r, hw)
	_headwear(b, hw, r)

	# --- Shoulders (team colour), right arm holding the gun ---------------------
	for sx in [-1.0, 1.0]:
		b.sphere(&"armor", 0.07 if female else 0.075, Vector3(sx * 0.23 * w, 1.44, 0), Vector3(1, 0.8, 1))
	var r_shoulder := Vector3(0.23 * w, 1.42, 0.0)
	var r_elbow := Vector3(0.26 * w, 1.2, -0.12)
	var r_hand := Vector3(0.1, 1.27, -0.3)
	_arm(b, r_shoulder, r_elbow, r_hand, female, gloves)
	var body := b.build()

	# --- Left arm (pivot at the shoulder) ---------------------------------------
	var a := MeshBuilder.new()
	_define(a, look)
	var ls := PlayerModel.L_SHOULDER
	var l_elbow := Vector3(-0.2 * w, 1.22, -0.3) - ls
	var l_hand := Vector3(0.05, 1.3, -0.52) - ls
	_arm(a, Vector3((1.0 - w) * 0.23, 0, 0), l_elbow, l_hand, female, gloves)
	var arm_l := a.build()

	# --- One leg: thigh (pivot at the hip) and shin (pivot at the knee) --------
	var l := MeshBuilder.new()
	_define(l, look)
	var t := 0.92 if female else 1.0
	l.limb(&"pants", Vector3(0, 0.02, 0), Vector3(0, -0.44, -0.02), 0.075 * t, 0.062 * t)
	var n := MeshBuilder.new()
	_define(n, look)
	var k := PlayerModel.KNEE # the shin is built round the knee
	n.limb(&"pants", Vector3.ZERO, Vector3(0, -0.82, 0.0) - k, 0.058 * t, 0.05 * t)
	if int(look.pants) not in [2, 3]: # knee pads (not with khakis or jeans)
		n.sphere(&"gear", 0.06, Vector3(0, -0.45, -0.06) - k, Vector3(1, 1.1, 0.7))
	if bool(boots.tall):
		n.limb(&"boot", Vector3(0, -0.84, 0.0) - k, Vector3(0, -0.62, -0.005) - k, 0.058 * t, 0.06 * t)
	n.box(&"boot", Vector3(0.11, 0.09, 0.24), Vector3(0, -0.855, -0.04) - k)
	n.box(&"gear", Vector3(0.115, 0.02, 0.25), Vector3(0, -0.895, -0.04) - k) # sole
	return { "body": body, "arm_l": arm_l, "leg": l.build(), "shin": n.build() }


## The look's own colours on a builder.
static func _define(b: MeshBuilder, look: Dictionary) -> void:
	var face: Dictionary = CharacterLook.face_of(look)
	var outfit: Dictionary = CharacterLook.OUTFITS[int(look.outfit)]
	var torso: Dictionary = CharacterLook.TORSO[int(look.torso)]
	var pack: Dictionary = CharacterLook.BACKPACKS[int(look.backpack)]
	var gloves: Dictionary = CharacterLook.GLOVES[int(look.gloves)]
	var pants: Dictionary = CharacterLook.PANTS[int(look.pants)]
	var boots: Dictionary = CharacterLook.BOOTS[int(look.boots)]
	var skin: Color = face.skin
	b.define(&"skin_c", skin)
	b.define(&"skin_dark", skin.darkened(0.12))
	b.define(&"hair", face.hair)
	b.define(&"stubble", skin.lerp(face.hair, 0.3))
	b.define(&"lip", skin.lerp(Color(0.55, 0.22, 0.2), 0.45))
	b.define(&"mouth_in", Color(0.18, 0.05, 0.05))
	b.define(&"teeth", Color(0.9, 0.88, 0.82))
	b.define(&"eye_white", Color(0.92, 0.92, 0.9))
	b.define(&"iris", CharacterLook.EYES[int(look.eyes)].color)
	b.define(&"gold", Color(0.85, 0.66, 0.25), 0.9)
	b.define(&"shirt", outfit.shirt, 0.0, int(outfit.pattern))
	b.define(&"vest", torso.color, 0.0, int(torso.pattern))
	b.define(&"vest_dark", (torso.color as Color).darkened(0.25))
	b.define(&"pack", pack.color, 0.0, int(pack.pattern))
	var gc: Color = gloves.color
	b.define(&"glove_c", skin if gc.r < 0.0 else gc)
	b.define(&"pants", pants.color, 0.0, int(pants.pattern))
	b.define(&"boot", boots.color)
	# Headwear takes the outfit's look: shirt colour, vest colour for helmets.
	b.define(&"hat", (outfit.shirt as Color).darkened(0.1), 0.0, int(outfit.pattern))
	b.define(&"helmet", torso.color if int(torso.pattern) == 0 else (torso.color as Color).darkened(0.15), 0.0,
		int(torso.pattern))
	b.define(&"knit", (outfit.shirt as Color).darkened(0.35) if int(look.outfit) != 4 else Color(0.8, 0.8, 0.82))


static func _arm(b: MeshBuilder, shoulder: Vector3, elbow: Vector3, hand: Vector3, female: bool,
		gloves: Dictionary) -> void:
	var t := 0.9 if female else 1.0
	b.limb(&"shirt", shoulder, elbow, 0.055 * t, 0.05 * t)
	b.limb(&"shirt", elbow, hand, 0.048 * t, 0.042 * t)
	# Armband in the team colour.
	b.limb(&"armor", shoulder.lerp(elbow, 0.35), shoulder.lerp(elbow, 0.55), 0.06 * t, 0.057 * t)
	b.sphere(&"glove_c", 0.045 * t, hand)
	if bool(gloves.fingerless):
		b.sphere(&"skin_c", 0.03 * t, hand + (hand - elbow).normalized() * 0.035)


static func _vest(b: MeshBuilder, style: int, w: float) -> void:
	match style:
		0: # plate carrier: plates, a row of pouches, straps over the shoulders
			b.box(&"vest", Vector3(0.42 * w, 0.34, 0.27), Vector3(0, 1.28, -0.005))
			for x in [-0.12, 0.0, 0.12]:
				b.box(&"vest_dark", Vector3(0.1 * w, 0.085, 0.04), Vector3(x * w, 1.18, -0.155))
			for sx in [-1.0, 1.0]:
				b.box(&"vest", Vector3(0.06, 0.04, 0.25), Vector3(sx * 0.13 * w, 1.47, 0))
		1: # chest rig: straps and a pouch panel low on the chest
			for sx in [-1.0, 1.0]:
				b.box(&"vest", Vector3(0.055, 0.36, 0.24), Vector3(sx * 0.1 * w, 1.3, 0))
			b.box(&"vest", Vector3(0.36 * w, 0.15, 0.07), Vector3(0, 1.13, -0.13))
			for x in [-0.12, -0.04, 0.04, 0.12]:
				b.box(&"vest_dark", Vector3(0.07 * w, 0.1, 0.03), Vector3(x * w, 1.14, -0.175))
		2: # light vest
			b.box(&"vest", Vector3(0.4 * w, 0.3, 0.25), Vector3(0, 1.27, -0.003))
			b.box(&"vest_dark", Vector3(0.12, 0.07, 0.03), Vector3(0.08, 1.2, -0.135))
		3: # heavy armour: bigger plates, collar, groin flap
			b.box(&"vest", Vector3(0.46 * w, 0.4, 0.3), Vector3(0, 1.26, -0.005))
			b.cylinder_y(&"vest", 0.1, 0.07, Vector3(0, 1.49, 0), 10)
			b.box(&"vest", Vector3(0.18, 0.15, 0.04), Vector3(0, 0.93, -0.13))
			for x in [-0.14, 0.0, 0.14]:
				b.box(&"vest_dark", Vector3(0.11 * w, 0.09, 0.04), Vector3(x * w, 1.16, -0.17))
	# Team patch on the chest.
	b.box(&"armor", Vector3(0.07, 0.045, 0.012), Vector3(-0.1 * w, 1.38, -0.15 if style != 1 else -0.12))


static func _backpack(b: MeshBuilder, style: int, w: float) -> void:
	match style:
		1: # assault pack
			b.box(&"pack", Vector3(0.3 * w, 0.36, 0.14), Vector3(0, 1.28, 0.19))
			b.box(&"pack", Vector3(0.26 * w, 0.08, 0.1), Vector3(0, 1.5, 0.19))
			b.box(&"gear", Vector3(0.22 * w, 0.12, 0.03), Vector3(0, 1.22, 0.275))
		2: # rucksack: big, side pockets, a bedroll on top
			b.box(&"pack", Vector3(0.34 * w, 0.46, 0.2), Vector3(0, 1.25, 0.22))
			for sx in [-1.0, 1.0]:
				b.box(&"pack", Vector3(0.06, 0.2, 0.14), Vector3(sx * 0.2 * w, 1.18, 0.22))
			b.cylinder_x(&"gear", 0.06, 0.34 * w, Vector3(0, 1.52, 0.22), 8)
		3: # sling bag across the back, strap over the chest
			b.box(&"pack", Vector3(0.2, 0.2, 0.1), Vector3(0.08, 1.12, 0.16))
			b.limb(&"gear", Vector3(-0.17 * w, 1.46, -0.13), Vector3(0.15 * w, 1.06, -0.13), 0.018)


static func _face(b: MeshBuilder, look: Dictionary, face: Dictionary, r: float, masked: bool) -> void:
	var fz := HEAD.z - r # front of the face
	var s := r / 0.105
	var beard := int(face.beard)
	if masked:
		# Balaclava: a skin band round the eyes on the mask's surface.
		fz -= 0.009
		b.box(&"skin_c", Vector3(0.13 * s, 0.036, 0.02), Vector3(0, 1.64, fz + 0.012))
	# Eyes.
	for sx in [-1.0, 1.0]:
		var e := Vector3(sx * 0.036 * s, 1.638, fz + 0.016)
		b.sphere(&"eye_white", 0.016 * s, e, Vector3(1, 0.7, 0.6), false, 8)
		b.sphere(&"iris", 0.0085 * s, e + Vector3(0, 0, -0.0075), Vector3(1, 1, 0.5), false, 6)
		if not masked:
			b.box(&"hair", Vector3(0.032 * s, 0.007, 0.01), Vector3(sx * 0.037 * s, 1.662, fz + 0.01),
				Vector3(0, 0, -sx * 6.0))
	if masked:
		return
	# Nose.
	b.box(&"skin_dark", Vector3(0.02 * s, 0.034, 0.026), Vector3(0, 1.616, fz + 0.002), Vector3(12, 0, 0))
	# Beard (drawn before the mouth so the mouth sits on it).
	var mz := fz + 0.012
	match beard:
		1:
			b.sphere(&"stubble", 0.098 * s, Vector3(0, 1.566, HEAD.z - 0.008), Vector3(1.02, 0.56, 1.02), false, 10)
			mz = fz - 0.004
		2:
			b.sphere(&"hair", 0.1 * s, Vector3(0, 1.562, HEAD.z - 0.012), Vector3(1.05, 0.64, 1.05), false, 10)
			mz = fz - 0.008
		3:
			b.box(&"hair", Vector3(0.05, 0.012, 0.012), Vector3(0, 1.598, fz + 0.006))
	_mouth(b, int(look.mouth), Vector3(0, 1.584, mz), s)
	# Ears.
	for sx in [-1.0, 1.0]:
		_ear(b, int(look.ears), Vector3(sx * (r - 0.004), 1.625, HEAD.z + 0.01), sx)


static func _mouth(b: MeshBuilder, kind: int, at: Vector3, s: float) -> void:
	var half := 0.012 * s
	match kind:
		0: # normal
			b.box(&"lip", Vector3(0.042 * s, 0.011, 0.012), at)
		1: # smirk: one corner up
			b.box(&"lip", Vector3(0.042 * s, 0.01, 0.012), at, Vector3(0, 0, 9))
		2: # grim: corners down
			b.box(&"lip", Vector3(0.024 * s, 0.009, 0.012), at + Vector3(-half, 0, 0), Vector3(0, 0, 14))
			b.box(&"lip", Vector3(0.024 * s, 0.009, 0.012), at + Vector3(half, 0, 0), Vector3(0, 0, -14))
		3: # open (talking)
			b.box(&"mouth_in", Vector3(0.034 * s, 0.016, 0.012), at)
			b.box(&"lip", Vector3(0.04 * s, 0.006, 0.013), at + Vector3(0, 0.01, 0))
			b.box(&"lip", Vector3(0.036 * s, 0.006, 0.013), at + Vector3(0, -0.01, 0))
		4: # shout
			b.sphere(&"mouth_in", 0.02 * s, at + Vector3(0, -0.004, 0), Vector3(1, 1.2, 0.45), false, 8)
			b.box(&"teeth", Vector3(0.026 * s, 0.006, 0.01), at + Vector3(0, 0.014, -0.002))
		5: # clench: teeth showing
			b.box(&"teeth", Vector3(0.04 * s, 0.012, 0.012), at)
			b.box(&"mouth_in", Vector3(0.04 * s, 0.002, 0.013), at)
		6: # neutral: a thin line
			b.box(&"mouth_in", Vector3(0.04 * s, 0.004, 0.012), at)
		7: # smile: corners up
			b.box(&"lip", Vector3(0.024 * s, 0.009, 0.012), at + Vector3(-half, 0, 0), Vector3(0, 0, -14))
			b.box(&"lip", Vector3(0.024 * s, 0.009, 0.012), at + Vector3(half, 0, 0), Vector3(0, 0, 14))


static func _ear(b: MeshBuilder, kind: int, at: Vector3, sx: float) -> void:
	var size := [0.024, 0.03, 0.037, 0.03, 0.03, 0.028, 0.03, 0.03][kind] as float
	var scale := Vector3(0.35, 1.0, 0.65)
	if kind == 4:
		scale = Vector3(0.4, 0.85, 0.85)
	elif kind == 5:
		scale = Vector3(0.22, 0.9, 0.5)
	b.sphere(&"skin_c", size, at, scale, false, 8)
	match kind:
		3: # pointed tip
			b.box(&"skin_c", Vector3(0.008, 0.03, 0.012), at + Vector3(sx * 0.003, 0.03, 0.006), Vector3(-20, 0, sx * -15))
		6: # scar: a notch
			b.box(&"skin_dark", Vector3(0.012, 0.006, 0.02), at + Vector3(sx * 0.006, 0.012, 0))
		7: # earring
			b.sphere(&"gold", 0.007, at + Vector3(sx * 0.004, -0.028, 0))


## Hair styles: 0 buzz, 1 short, 2 side part, 3 slicked back, 4 fade with
## volume on top, 5 ponytail, 6 bun, 7 long straight, 8 bob, 9 braid.
static func _hair(b: MeshBuilder, style: int, r: float, headwear: int) -> void:
	var covered := headwear in [2, 4, 7] # helmets and beanies hide the top
	var cap_r := r + (0.003 if style == 0 else 0.007)
	if not covered or style >= 5:
		b.sphere(&"hair", cap_r, HEAD + Vector3(0, 0.042, 0.008), Vector3(1.0, 0.8, 1.02), true, 12)
		# Down the back of the head.
		b.sphere(&"hair", cap_r * 0.97, HEAD + Vector3(0, -0.005, 0.02), Vector3(1.0, 0.9, 0.95), false, 10)
	if covered and style < 5:
		return
	match style:
		2:
			b.box(&"hair", Vector3(0.1, 0.03, 0.05), HEAD + Vector3(0.02, 0.105, -0.07), Vector3(-15, 0, -8))
		3:
			b.sphere(&"hair", r * 0.9, HEAD + Vector3(0, 0.05, 0.04), Vector3(1.05, 0.7, 1.1), false, 10)
		4:
			b.sphere(&"hair", r * 0.75, HEAD + Vector3(0, 0.1, -0.01), Vector3(1, 0.55, 1.1), false, 10)
		5: # ponytail
			b.sphere(&"hair", 0.035, HEAD + Vector3(0, 0.05, 0.1))
			b.limb(&"hair", HEAD + Vector3(0, 0.04, 0.12), HEAD + Vector3(0, -0.2, 0.15), 0.028, 0.012)
		6: # bun
			b.sphere(&"hair", 0.045, HEAD + Vector3(0, 0.08, 0.09))
		7: # long straight: down the back to the shoulder blades
			b.sphere(&"hair", r * 1.04, HEAD + Vector3(0, -0.01, 0.035), Vector3(1.04, 1.0, 1.0), false, 12)
			b.box(&"hair", Vector3(0.19, 0.24, 0.05), HEAD + Vector3(0, -0.15, 0.085), Vector3(-8, 0, 0))
		8: # bob: full to the jaw, behind the face
			b.sphere(&"hair", r * 1.06, HEAD + Vector3(0, -0.02, 0.035), Vector3(1.06, 0.95, 1.0), false, 12)
		9: # braid over the shoulder
			b.limb(&"hair", HEAD + Vector3(0.05, -0.02, 0.1), HEAD + Vector3(0.12, -0.14, 0.06), 0.025, 0.022)
			b.limb(&"hair", HEAD + Vector3(0.12, -0.14, 0.06), HEAD + Vector3(0.14, -0.3, -0.05), 0.022, 0.012)


static func _headwear(b: MeshBuilder, kind: int, r: float) -> void:
	var top := HEAD + Vector3(0, 0.03, 0.005)
	match kind:
		1: # cap with a brim
			b.sphere(&"hat", r + 0.01, HEAD + Vector3(0, 0.035, 0.005), Vector3(1, 0.78, 1.04), true, 12)
			b.box(&"hat", Vector3(0.17, 0.012, 0.09), HEAD + Vector3(0, 0.04, -0.14), Vector3(-8, 0, 0))
		2, 7: # helmet (7: tactical — ear cups, night-vision mount, rails)
			b.sphere(&"helmet", r + 0.03, top, Vector3(1, 0.85, 1.05), true, 12)
			b.box(&"armor", Vector3(0.27, 0.022, 0.285), top + Vector3(0, 0.015, 0)) # team band
			if kind == 7:
				for sx in [-1.0, 1.0]:
					b.cylinder_x(&"gear", 0.045, 0.045, HEAD + Vector3(sx * (r + 0.01), 0.0, 0.01), 10)
					b.box(&"gear", Vector3(0.015, 0.03, 0.12), top + Vector3(sx * (r + 0.025), 0.035, 0))
				b.box(&"gear", Vector3(0.05, 0.05, 0.035), top + Vector3(0, 0.07, -0.12))
				b.cylinder_z(&"steel", 0.016, 0.05, top + Vector3(0, 0.1, -0.13))
		3: # boonie hat
			b.cylinder_y(&"hat", r + 0.006, 0.07, HEAD + Vector3(0, 0.075, 0.005), 12)
			b.sphere(&"hat", r + 0.006, HEAD + Vector3(0, 0.105, 0.005), Vector3(1, 0.35, 1), true, 12)
			b.cylinder_y(&"hat", r + 0.085, 0.012, HEAD + Vector3(0, 0.045, 0.005), 14)
		4: # beanie
			b.sphere(&"knit", r + 0.012, HEAD + Vector3(0, 0.03, 0.005), Vector3(1, 0.95, 1.03), true, 12)
			b.cylinder_y(&"knit", r + 0.014, 0.035, HEAD + Vector3(0, 0.04, 0.005), 12)
		5: # balaclava over the whole head
			b.sphere(&"knit", r + 0.008, HEAD, Vector3(1, 1.1, 1), false, 12)
			b.cylinder_y(&"knit", 0.06, 0.08, Vector3(0, 1.5, 0), 10)
		6: # headset: band over the top, ear cups, a mic boom
			b.box(&"gear", Vector3(0.018, 0.02, 0.03), HEAD + Vector3(0, r * 1.1 + 0.01, 0.01))
			for sx in [-1.0, 1.0]:
				b.limb(&"gear", HEAD + Vector3(0, r * 1.1 + 0.01, 0.01), HEAD + Vector3(sx * (r + 0.012), 0.02, 0.01), 0.01)
				b.cylinder_x(&"gear", 0.042, 0.04, HEAD + Vector3(sx * (r + 0.014), 0.0, 0.01), 10)
			b.limb(&"gear", HEAD + Vector3(-(r + 0.02), -0.02, 0.0), HEAD + Vector3(-0.03, -0.045, -r - 0.005), 0.005)
			b.sphere(&"gear", 0.01, HEAD + Vector3(-0.03, -0.045, -r - 0.006))
