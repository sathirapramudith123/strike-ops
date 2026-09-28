class_name SmokeCloud
extends Node3D
## Smoke grenade cloud: a thick grey cloud RADIUS metres across that you
## can't see through, lasting DURATION seconds (it billows out for the first
## second and thins out over the last two). Bullets still pass through it.
## It puts out Molotov fires inside it, and a Molotov that lands in it
## fizzles (FireZone checks `covers_point`). The same on every peer — it only
## depends on where the server said the grenade went off.

const RADIUS := 3.5
const HEIGHT := 3.0
const DURATION := 15.0
const GROUP := &"smoke_cloud"

var _time := 0.0
var _started := false


func start(pos: Vector3) -> void:
	global_position = pos
	_started = true
	add_to_group(GROUP)
	# Put out fires already burning here.
	for fire in get_tree().get_nodes_in_group(FireZone.GROUP):
		var f := fire as FireZone
		if f and covers_point(f.global_position + Vector3.UP * 0.2, 1.0):
			f.extinguish()
	if not NetworkManager.is_dedicated():
		add_child(_build_cloud())
		Audio.play_3d(&"smoke_hiss", pos, -2.0, 35.0, randf_range(0.95, 1.05), 5.0)


func is_active() -> bool:
	return _started and _time < DURATION


## True if `point` is inside the cloud (`grow` metres of slack).
func covers_point(point: Vector3, grow: float = 0.0) -> bool:
	if not is_active():
		return false
	var d := point - global_position
	return Vector2(d.x, d.z).length() <= RADIUS + grow and d.y > -1.0 - grow and d.y < HEIGHT + grow


## True if the line from `from` to `to` passes through any smoke cloud.
static func blocks_line(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		var c := node as SmokeCloud
		if c == null or not c.is_active():
			continue
		var center := c.global_position + Vector3.UP * 1.2
		var closest := Geometry3D.get_closest_point_to_segment(center, from, to)
		var off := closest - center
		if Vector2(off.x, off.z).length() < RADIUS * 0.85 and absf(off.y) < HEIGHT * 0.6:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not _started:
		return
	_time += delta
	if _time >= DURATION + 1.0:
		queue_free()


## Big soft grey puffs that spread out, hang and fade. The particles live
## the whole cloud's life (one burst), so the cloud doesn't flicker.
func _build_cloud() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Cloud"
	p.amount = 64
	p.lifetime = DURATION
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3.ZERO
	p.angular_velocity_min = -12.0
	p.angular_velocity_max = 12.0
	p.position.y = 0.6
	p.mesh = GrenadeFx.soft_quad(2.4, false, 0.0, 1.0, true)
	((p.mesh as QuadMesh).material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.6, 0.6, 0.0))
	ramp.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	var solid := 1.0 / DURATION # ~1 s to billow out
	ramp.add_point(solid, Color(0.6, 0.6, 0.6, 1.0))
	ramp.add_point(1.0 - 2.0 * solid, Color(0.55, 0.55, 0.55, 1.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.max_value = 2.0
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.08, 1.5))
	curve.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curve
	p.emitting = true
	return p
