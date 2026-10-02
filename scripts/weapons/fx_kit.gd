class_name FxKit
extends RefCounted
## Shared pieces for the grenade effects (README → Grenade effects): soft
## noise textures made once in code (no image files) — a billowing smoke
## puff, a ragged flame tongue, a spark — and a configurable particle
## emitter. Everything is CPU particles on camera-facing quads; amounts
## follow Settings → Graphics → Particles.

static var _tex := {}


## A billowy smoke puff: fractal noise inside a soft round edge, lighter at
## the top (baked lighting), alpha = density. White — tinted per particle.
static func smoke_texture() -> ImageTexture:
	return _cached(&"smoke", func() -> Image: return _puff(128, 0.55, 3.0, true))


## A ragged flame / fireball blob: hotter (whiter) core, noisy edge.
static func fire_texture() -> ImageTexture:
	return _cached(&"fire", func() -> Image: return _puff(96, 0.8, 4.5, false))


## A spark: a small bright dot with a soft halo.
static func spark_texture() -> ImageTexture:
	return _cached(&"spark", func() -> Image:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = pow(a, 2.5)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		return img)


## A scorch mark: dark noisy disc fading out at the edge.
static func scorch_texture() -> ImageTexture:
	return _cached(&"scorch", func() -> Image:
		var n := 128
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.05
		noise.fractal_octaves = 4
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
				var edge := clampf((1.0 - d) * 2.2 + (v - 0.5) * 1.2, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.04, 0.035, 0.03, edge * 0.85))
		return img)


static func _cached(key: StringName, make: Callable) -> ImageTexture:
	if not _tex.has(key):
		var img: Image = make.call()
		img.generate_mipmaps()
		_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


## Noise inside a round falloff. `fill` = how far the dense part reaches,
## `rough` = how much the noise eats the edge; `shade` bakes a light top.
static func _puff(n: int, fill: float, rough: float, shade: bool) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = n
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 3.2 / n
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var d := p.length()
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((fill - d) * rough + (v - 0.5) * 2.0 * (0.4 + d), 0.0, 1.0)
			a = smoothstep(0.0, 1.0, a)
			var l := 1.0
			if shade:
				l = clampf(0.78 - p.y * 0.22 + (v - 0.5) * 0.35, 0.45, 1.0) # lit from above
			else:
				l = clampf(1.15 - d * 0.6 + (v - 0.5) * 0.3, 0.6, 1.0)
			img.set_pixel(x, y, Color(l, l, l, a))
	return img


## A camera-facing quad textured with `tex`. `additive` for light (fire,
## sparks); otherwise alpha blended. `glow` brightens unshaded additive ones.
static func quad(tex: Texture2D, size: float, additive: bool, glow: float = 1.0, stretch: float = 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * stretch)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(glow, glow, glow)
	q.material = mat
	return q


## How many particles for `n` at the current Particles setting (at least `lo`).
static func count(n: int, lo: int = 4) -> int:
	return maxi(lo, int(round(n * SettingsManager.graphics.particle_amount)))


## A particle emitter. `colors` = [[t, Color], …] over each particle's life,
## `sizes` = [[t, scale], …]. Spins its quads (random start angle and spin).
static func emitter(mesh: Mesh, amount: int, lifetime: float, one_shot: bool, colors: Array, sizes: Array,
		speed: Vector2, spread: float = 180.0, gravity := Vector3.ZERO, damping := 0.0,
		spin := 30.0, shape_radius := 0.2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.randomness = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = shape_radius
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = gravity
	p.damping_min = damping * 0.7
	p.damping_max = damping * 1.3
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -spin
	p.angular_velocity_max = spin
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.remove_point(1)
	ramp.set_offset(0, colors[0][0])
	ramp.set_color(0, colors[0][1])
	for i in range(1, colors.size()):
		ramp.add_point(colors[i][0], colors[i][1])
	p.color_ramp = ramp
	var curve := Curve.new()
	var top := 1.0
	for s: Array in sizes:
		top = maxf(top, float(s[1]))
	curve.max_value = top
	for s: Array in sizes:
		curve.add_point(Vector2(s[0], s[1]))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.25
	p.emitting = true
	return p


## A flat decal-like quad on the ground (scorch), fading out after `hold` s.
static func ground_mark(parent: Node3D, tex: Texture2D, size: float, hold: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.roughness = 1.0
	plane.material = mat
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = randf() * TAU
	mi.position.y = 0.012
	parent.add_child(mi)
	var t := mi.create_tween()
	t.tween_interval(hold)
	t.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	return mi
