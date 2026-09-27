class_name WeaponModel
extends RefCounted
## Low-poly gun models built from code (one mesh per weapon, cached): used as
## the first-person viewmodel and in the third-person player's hands.
## Units are metres, -Z = muzzle. The iron sights keep the exact positions the
## weapons' ADS offsets were tuned for (sight top ≈ -ads_position.y).

static var _cache: Dictionary = {}


static func has_model(weapon_id: String) -> bool:
	return weapon_id in ["rifle", "smg", "shotgun", "sniper", "pistol"]


static func get_mesh(weapon_id: String) -> ArrayMesh:
	if not _cache.has(weapon_id):
		var b := MeshBuilder.new()
		match weapon_id:
			"rifle": _rifle(b)
			"smg": _smg(b)
			"shotgun": _shotgun(b)
			"sniper": _sniper(b)
			"pistol": _pistol(b)
		_cache[weapon_id] = b.build()
	return _cache[weapon_id]


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
	b.box(&"polymer", Vector3(0.035, 0.14, 0.06), Vector3(0, -0.1, -0.06), Vector3(15, 0, 0)) # magazine
	b.box(&"polymer", Vector3(0.037, 0.02, 0.064), Vector3(0, -0.168, -0.042), Vector3(15, 0, 0))
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
	b.box(&"polymer", Vector3(0.03, 0.2, 0.045), Vector3(0, -0.13, -0.05)) # long magazine
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


static func _sniper(b: MeshBuilder) -> void: # LR-50
	b.box(&"olive", Vector3(0.06, 0.09, 0.4), Vector3.ZERO)
	b.cylinder_z(&"steel", 0.013, 0.55, Vector3(0, 0.01, -0.47), 0.011)
	b.box(&"steel", Vector3(0.035, 0.03, 0.06), Vector3(0, 0.01, -0.76)) # muzzle brake
	b.cylinder_z(&"polymer", 0.025, 0.3, Vector3(0, 0.085, -0.02)) # scope
	b.cylinder_z(&"polymer", 0.025, 0.08, Vector3(0, 0.085, -0.18), 0.034) # objective bell
	b.cylinder_z(&"polymer", 0.03, 0.05, Vector3(0, 0.085, 0.145)) # eyepiece
	b.cylinder_z(&"lens", 0.03, 0.004, Vector3(0, 0.085, -0.222)) # lens
	b.cylinder_y(&"polymer", 0.012, 0.03, Vector3(0, 0.12, -0.02)) # turret
	b.cylinder_x(&"polymer", 0.011, 0.03, Vector3(0.037, 0.085, -0.02))
	for z in [-0.08, 0.06]:
		b.box(&"steel", Vector3(0.022, 0.045, 0.02), Vector3(0, 0.05, z)) # rings
	b.cylinder_x(&"steel", 0.006, 0.05, Vector3(0.05, 0.02, 0.1)) # bolt handle
	b.sphere(&"steel", 0.011, Vector3(0.077, 0.02, 0.1))
	b.box(&"polymer", Vector3(0.04, 0.07, 0.08), Vector3(0, -0.08, -0.02)) # magazine
	b.box(&"olive", Vector3(0.05, 0.1, 0.3), Vector3(0, -0.02, 0.33)) # stock
	b.box(&"olive", Vector3(0.03, 0.03, 0.12), Vector3(0, 0.045, 0.3)) # cheek riser
	b.box(&"polymer", Vector3(0.036, 0.09, 0.05), Vector3(0, -0.08, 0.14), Vector3(-15, 0, 0)) # grip
	for sx in [-1.0, 1.0]:
		b.cylinder_z(&"steel", 0.005, 0.15, Vector3(sx * 0.015, -0.04, -0.33)) # folded bipod


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
