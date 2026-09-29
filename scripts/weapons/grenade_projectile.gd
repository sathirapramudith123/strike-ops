class_name GrenadeProjectile
extends RigidBody3D
## A thrown grenade. Every peer simulates its own copy (same start, same
## physics), but only the server decides when it goes off: the HE, flash and
## smoke after their fuse (Throwables.FUSES), the Molotov when it smashes on
## a floor (or after MOLOTOV_MAX_FLIGHT in the air). See Throwables for the networking.

const RADIUS := 0.07
const MOLOTOV_MAX_FLIGHT := 2.5
## A contact whose normal points up at least this much counts as a floor.
const FLOOR_NORMAL_Y := 0.6
## Clients drop a projectile the server never detonated (lost message).
const CLIENT_TIMEOUT := 6.0

var kind: int = Throwables.Kind.HE
var thrower: PlayerController
var throwables: Throwables
var projectile_id: int = 0

var _age := 0.0
var _detonated := false
var _last_bounce_ms := 0


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 # world only: grenades fly past players
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	can_sleep = false
	mass = 0.4
	linear_damp = 0.05
	angular_damp = 1.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)


func _ready() -> void:
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.15 if kind == Throwables.Kind.MOLOTOV else 0.35
	mat.friction = 0.7
	physics_material_override = mat
	body_entered.connect(_on_body_entered)
	if not NetworkManager.is_dedicated():
		add_child(build_model(kind))


func launch(origin: Vector3, vel: Vector3) -> void:
	global_position = origin
	linear_velocity = vel
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))


func _physics_process(delta: float) -> void:
	_age += delta
	if global_position.y < -40.0:
		queue_free()
		return
	if not multiplayer.is_server():
		if _age > CLIENT_TIMEOUT:
			queue_free()
		return
	var fuse: float = Throwables.FUSES.get(kind, MOLOTOV_MAX_FLIGHT)
	if _age >= fuse:
		_detonate(global_position)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if kind != Throwables.Kind.MOLOTOV or not multiplayer.is_server() or _detonated:
		return
	for i in state.get_contact_count():
		if state.get_contact_local_normal(i).y >= FLOOR_NORMAL_Y:
			# Smashed on a floor: burn where it landed (deferred — the
			# physics state is locked inside this callback).
			_detonated = true
			_detonate_now.call_deferred(state.get_contact_local_position(i))
			return


func _detonate(pos: Vector3) -> void:
	if _detonated:
		return
	_detonated = true
	_detonate_now(pos)


func _detonate_now(pos: Vector3) -> void:
	if is_instance_valid(throwables):
		throwables.server_detonate(projectile_id, pos)
	else:
		queue_free() # the thrower left the game


func _on_body_entered(_body: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_bounce_ms < 120 or linear_velocity.length() < 1.5:
		return
	_last_bounce_ms = now
	if kind != Throwables.Kind.MOLOTOV:
		Audio.play_3d(&"grenade_bounce", global_position, -8.0, 25.0, randf_range(0.9, 1.1), 3.0)


## Small low-poly model: an olive-drab frag with a lever, a bottle with a
## burning rag, or a can (flash: grey with a white top; smoke: green-grey
## with a dark band).
static func build_model(grenade_kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	if grenade_kind == Throwables.Kind.FLASH or grenade_kind == Throwables.Kind.SMOKE:
		var smoke := grenade_kind == Throwables.Kind.SMOKE
		var can := _part(_cylinder(0.032, 0.032, 0.11), Color(0.32, 0.36, 0.3) if smoke else Color(0.45, 0.46, 0.48), 0.6)
		root.add_child(can)
		var band := _part(_cylinder(0.034, 0.034, 0.02), Color(0.12, 0.12, 0.12) if smoke else Color(0.9, 0.9, 0.85), 0.6)
		band.position.y = 0.035 if smoke else 0.057
		root.add_child(band)
		var lever := _part(_box(Vector3(0.014, 0.08, 0.008)), Color(0.4, 0.4, 0.38), 0.4)
		lever.position = Vector3(0.036, 0.02, 0)
		root.add_child(lever)
	elif grenade_kind == Throwables.Kind.HE:
		var body := _part(_sphere(0.055, 0.075), Color(0.25, 0.3, 0.18), 0.7)
		root.add_child(body)
		var cap := _part(_cylinder(0.022, 0.022, 0.03), Color(0.35, 0.35, 0.33), 0.4)
		cap.position = Vector3(0, 0.075, 0)
		root.add_child(cap)
		var lever := _part(_box(Vector3(0.016, 0.075, 0.008)), Color(0.4, 0.4, 0.38), 0.4)
		lever.position = Vector3(0.028, 0.045, 0)
		lever.rotation.z = -0.35
		root.add_child(lever)
	else:
		var glass := _part(_cylinder(0.04, 0.04, 0.14), Color(0.35, 0.22, 0.08, 0.85), 0.15)
		root.add_child(glass)
		var neck := _part(_cylinder(0.014, 0.03, 0.07), Color(0.35, 0.22, 0.08, 0.85), 0.15)
		neck.position = Vector3(0, 0.105, 0)
		root.add_child(neck)
		var rag := _part(_box(Vector3(0.03, 0.05, 0.03)), Color(0.75, 0.7, 0.6), 0.9)
		rag.position = Vector3(0, 0.155, 0)
		root.add_child(rag)
		var flame := _part(_sphere(0.035, 0.07), Color(1.0, 0.55, 0.15), 1.0, 3.0)
		flame.position = Vector3(0, 0.2, 0)
		root.add_child(flame)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.light_energy = 1.2
		light.omni_range = 3.0
		light.position = Vector3(0, 0.22, 0)
		root.add_child(light)
	return root


static func _part(mesh: Mesh, color: Color, roughness: float, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi


static func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 6
	return m


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
