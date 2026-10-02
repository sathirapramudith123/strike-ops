class_name FireZone
extends Node3D
## Molotov fire: a patch of flames RADIUS metres across on the floor under
## where the bottle broke, burning for DURATION seconds. The server hurts
## everyone standing in it (TICK at a time, armour does not help); every
## peer shows the flames, smoke, flickering light and crackle.
## Teammates of the thrower are not hurt (same rule as bullets); the
## thrower is. A smoke grenade puts it out (extinguish), and a bottle that
## breaks inside a smoke cloud doesn't light at all.

const RADIUS := 3.0
const DURATION := 7.0
const DPS := 25.0
const TICK := 0.25
## Feet between this far below and above the fire's floor are "in" it.
const BELOW := 0.6
const ABOVE := 1.2
## How far down the fire looks for a floor when the bottle broke in the air.
const DROP := 25.0
const GROUP := &"fire_zone"

var thrower: PlayerController
var _time := 0.0
var _tick := 0.0
var _light: OmniLight3D
var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _core: CPUParticles3D
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
	for node in get_tree().get_nodes_in_group(SmokeCloud.GROUP):
		if (node as SmokeCloud).covers_point(global_position + Vector3.UP * 0.2, 0.5):
			# Fizzles in the smoke: just the glass breaking.
			if not NetworkManager.is_dedicated():
				Audio.play_3d(&"glass_break", global_position, -2.0, 40.0, randf_range(0.95, 1.05), 5.0)
			queue_free()
			return
	_lit = true
	add_to_group(GROUP)
	if not NetworkManager.is_dedicated():
		_build_visuals()
		Audio.play_3d(&"glass_break", global_position, -2.0, 40.0, randf_range(0.95, 1.05), 5.0)
		Audio.play_3d(&"fire", global_position + Vector3.UP * 0.3, -2.0, 35.0, randf_range(0.95, 1.05), 5.0)


## Puts the fire out now (smoke grenade); the flames die down over ~1.5 s.
func extinguish() -> void:
	if is_burning():
		_time = DURATION


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
			if _core:
				_core.emitting = false
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
		if victim and source and Match.shields(source.peer_id, victim.peer_id):
			continue
		if covers(target.global_position):
			health.take_damage(DPS * TICK, source, false, Throwables.NAMES[Throwables.Kind.MOLOTOV], 1.0, false)


func _build_visuals() -> void:
	# Scorch and a pool of burning fuel on the floor.
	FxKit.ground_mark(self, FxKit.scorch_texture(), RADIUS * 2.4, DURATION)
	var fire_tex := FxKit.fire_texture()
	# Flames: many tall ragged tongues, orange bodies (alpha blended so the
	# colour stays deep on bright floors) over a hot yellow-white core.
	_flames = FxKit.emitter(FxKit.quad(fire_tex, 0.6, false, 1.0, 2.1), FxKit.count(130, 36), 0.75, false,
		[[0.0, Color(1, 0.62, 0.18, 0.0)], [0.1, Color(1, 0.55, 0.12, 0.95)], [0.5, Color(0.95, 0.3, 0.04, 0.75)],
			[1.0, Color(0.3, 0.05, 0.0, 0.0)]],
		[[0.0, 0.6], [0.25, 1.1], [1.0, 0.3]], Vector2(1.0, 2.2), 8.0, Vector3(0, 1.2, 0), 0.6, 25.0, 0.1)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flames.emission_box_extents = Vector3(RADIUS * 0.75, 0.05, RADIUS * 0.75)
	add_child(_flames)
	var core := FxKit.emitter(FxKit.quad(fire_tex, 0.5, true, 1.3, 1.4), FxKit.count(70, 20), 0.4, false,
		[[0.0, Color(1, 0.9, 0.55, 0.0)], [0.2, Color(1, 0.8, 0.4, 0.9)], [1.0, Color(1, 0.45, 0.1, 0.0)]],
		[[0.0, 0.7], [1.0, 0.5]], Vector2(0.4, 1.0), 10.0, Vector3(0, 0.8, 0), 0.5, 20.0, 0.1)
	core.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	core.emission_box_extents = Vector3(RADIUS * 0.75, 0.02, RADIUS * 0.75)
	add_child(core)
	_core = core
	# Glowing embers drifting up.
	var embers := FxKit.emitter(FxKit.quad(FxKit.spark_texture(), 0.05, true, 3.0), FxKit.count(30, 8), 1.8, false,
		[[0.0, Color(1, 0.7, 0.3, 1)], [1.0, Color(1, 0.3, 0.05, 0)]], [[0.0, 1.0], [1.0, 0.5]],
		Vector2(1.5, 3.5), 25.0, Vector3(0.3, 0.6, 0.1), 0.8, 0.0, 0.1)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(RADIUS * 0.7, 0.1, RADIUS * 0.7)
	add_child(embers)
	# Black smoke rolling up from the flames.
	_smoke = FxKit.emitter(FxKit.quad(FxKit.smoke_texture(), 1.2, false), FxKit.count(22, 8), 3.0, false,
		[[0.0, Color(0.08, 0.07, 0.06, 0.0)], [0.15, Color(0.1, 0.09, 0.08, 0.7)], [1.0, Color(0.25, 0.24, 0.23, 0.0)]],
		[[0.0, 0.6], [1.0, 2.4]], Vector2(1.2, 2.2), 15.0, Vector3(0.2, 0.5, 0.1), 0.6, 20.0, 0.1)
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(RADIUS * 0.6, 0.1, RADIUS * 0.6)
	_smoke.position.y = 1.0
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = RADIUS * 2.8
	_light.position.y = 0.8
	add_child(_light)
	# The bottle bursting: a puff of flame and glass glints.
	add_child(FxKit.emitter(FxKit.quad(fire_tex, 1.2, true, 1.1), 8, 0.4, true,
		[[0.0, Color(1, 0.8, 0.4, 1)], [1.0, Color(1, 0.3, 0.05, 0)]], [[0.0, 0.6], [1.0, 1.8]],
		Vector2(1.0, 3.0), 60.0, Vector3.ZERO, 3.0, 60.0, 0.1))
	add_child(FxKit.emitter(FxKit.quad(FxKit.spark_texture(), 0.04, true, 2.0), 14, 0.6, true,
		[[0.0, Color(0.85, 0.95, 1, 1)], [1.0, Color(0.85, 0.95, 1, 0)]], [[0.0, 1.0], [1.0, 1.0]],
		Vector2(2.0, 5.0), 70.0, Vector3(0, -9.0, 0), 1.0, 0.0, 0.05))
