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


## Billowing grey smoke (noise-textured puffs, baked light on top) that
## spreads out, hangs and fades, plus a thin jet hissing out of the canister
## for the first seconds. The cloud's puffs live its whole life (one burst)
## so it doesn't flicker; it keeps enough of them on every Particles
## setting to stay opaque (it blocks sight for everyone).
func _build_cloud() -> Node3D:
	var root := Node3D.new()
	root.name = "Cloud"
	var tex := FxKit.smoke_texture()
	var n := maxi(56, FxKit.count(80))
	var shades := [Color(0.62, 0.62, 0.63), Color(0.7, 0.7, 0.71), Color(0.55, 0.55, 0.56)]
	for i in 3:
		var c: Color = shades[i]
		var solid := 1.0 / DURATION
		var p := FxKit.emitter(FxKit.quad(tex, 2.6, false), n / 3, DURATION, true,
			[[0.0, Color(c, 0.0)], [solid, Color(c, 1.0)], [1.0 - 2.0 * solid, Color(c.lightened(0.05), 0.95)], [1.0, Color(c, 0.0)]],
			[[0.0, 0.35], [0.08, 1.4], [1.0, 1.75]], Vector2(2.2, 4.6), 75.0, Vector3.ZERO, 2.4, 10.0, 1.0)
		p.position.y = 0.6 + i * 0.25
		root.add_child(p)
	# The hissing jet from the canister.
	var jet := FxKit.emitter(FxKit.quad(tex, 0.6, false), FxKit.count(24, 8), 1.4, false,
		[[0.0, Color(0.8, 0.8, 0.82, 0.0)], [0.15, Color(0.8, 0.8, 0.82, 0.8)], [1.0, Color(0.7, 0.7, 0.72, 0.0)]],
		[[0.0, 0.4], [1.0, 2.5]], Vector2(3.0, 5.0), 25.0, Vector3(0, 0.5, 0), 2.0, 40.0, 0.05)
	jet.position.y = 0.1
	root.add_child(jet)
	var t := Timer.new()
	t.wait_time = 4.0
	t.one_shot = true
	t.autostart = true
	t.timeout.connect(func() -> void: jet.emitting = false)
	root.add_child(t)
	return root
