class_name AmbientFx
extends Node3D
## Life in a ruined map (placed by tools/greybox.py: Map.ambient). Looks and
## sound only — no collision, nothing that hides a player — and each peer
## runs its own (they don't need to match). Dedicated servers skip them.
##
##   FLICKER_LAMP  a failing lamp: steady for a while, then a burst of
##                 flicker with a buzz, sometimes dark for a moment.
##   DRIP          water dripping from `height` above into a puddle: the
##                 drop falls, splashes, rings spread, a "plink".
##   SPARKS        a broken cable hanging from `height` above that shorts:
##                 a burst of sparks, a blue-white flash and a crackle.
##   RATS          `count` rats scurrying along the wall between here and
##                 `run_to`, stopping to sniff; they bolt to the far end,
##                 squeaking, when a player comes within FLEE_DISTANCE.
##
## Lamp and spark lights follow Settings → Graphics → Dynamic lights;
## spark particles follow Particles.

enum Kind { FLICKER_LAMP, DRIP, SPARKS, RATS }

const GROUP := &"ambient_fx"
const FLEE_DISTANCE := 4.5
## Small things (rats, drops, puddles) aren't drawn beyond this, and
## drips, sparks and rats don't update while the camera is further away.
const NEAR_DISTANCE := 30.0
const UPDATE_DISTANCE := 45.0

## One merged mesh shared by this node's rats (2 surfaces: fur, pink). Not
## static: a mesh held in a static variable makes Godot crash on exit.
var _rat_mesh_cache: ArrayMesh

@export var kind: Kind = Kind.FLICKER_LAMP
## Lamps and sparks: light energy, range and colour.
@export var energy: float = 1.0
@export var light_range: float = 10.0
@export var color: Color = Color(1.0, 0.92, 0.78)
## Drips and sparks: how far above this point the source is (m).
@export var height: float = 4.0
## Drips: puddle size (m, 0 = none).
@export var puddle: float = 1.2
## Rats: where they run to (world space) and how many.
@export var run_to: Vector3 = Vector3.ZERO
@export var count: int = 2

## Statistics for tests: drops that landed, spark bursts, flicker bursts.
var drops := 0
var bursts := 0
var light: OmniLight3D

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _state := 0
var _bulb_mat: StandardMaterial3D
var _base_energy := 1.0
# Drips
var _drop: MeshInstance3D
var _drop_v := 0.0
var _splash: CPUParticles3D
var _rings: Array[MeshInstance3D] = []
# Sparks
var _sparks: CPUParticles3D
var _flash := 0.0
var _tip_mat: StandardMaterial3D
# Rats
var _rats: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = hash(global_position)
	if NetworkManager.is_dedicated():
		set_process(false)
		return
	match kind:
		Kind.FLICKER_LAMP:
			_build_lamp()
		Kind.DRIP:
			_build_drip()
		Kind.SPARKS:
			_build_sparks()
		Kind.RATS:
			_build_rats()
	_timer = _rng.randf_range(0.5, 3.0)


func _process(delta: float) -> void:
	if light:
		light.visible = SettingsManager.graphics.dynamic_lights
	if kind != Kind.FLICKER_LAMP:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) > UPDATE_DISTANCE:
			return
	match kind:
		Kind.FLICKER_LAMP:
			_update_lamp(delta)
		Kind.DRIP:
			_update_drip(delta)
		Kind.SPARKS:
			_update_sparks(delta)
		Kind.RATS:
			_update_rats(delta)


# --- Flickering lamp ---------------------------------------------------------------

func _build_lamp() -> void:
	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	add_child(light)
	_base_energy = energy
	# A caged bulb under a small dented shade.
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = color
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = color
	_bulb_mat.emission_energy_multiplier = 3.0
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.2
	sphere.radial_segments = 10
	sphere.rings = 5
	bulb.mesh = sphere
	bulb.material_override = _bulb_mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)
	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 0.28
	cone.height = 0.16
	cone.radial_segments = 10
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.12)
	dark.metallic = 0.6
	dark.roughness = 0.6
	cone.material = dark
	shade.mesh = cone
	shade.position.y = 0.12
	add_child(shade)
	var wire := MeshInstance3D.new()
	var w := CylinderMesh.new()
	w.top_radius = 0.008
	w.bottom_radius = 0.008
	w.height = 0.8
	w.radial_segments = 4
	w.material = dark
	wire.mesh = w
	wire.position.y = 0.6
	add_child(wire)


