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


## A real-looking smoke screen: wispy puffs (four shapes in an atlas, each
## a different grey) pour out of the canister over the first seconds — a
## heavy layer rolling out along the ground, a billowing body above it —
## then hang, drift a little with the air and thin out at the end. Torn
## wisps keep curling off the edges, and a jet hisses out of the canister
## for the first seconds. Puffs fade softly into the floor and walls
## (FxKit.quad `soft`). Each puff lives the cloud's whole life so it doesn't
## flicker, and it keeps enough of them on every Particles setting to stay
## opaque (it blocks sight for everyone).
func _build_cloud() -> Node3D:
	var root := Node3D.new()
	root.name = "Cloud"
	var tex := FxKit.smoke_atlas()
	# Puffs come out over the first ~3 s (explosiveness); the last one is gone
	# about a second after DURATION.
	var explosive := 0.85
	var life := (DURATION + 1.0) / (2.0 - explosive)
	var solid := 1.2 / life
	var fade := [[0.0, Color(1, 1, 1, 0.0)], [solid, Color(1, 1, 1, 1.0)], [0.82, Color(1, 1, 1, 0.92)], [1.0, Color(1, 1, 1, 0.0)]]
	var layers := [
		# [name, size, count, min, speed, spread, gravity, damping, height]
		["Ground", 3.4, 44, 28, Vector2(2.2, 4.4), 85.0, Vector3(0, -0.15, 0), 1.6, 0.35],
		["Body", 2.9, 72, 44, Vector2(1.2, 3.2), 60.0, Vector3.ZERO, 1.6, 0.9],
	]
	for l: Array in layers:
		var p := FxKit.emitter(FxKit.quad(tex, l[1], false, 1.0, 1.0, 2, 0.8), maxi(l[3], FxKit.count(l[2])), life, true,
			fade, [[0.0, 0.4], [0.06, 1.2], [1.0, 1.8]], l[4], l[5], l[6], l[7], 8.0, 0.25)
		p.name = l[0]
		p.explosiveness = explosive
		p.position.y = l[8]
		FxKit.pick_frame(p)
		FxKit.shade_range(p, Color(0.52, 0.53, 0.55), Color(0.72, 0.72, 0.73))
		root.add_child(p)
	# Torn wisps curling off the edges and drifting with the air.
	var wisps := FxKit.emitter(FxKit.quad(tex, 2.0, false, 1.0, 1.0, 2, 0.6), FxKit.count(24, 8), 5.0, false,
		[[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.4)], [1.0, Color(1, 1, 1, 0.0)]],
		[[0.0, 0.6], [1.0, 1.6]], Vector2(0.2, 0.6), 70.0, Vector3(0.22, 0.1, 0.12), 0.2, 12.0, RADIUS * 0.8)
	wisps.name = "Wisps"
	wisps.position.y = 1.3
	FxKit.pick_frame(wisps)
	FxKit.shade_range(wisps, Color(0.6, 0.6, 0.62), Color(0.76, 0.76, 0.77))
	root.add_child(wisps)
	# The hissing jet from the canister.
	var jet := FxKit.emitter(FxKit.quad(tex, 0.6, false, 1.0, 1.0, 2, 0.2), FxKit.count(24, 8), 1.4, false,
		[[0.0, Color(0.78, 0.78, 0.8, 0.0)], [0.15, Color(0.78, 0.78, 0.8, 0.8)], [1.0, Color(0.68, 0.68, 0.7, 0.0)]],
		[[0.0, 0.4], [1.0, 2.5]], Vector2(3.0, 5.0), 25.0, Vector3(0, 0.5, 0), 2.0, 40.0, 0.05)
	jet.name = "Jet"
	jet.position.y = 0.1
	FxKit.pick_frame(jet)
	root.add_child(jet)
	var t := Timer.new()
	t.wait_time = 4.0
	t.one_shot = true
	t.autostart = true
	t.timeout.connect(func() -> void: jet.emitting = false)
	root.add_child(t)
	var t2 := Timer.new()
	t2.wait_time = DURATION - 4.0
	t2.one_shot = true
	t2.autostart = true
	t2.timeout.connect(func() -> void: wisps.emitting = false)
	root.add_child(t2)
	return root
