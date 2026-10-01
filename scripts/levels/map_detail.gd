class_name MapDetail
extends Node3D
## A map's extra detail layer (GraphicsPreset.map_detail, on by default):
## assets/maps/<map>/<map>_detail.tscn with this script on the root. The
## Level adds it when the option is on and frees it (restore()) when it is
## turned off. Children are looks only — the skyline outside the walls,
## props flat on walls or on existing cover — never collision, and never
## anything that hides a player (players with it off must see the same).
##
## Besides its children it can swap the sky for a panorama photo, tint the
## sun and add chimney smoke (cheap CPU particles, scaled by the Particles
## setting).

## Panorama sky (equirectangular, LDR is fine). Null keeps the map's sky.
@export var sky_texture: Texture2D
@export var sky_energy: float = 1.0
## Where the sun is in the panorama: horizontal position 0..1 across the
## image. The sky is turned so it lines up with the map's sun.
@export_range(0.0, 1.0) var sky_sun_u: float = 0.5
@export var sun_color: Color = Color(0, 0, 0, 0)
@export var sun_energy: float = -1.0
## Distance fog with the far scenery (negative density keeps the map's).
@export var fog_density: float = -1.0
@export var fog_color: Color = Color(0, 0, 0, 0)
## Chimney tops (world space) that smoke.
@export var smoke_points: PackedVector3Array = []
@export var smoke_color: Color = Color(0.2, 0.2, 0.21, 0.9)

## What StaticBatcher did with the detail meshes.
var batch_stats: Dictionary = {}

var _env: Environment
var _sun: DirectionalLight3D
var _saved := {}


func apply(level: Level) -> void:
	_env = level.world_environment.environment if level.world_environment else null
	_sun = level.sun
	if _env and _env.sky and sky_texture:
		var sky := PanoramaSkyMaterial.new()
		sky.panorama = sky_texture
		sky.energy_multiplier = sky_energy
		_saved.sky_material = _env.sky.sky_material
		_saved.sky_rotation = _env.sky_rotation
		_env.sky.sky_material = sky
		if _sun:
			# Godot's panorama: u = atan2(x, -z) / TAU + 0.5 for a direction.
			var to_sun := _sun.global_basis.z
			var want := atan2(to_sun.x, -to_sun.z)
			var have := (sky_sun_u - 0.5) * TAU
			_env.sky_rotation = Vector3(0, want - have, 0)
	if _env and fog_density >= 0.0:
		_saved.fog_density = _env.fog_density
		_env.fog_density = fog_density
	if _env and fog_color.a > 0.0:
		_saved.fog_light_color = _env.fog_light_color
		_env.fog_light_color = fog_color
	if _sun and sun_color.a > 0.0:
		_saved.sun_color = _sun.light_color
		_sun.light_color = sun_color
	if _sun and sun_energy >= 0.0:
		_saved.sun_energy = _sun.light_energy
		_sun.light_energy = sun_energy
	# Props near the play area (pipes, gutters, trusses …) are exported
	# without textures and wear the art's material of the same name, so
	# they share its textures; then everything is merged like the greybox
	# (StaticBatcher: small props fade out with the Draw distance setting).
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m and level.art_materials.has(m.resource_name):
				mi.set_surface_override_material(s, level.art_materials[m.resource_name])
	if not Level.batching_disabled:
		batch_stats = StaticBatcher.batch(self, SettingsManager.graphics.draw_distance_scale)
	# Far scenery: no shadows (it is outside the shadow distance anyway).
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var m := mi.get_active_material(0)
		if mi.name.begins_with("Far_") or (m and m.resource_name.begins_with("Far_")):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for p in smoke_points:
		add_child(_smoke(p))


## Puts the map's own sky and sun back.
func restore() -> void:
	if _env and _saved.has("sky_material"):
		_env.sky.sky_material = _saved.sky_material
		_env.sky_rotation = _saved.sky_rotation
	if _env and _saved.has("fog_density"):
		_env.fog_density = _saved.fog_density
	if _env and _saved.has("fog_light_color"):
		_env.fog_light_color = _saved.fog_light_color
	if _sun and _saved.has("sun_color"):
		_sun.light_color = _saved.sun_color
	if _sun and _saved.has("sun_energy"):
		_sun.light_energy = _saved.sun_energy
	_saved.clear()


func _smoke(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.position = at
	p.amount = maxi(6, int(40 * SettingsManager.graphics.particle_amount))
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.9, 0.15, 0.3) # a light breeze
	p.scale_amount_min = 3.0
	p.scale_amount_max = 4.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(smoke_color, 0.0))
	fade.set_color(1, Color(smoke_color, 0.0))
	fade.add_point(0.04, smoke_color)
	fade.add_point(0.6, Color(smoke_color.lightened(0.25), smoke_color.a * 0.6))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 6)
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	puff.width = 64
	puff.height = 64
	var g := Gradient.new() # a soft puff with a solid middle
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.8))
	puff.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
