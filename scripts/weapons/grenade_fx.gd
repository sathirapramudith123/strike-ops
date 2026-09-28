class_name GrenadeFx
extends RefCounted
## Explosion effect for the HE grenade: a flash of light, a fireball, smoke,
## flying debris, the bang, and a camera shake for players close by. Built
## from CPU particles and primitive meshes (no textures), freed by itself.

const LIFETIME := 3.0

static var _dot: GradientTexture2D


static func explosion(parent: Node, pos: Vector3) -> Node3D:
	if NetworkManager.is_dedicated() or parent == null:
		return null
	var root := Node3D.new()
	root.name = "Explosion"
	parent.add_child(root)
	root.global_position = pos + Vector3.UP * 0.1
	# Flash.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 8.0
	light.omni_range = 9.0
	root.add_child(light)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	# Fireball: bright, fast, short.
	root.add_child(_burst(26, 0.4, 0.7, 6.0, Color(1.0, 0.65, 0.2), 4.0, 2.5, true))
	# Smoke: grey, slow, rising.
	var smoke := _burst(20, 2.4, 0.9, 2.2, Color(0.28, 0.27, 0.25, 0.75), 0.0, 3.0, false)
	(smoke as CPUParticles3D).gravity = Vector3(0, 0.6, 0)
	root.add_child(smoke)
	# Debris: small dark chips thrown out and falling.
	var debris := _burst(16, 1.0, 0.05, 9.0, Color(0.15, 0.13, 0.1), 0.0, 1.0, false)
	(debris as CPUParticles3D).gravity = Vector3(0, -12, 0)
	root.add_child(debris)
	Audio.play_3d(&"explosion", pos, 2.0, 140.0, randf_range(0.95, 1.08), 12.0)
	_shake_nearby(root, pos)
	root.get_tree().create_timer(LIFETIME).timeout.connect(root.queue_free)
	return root


## Rumble for a local controller player and a short view punch near the blast.
static func _shake_nearby(node: Node, pos: Vector3) -> void:
	var level := node.get_tree().current_scene as Level
	var me: PlayerController = level.player if level else null
	if me == null or me.health.is_dead:
		return
	var d := me.global_position.distance_to(pos)
	if d > Throwables.HE_RADIUS * 3.0:
		return
	var k := 1.0 - d / (Throwables.HE_RADIUS * 3.0)
	me.add_recoil(randf_range(1.0, 2.5) * k, randf_range(-1.5, 1.5) * k)
	GamepadInput.rumble(0.8 * k, 0.6 * k, 0.35)


## One-shot particle burst of `amount` soft spots (`size` m across at birth,
## `end_scale` times that when they fade out).
static func _burst(amount: int, lifetime: float, size: float, speed: float, color: Color,
		emission: float, end_scale: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.2
	p.gravity = Vector3.ZERO
	var mesh := soft_quad(size, additive, emission)
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.max_value = maxf(end_scale, 1.0)
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, end_scale))
	p.scale_amount_curve = curve
	p.emitting = true
	return p


## A camera-facing quad with a soft round spot on it (particles). `glow` > 0
## makes it unshaded and that much brighter.
static func soft_quad(size: float, additive: bool, glow: float = 0.0, stretch: float = 1.0) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * stretch)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = soft_dot()
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if glow > 0.0:
		mat.albedo_color = Color(glow, glow, glow)
	quad.material = mat
	return quad


## White round spot fading to transparent at the edge (built once).
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 64
		_dot.height = 64
	return _dot
