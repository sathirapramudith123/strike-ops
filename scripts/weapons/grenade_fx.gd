class_name GrenadeFx
extends RefCounted
## Explosion effect for the HE grenade: a flash of light, a fireball, smoke,
## flying debris, the bang, and a camera shake for players close by. Built
## from CPU particles and primitive meshes (no textures), freed by itself.

const LIFETIME := 3.0

static var _dot: GradientTexture2D
static var _solid_dot: GradientTexture2D


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
	var me := _local_player(node.get_parent())
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
static func soft_quad(size: float, additive: bool, glow: float = 0.0, stretch: float = 1.0,
		solid: bool = false) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * stretch)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = soft_dot(solid)
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if glow > 0.0:
		mat.albedo_color = Color(glow, glow, glow)
	quad.material = mat
	return quad


## White round spot fading to transparent at the edge (built once). The
## `solid` one stays opaque further out (smoke clouds).
static func soft_dot(solid: bool = false) -> GradientTexture2D:
	var cached: GradientTexture2D = _solid_dot if solid else _dot
	if cached:
		return cached
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	if solid:
		g.add_point(0.6, Color(1, 1, 1, 0.95))
	else:
		g.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	if solid:
		_solid_dot = tex
	else:
		_dot = tex
	return tex


## The local player of the level `node` is in (or the current scene's).
static func _local_player(node: Node) -> PlayerController:
	var level := node as Level
	if level == null and node:
		level = node.get_tree().current_scene as Level
	return level.player if level else null


# --- Flashbang -----------------------------------------------------------------

## Beyond this a flash does nothing.
const FLASH_RANGE := 22.0
## Longest blindness (looking straight at a flash right next to you).
const FLASH_MAX_BLIND := 4.0
## The white screen stays full until this many seconds are left, then fades.
const FLASH_FADE := 1.5


## Bang + white burst at `pos`, then blinds the local player by how much of
## it they saw (each peer only works out its own player's blindness — it is
## a visual effect, not damage).
static func flash(parent: Node, pos: Vector3) -> Node3D:
	if NetworkManager.is_dedicated() or parent == null:
		return null
	var root := Node3D.new()
	root.name = "Flash"
	parent.add_child(root)
	root.global_position = pos + Vector3.UP * 0.1
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.97, 1.0)
	light.light_energy = 14.0
	light.omni_range = 14.0
	root.add_child(light)
	var sparks := _burst(14, 0.25, 0.5, 5.0, Color(1, 1, 1), 5.0, 2.0, true)
	root.add_child(sparks)
	var smoke := _burst(8, 1.4, 0.4, 1.2, Color(0.55, 0.55, 0.55, 0.45), 0.0, 3.0, false)
	smoke.gravity = Vector3(0, 0.4, 0)
	root.add_child(smoke)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	Audio.play_3d(&"flash_bang", pos, 2.0, 100.0, randf_range(0.97, 1.05), 10.0)
	var me := _local_player(parent)
	if me and not me.health.is_dead:
		var secs := blind_seconds(me.get_world_3d().direct_space_state, me.camera.global_position,
			-me.camera.global_basis.z, pos + Vector3.UP * 0.1)
		me.flash(secs)
	root.get_tree().create_timer(LIFETIME).timeout.connect(root.queue_free)
	return root


## How long (s) a flash at `pos` blinds someone whose eye is at `eye`
## looking along `forward`: nothing through walls or past FLASH_RANGE; less
## the further away and the more they look away (a flash behind you still
## dazzles a little).
static func blind_seconds(space: PhysicsDirectSpaceState3D, eye: Vector3, forward: Vector3, pos: Vector3) -> float:
	var to_flash := pos - eye
	var d := to_flash.length()
	if d > FLASH_RANGE:
		return 0.0
	if d > 0.3 and not Throwables.blast_reaches(space, pos, eye):
		return 0.0
	var facing := forward.normalized().dot(to_flash / maxf(d, 0.001)) if d > 0.3 else 1.0
	var look := 1.0
	if facing < 0.5:
		look = 0.2 if facing < -0.3 else remap(facing, -0.3, 0.5, 0.35, 1.0)
	var near := clampf(1.0 - pow(d / FLASH_RANGE, 1.5), 0.0, 1.0)
	var secs := FLASH_MAX_BLIND * look * near
	return secs if secs >= 0.25 else 0.0
