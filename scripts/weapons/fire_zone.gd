class_name FireZone
extends Node3D
## Molotov fire: a patch of flames RADIUS metres across on the floor under
## where the bottle broke, burning for DURATION seconds. The server hurts
## everyone standing in it (TICK at a time, armour does not help); every
## peer shows the flames, smoke, flickering light and crackle.
## Teammates of the thrower are not hurt (same rule as bullets); the
## thrower is.

const RADIUS := 3.0
const DURATION := 7.0
const DPS := 25.0
const TICK := 0.25
## Feet between this far below and above the fire's floor are "in" it.
const BELOW := 0.6
const ABOVE := 1.2
## How far down the fire looks for a floor when the bottle broke in the air.
const DROP := 25.0

var thrower: PlayerController
var _time := 0.0
var _tick := 0.0
var _light: OmniLight3D
var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _lit := false


## Puts the fire on the floor below `pos` (nothing if there is no floor).
func ignite(pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * DROP, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		queue_free()
		return
	global_position = hit.position + Vector3.UP * 0.02
	_lit = true
	if not NetworkManager.is_dedicated():
		_build_visuals()
		Audio.play_3d(&"glass_break", global_position, -2.0, 40.0, randf_range(0.95, 1.05), 5.0)
		Audio.play_3d(&"fire", global_position + Vector3.UP * 0.3, -2.0, 35.0, randf_range(0.95, 1.05), 5.0)


func is_burning() -> bool:
	return _lit and _time < DURATION


## True if a body standing at `feet` is inside the flames (and no wall between).
func covers(feet: Vector3) -> bool:
	if not is_burning():
		return false
	var d := feet - global_position
	if Vector2(d.x, d.z).length() > RADIUS or d.y < -BELOW or d.y > ABOVE:
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, feet + Vector3.UP * 0.4, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	if not _lit:
		return
	_time += delta
	if _time >= DURATION:
		if _flames:
			_flames.emitting = false
			_smoke.emitting = false
		if _time >= DURATION + 1.5:
			queue_free()
		return
	if _light:
		_light.light_energy = 2.2 + sin(_time * 23.0) * 0.4 + sin(_time * 37.0) * 0.3
		# Die down over the last second.
		_light.light_energy *= clampf(DURATION - _time, 0.0, 1.0)
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var source: PlayerController = thrower if is_instance_valid(thrower) else null
	for node in get_tree().get_nodes_in_group(Health.NET_GROUP):
		var health := node as Health
		var target := health.get_parent() as Node3D
		if health.is_dead or target == null:
			continue
		var victim := target as PlayerController
		if victim and source and victim != source and Match.is_friendly(source.peer_id, victim.peer_id):
			continue
		if covers(target.global_position):
			health.take_damage(DPS * TICK, source, false, Throwables.NAMES[Throwables.Kind.MOLOTOV], 1.0, false)


func _build_visuals() -> void:
	# Scorched patch on the floor.
	var scorch := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.01
	disc.radial_segments = 20
	disc.rings = 1
	scorch.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.04, 0.03, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	scorch.material_override = sm
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scorch)
	_flames = _particles(64, 0.9, Color(1.0, 0.55, 0.15), 0.45, 2.6, true)
	add_child(_flames)
	_smoke = _particles(20, 2.5, Color(0.12, 0.11, 0.1, 0.55), 0.9, 1.4, false)
	_smoke.position.y = 0.8
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = RADIUS * 2.5
	_light.position.y = 0.8
	add_child(_light)


## Continuous particles over the whole disc, rising.
func _particles(amount: int, lifetime: float, color: Color, size: float, rise: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(RADIUS * 0.8, 0.05, RADIUS * 0.8)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector3.ZERO
	var quad := GrenadeFx.soft_quad(size, additive, 1.6 if additive else 0.0, 1.4)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r * 0.6, color.g * 0.3, color.b * 0.2, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = curve
	p.emitting = true
	return p
