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
}


static func has_model(weapon_id: String) -> bool:
	return weapon_id in ["rifle", "smg", "shotgun", "sniper", "pistol"]


## The whole gun (third person). `with_magazine = false`: the viewmodel's
## gun, whose magazine is a separate node (see get_magazine_mesh).
static func get_mesh(weapon_id: String, with_magazine: bool = true) -> ArrayMesh:
	var key := weapon_id if with_magazine else weapon_id + ":nomag"
	if not _cache.has(key):
		var b := MeshBuilder.new()
		match weapon_id:
			"rifle": _rifle(b)
			"smg": _smg(b)
			"shotgun": _shotgun(b)
			"sniper": _sniper(b)
			"pistol": _pistol(b)
		if with_magazine and weapon_id != "shotgun":
			_magazine(b, weapon_id)
		_cache[key] = b.build()
	return _cache[key]


## The magazine (shotgun: one shell), in weapon space where it sits in the gun.
static func get_magazine_mesh(weapon_id: String) -> ArrayMesh:
	var key := weapon_id + ":mag"
	if not _cache.has(key) and has_model(weapon_id):
		var b := MeshBuilder.new()
		_magazine(b, weapon_id)
		_cache[key] = b.build()
	return _cache.get(key)


static func _magazine(b: MeshBuilder, weapon_id: String) -> void:
	match weapon_id:
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
static func get_arm_mesh(weapon_id: String, left: bool) -> ArrayMesh:
	var key := weapon_id + (":L" if left else ":R")
	if not _arms_cache.has(key) and HANDS.has(weapon_id):
		var h: Dictionary = HANDS[weapon_id]
		var b := MeshBuilder.new()
		if not left:
			_right_hand(b, h.grip, h.grip_tilt)
		else:
			match h.left_kind:
				"under": _left_hand_under(b, h.left)
				"vertical": _left_hand_vertical(b, h.left)
				_: _left_hand_support(b, h.left)
		_arms_cache[key] = b.build()
	return _arms_cache.get(key)


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