## States: 0 steady, 1 flickering, 2 dark.
func _update_lamp(delta: float) -> void:
	_timer -= delta
	var level := 1.0
	match _state:
		0:
			level = 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.013)
			if _timer <= 0.0:
				_state = 1
				_timer = _rng.randf_range(0.3, 1.4)
				bursts += 1
				Audio.play_3d(&"lamp_buzz", global_position, -14.0, 14.0, _rng.randf_range(0.9, 1.1), 2.0)
		1:
			level = 1.0 if _rng.randf() < 0.45 else _rng.randf_range(0.0, 0.25)
			if _timer <= 0.0:
				if _rng.randf() < 0.35:
					_state = 2
					_timer = _rng.randf_range(0.2, 1.8)
				else:
					_state = 0
					_timer = _rng.randf_range(2.0, 7.0)
		2:
			level = 0.0
			if _timer <= 0.0:
				_state = 1
				_timer = _rng.randf_range(0.1, 0.5)
	if light:
		light.light_energy = _base_energy * level
	if _bulb_mat:
		_bulb_mat.emission_energy_multiplier = 0.05 + 3.0 * level


# --- Dripping water ----------------------------------------------------------------

func _water_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.62, 0.66, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if alpha < 0.5 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m


func _build_drip() -> void:
	if puddle > 0.0:
		var p := MeshInstance3D.new()
		var plane := CylinderMesh.new()
		plane.top_radius = puddle * 0.5
		plane.bottom_radius = puddle * 0.5
		plane.height = 0.004
		plane.radial_segments = 14
		plane.rings = 1
		p.scale = Vector3(1.0, 1.0, 0.7)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.045, 0.04, 0.035, 0.8)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.roughness = 0.12
		pm.metallic = 0.0
		pm.metallic_specular = 0.35
		plane.material = pm
		p.mesh = plane
		p.position.y = 0.006
		p.rotation.y = _rng.randf() * TAU
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_range_end = NEAR_DISTANCE
		add_child(p)
	_drop = MeshInstance3D.new()
	var d := SphereMesh.new()
	d.radius = 0.018
	d.height = 0.07
	d.radial_segments = 6
	d.rings = 3
	d.material = _water_material(0.85)
	_drop.mesh = d
	_drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drop.visible = false
	_drop.visibility_range_end = NEAR_DISTANCE
	add_child(_drop)
	_splash = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var sm := _water_material(0.7)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = sm
	_splash.mesh = q
	_splash.amount = 8
	_splash.lifetime = 0.35
	_splash.one_shot = true
	_splash.explosiveness = 1.0
	_splash.emitting = false
	_splash.direction = Vector3.UP
	_splash.spread = 50.0
	_splash.initial_velocity_min = 0.6
	_splash.initial_velocity_max = 1.3
	_splash.gravity = Vector3(0, -9.8, 0)
	_splash.position.y = 0.02
	_splash.local_coords = true
	add_child(_splash)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		torus.rings = 16
		torus.ring_segments = 4
		torus.material = _water_material(0.35)
		ring.mesh = torus
		ring.position.y = 0.01
		ring.scale = Vector3(0.05, 0.01, 0.05)
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_rings.append(ring)


