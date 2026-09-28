class_name GrenadeArc
extends MeshInstance3D
## The predicted flight of the grenade in hand (local player only): a thin
## line along the path, bounces included, and a ring where it will go off —
## the HE, flash and smoke where their fuse runs out, the Molotov where it
## smashes on a floor. Worked out each frame from the same launch as a real
## throw (Throwables.throw_launch) with a simple copy of the physics, so it
## is a guide rather than exact after bounces. Turn it off in Settings →
## Gameplay ("Show grenade throw path").

const STEP := 1.0 / 60.0
const MAX_TIME := 3.0
const MAX_BOUNCES := 3
const WIDTH := 0.04
const RING_RADIUS := 0.55
const MARKER_HEIGHT := 1.2
const COLORS := {
	Throwables.Kind.HE: Color(1.0, 0.75, 0.3),
	Throwables.Kind.FLASH: Color(0.95, 0.97, 1.0),
	Throwables.Kind.SMOKE: Color(0.7, 0.85, 0.7),
	Throwables.Kind.MOLOTOV: Color(1.0, 0.45, 0.2),
}

var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	material_override = _material


## Where a grenade thrown from `origin` with `velocity` goes:
## { "points": PackedVector3Array, "end": Vector3, "normal": up at the end,
##   "landed": whether it ends on something }.
static func predict(space: PhysicsDirectSpaceState3D, origin: Vector3, velocity: Vector3, kind: int) -> Dictionary:
	var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var damp := float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)) + 0.05
	var molotov := kind == Throwables.Kind.MOLOTOV
	var bounce := 0.15 if molotov else 0.35
	var fuse: float = Throwables.FUSES.get(kind, GrenadeProjectile.MOLOTOV_MAX_FLIGHT)
	var p := origin
	var v := velocity
	var points := PackedVector3Array([p])
	var normal := Vector3.UP
	var landed := false
	var bounces := 0
	var t := 0.0
	while t < minf(fuse, MAX_TIME):
		v += gravity * STEP
		v *= maxf(0.0, 1.0 - damp * STEP)
		var next := p + v * STEP
		var q := PhysicsRayQueryParameters3D.create(p, next, 1)
		var hit := space.intersect_ray(q)
		t += STEP
		if hit.is_empty():
			p = next
			if points.size() < 400 and (points[-1].distance_squared_to(p) > 0.04 or t >= fuse):
				points.append(p)
			continue
		var n: Vector3 = hit.normal
		p = (hit.position as Vector3) + n * GrenadeProjectile.RADIUS
		points.append(p)
		normal = n
		landed = true
		if molotov and n.y >= GrenadeProjectile.FLOOR_NORMAL_Y:
			break
		bounces += 1
		var vn := n * v.dot(n)
		v = (v - vn) * 0.7 - vn * bounce
		if bounces > MAX_BOUNCES or v.length() < 0.8:
			# Rolling to a stop: it goes off about here.
			landed = n.y >= GrenadeProjectile.FLOOR_NORMAL_Y
			break
	if not landed:
		# In the air when the fuse runs out: the ring goes on the ground below.
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 30.0, 1))
		normal = down.normal if not down.is_empty() else Vector3.UP
	return { "points": points, "end": p, "normal": normal, "landed": landed }


## Draws `path` (from predict()) in the colour of `kind`.
func show_path(path: Dictionary, kind: int) -> void:
	visible = true
	_mesh.clear_surfaces()
	var points: PackedVector3Array = path.points
	if points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else points[0]
	var col: Color = COLORS.get(kind, Color.WHITE)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	for i in n - 1:
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).cross(eye - a).normalized() * WIDTH
		# Fade in near the hand so it doesn't cover the view.
		var ca := col
		var cb := col
		ca.a = clampf(float(i) / 6.0, 0.0, 1.0) * 0.85
		cb.a = clampf(float(i + 1) / 6.0, 0.0, 1.0) * 0.85
		_quad(a - side, a + side, b + side, b - side, ca, ca, cb, cb)
	# The ring where it goes off.
	var end: Vector3 = path.end
	var up: Vector3 = path.normal
	var basis := Basis.looking_at(up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD), up)
	var ring := col
	ring.a = 0.9
	var segs := 24
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := basis * Vector3(cos(a0), 0, sin(a0))
		var o1 := basis * Vector3(cos(a1), 0, sin(a1))
		var c := end + up * 0.03
		_quad(c + o0 * RING_RADIUS, c + o1 * RING_RADIUS, c + o1 * (RING_RADIUS - 0.12), c + o0 * (RING_RADIUS - 0.12),
			ring, ring, ring, ring)
		# A faint filled disc inside the ring.
		var fill := col
		fill.a = 0.25
		_mesh.surface_set_color(fill)
		_mesh.surface_add_vertex(c)
		_mesh.surface_add_vertex(c + o0 * (RING_RADIUS - 0.12))
		_mesh.surface_add_vertex(c + o1 * (RING_RADIUS - 0.12))
	# A short upright marker, so the spot shows when looking along the throw.
	var side := up.cross(eye - end)
	side = (side.normalized() if side.length() > 0.001 else basis.x) * WIDTH * 1.5
	var top := col
	top.a = 0.0
	_quad(end - side, end + side, end + side + up * MARKER_HEIGHT, end - side + up * MARKER_HEIGHT, ring, ring, top, top)
	_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	for v: Array in [[a, ca], [b, cb], [c, cc], [a, ca], [c, cc], [d, cd]]:
		_mesh.surface_set_color(v[1])
		_mesh.surface_add_vertex(v[0])