func _update_drip(delta: float) -> void:
	if _drop == null:
		return
	if _drop.visible:
		_drop_v += 9.8 * delta
		_drop.position.y -= _drop_v * delta
		if _drop.position.y <= 0.02:
			_drop.visible = false
			_land_drop()
	else:
		_timer -= delta
		if _timer <= 0.0:
			_drop.position = Vector3(0, height, 0)
			_drop_v = 0.0
			_drop.visible = true
			_timer = _rng.randf_range(0.6, 2.2)
	for ring in _rings:
		if ring.visible:
			var s := ring.scale.x + delta * 0.5
			ring.scale = Vector3(s, 0.01, s)
			(ring.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = maxf(0.0, 0.35 - s * 1.2)
			if s > 0.3:
				ring.visible = false


func _land_drop() -> void:
	drops += 1
	_splash.restart()
	_splash.emitting = true
	for ring in _rings:
		if not ring.visible:
			ring.scale = Vector3(0.03, 0.01, 0.03)
			ring.visible = true
			break
	Audio.play_3d(&"drip", global_position, -16.0, 12.0, _rng.randf_range(0.85, 1.2), 1.5)


# --- Electrical short --------------------------------------------------------------

func _build_sparks() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.045)
	dark.roughness = 0.7
	# The cable hangs from the ceiling with a kink; its frayed copper end glows.
	var top := Vector3(0.0, height, 0.0)
	var kink := Vector3(0.25, height * 0.45, 0.1)
	var tip := Vector3(0.1, 0.0, 0.05)
	for seg: Array in [[top, kink], [kink, tip]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.018
		c.bottom_radius = 0.018
		c.height = a.distance_to(b)
		c.radial_segments = 5
		c.material = dark
		mi.mesh = c
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = (a + b) * 0.5
		mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	var end := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	s.radial_segments = 6
	s.rings = 3
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.albedo_color = Color(0.85, 0.5, 0.2)
	_tip_mat.emission_enabled = true
	_tip_mat.emission = Color(0.7, 0.85, 1.0)
	_tip_mat.emission_energy_multiplier = 0.0
	s.material = _tip_mat
	end.mesh = s
	end.position = tip
	add_child(end)
	_sparks = FxKit.emitter(FxKit.quad(FxKit.spark_texture(), 0.05, true, 2.5, 3.0), FxKit.count(26, 8), 0.7, true,
		[[0.0, Color(0.85, 0.92, 1.0, 1.0)], [0.4, Color(1.0, 0.75, 0.35, 1.0)], [1.0, Color(1.0, 0.4, 0.1, 0.0)]],
		[[0.0, 1.0], [1.0, 0.4]], Vector2(1.5, 4.0), 180.0, Vector3(0, -9.8, 0), 0.5, 0.0, 0.03)
	_sparks.emitting = false
	_sparks.position = tip
	add_child(_sparks)
	light = OmniLight3D.new()
	light.light_color = Color(0.7, 0.82, 1.0)
	light.light_energy = 0.0
	light.omni_range = light_range
	light.shadow_enabled = false
	light.position = tip
	add_child(light)


func _update_sparks(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		spark_burst()
		_timer = _rng.randf_range(1.5, 6.0) if _rng.randf() < 0.75 else _rng.randf_range(0.15, 0.4)
	_flash = maxf(0.0, _flash - delta * 6.0)
	if light:
		light.light_energy = energy * 3.0 * _flash
	if _tip_mat:
		_tip_mat.emission_energy_multiplier = 6.0 * _flash


func spark_burst() -> void:
	if _sparks == null:
		return
	bursts += 1
	_flash = 1.0
	_sparks.restart()
	_sparks.emitting = true
	Audio.play_3d(&"spark", global_position + Vector3.UP * 0.2, -8.0, 22.0, _rng.randf_range(0.9, 1.15), 3.0)


# --- Rats ------------------------------------------------------------------------------

## One rat (a MeshInstance3D sharing the merged rat mesh).
func _rat_mesh() -> Node3D:
	if _rat_mesh_cache == null:
		_rat_mesh_cache = _merge_rat(_rat_parts())
	var mi := MeshInstance3D.new()
	mi.mesh = _rat_mesh_cache
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = NEAR_DISTANCE
	return mi


## Merges the part meshes into one ArrayMesh, one surface per material.
static func _merge_rat(root: Node3D) -> ArrayMesh:
	var tools := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var mat := mi.mesh.surface_get_material(0)
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		var xf := root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() else _local_xf(root, mi)
		(tools[mat] as SurfaceTool).append_from(mi.mesh, 0, xf)
	var out := ArrayMesh.new()
	for mat in tools:
		(tools[mat] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	root.free()
	return out


static func _local_xf(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _rat_parts() -> Node3D:
	var root := Node3D.new()
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.22, 0.18, 0.15)
	fur.roughness = 0.95
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(0.6, 0.42, 0.4)
	pink.roughness = 0.8
	var body := MeshInstance3D.new()
	var b := SphereMesh.new()
	b.radius = 0.05
	b.height = 0.1
	b.radial_segments = 8
	b.rings = 4
	b.material = fur
	body.mesh = b
	body.scale = Vector3(0.75, 0.7, 1.6)
	body.position = Vector3(0, 0.045, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var h := CylinderMesh.new()
	h.top_radius = 0.004
	h.bottom_radius = 0.032
	h.height = 0.075
	h.radial_segments = 6
	h.material = fur
	head.mesh = h
	head.rotation.x = -PI / 2
	head.position = Vector3(0, 0.045, -0.105)
	root.add_child(head)
	for side: float in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.012
		e.height = 0.024
		e.radial_segments = 5
		e.rings = 2
		e.material = pink
		ear.mesh = e
		ear.position = Vector3(side * 0.022, 0.075, -0.085)
		root.add_child(ear)
	var tail := MeshInstance3D.new()
	var t := CylinderMesh.new()
	t.top_radius = 0.006
	t.bottom_radius = 0.002
	t.height = 0.16
	t.radial_segments = 4
	t.material = pink
	tail.mesh = t
	tail.rotation.x = PI / 2 - 0.25
	tail.position = Vector3(0, 0.03, 0.15)
	root.add_child(tail)
	return root


func _build_rats() -> void:
	var a := global_position
	for i in count:
		var rat := _rat_mesh()
		add_child(rat)
		var t := _rng.randf()
		_rats.append({ "node": rat, "t": t, "dir": 1.0 if _rng.randf() < 0.5 else -1.0,
			"speed": 0.0, "wait": _rng.randf_range(0.0, 2.0), "flee": false })
		rat.global_position = a.lerp(run_to, t)


## Each rat: runs a stretch, stops and sniffs, turns back at the ends; a
## player close by makes it bolt (fast, squeaking) to the far end.
func _update_rats(delta: float) -> void:
	var a := global_position
	var length := maxf(a.distance_to(run_to), 0.5)
	var players := get_tree().get_nodes_in_group(&"player")
	for r: Dictionary in _rats:
		var node: Node3D = r.node
		var near := false
		for p in players:
			if (p as Node3D).global_position.distance_to(node.global_position) < FLEE_DISTANCE:
				near = true
				if not r.flee:
					r.flee = true
					r.wait = 0.0
					# Away from the player.
					var to_run := (run_to - a).normalized()
					r.dir = 1.0 if (node.global_position - (p as Node3D).global_position).dot(to_run) >= 0.0 else -1.0
					if _rng.randf() < 0.6:
						Audio.play_3d(&"rat_squeak", node.global_position, -10.0, 15.0, _rng.randf_range(0.9, 1.3), 1.5)
				break
		if not near and r.flee and r.wait <= 0.0:
			r.flee = false
		if r.wait > 0.0 and not r.flee:
			r.wait -= delta
			# Sniffing: little twitches on the spot.
			node.rotation.y += sin(Time.get_ticks_msec() * 0.02 + r.t * 10.0) * delta * 2.0
			continue
		var speed: float = 4.5 if r.flee else 1.6
		r.t = clampf(r.t + r.dir * speed * delta / length, 0.0, 1.0)
		var pos := a.lerp(run_to, r.t)
		pos.y = a.y + abs(sin(Time.get_ticks_msec() * 0.04 + r.t * 30.0)) * 0.012
		node.global_position = pos
		var ahead: Vector3 = (run_to - a).normalized() * float(r.dir)
		if ahead.length() > 0.01:
			node.look_at(node.global_position + ahead, Vector3.UP)
		if r.t <= 0.0 or r.t >= 1.0:
			r.dir = -r.dir
			r.wait = _rng.randf_range(1.0, 4.0)
			r.flee = false
		elif not r.flee and _rng.randf() < delta * 0.4:
			r.wait = _rng.randf_range(0.5, 2.5)
			if _rng.randf() < 0.3:
				r.dir = -r.dir
		if r.flee and _rng.randf() < delta * 1.5:
			Audio.play_3d(&"rat_scurry", node.global_position, -16.0, 10.0, _rng.randf_range(0.9, 1.2), 1.0)


## Rats currently bolting from a player (for tests).
func fleeing() -> int:
	var n := 0
	for r: Dictionary in _rats:
		if r.flee:
			n += 1
	return n


func rat_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r: Dictionary in _rats:
		out.append((r.node as Node3D).global_position)
	return out
