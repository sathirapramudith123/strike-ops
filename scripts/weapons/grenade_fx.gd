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
	var smoke_tex := FxKit.smoke_texture()
	var fire_tex := FxKit.fire_texture()
	# Flash of light.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.32)
	light.light_energy = 12.0
	light.omni_range = 12.0
	light.position.y = 0.6
	root.add_child(light)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Core flash: one big white-hot sprite for a few frames.
	root.add_child(FxKit.emitter(FxKit.quad(fire_tex, 2.6, true, 1.4), 3, 0.14, true,
		[[0.0, Color(1, 0.95, 0.8, 1)], [1.0, Color(1, 0.6, 0.2, 0)]], [[0.0, 0.6], [1.0, 1.6]],
		Vector2(0, 0.3), 180.0, Vector3.ZERO, 0.0, 0.0, 0.05))
	# Fireball: ragged orange billows that swell and darken.
	root.add_child(FxKit.emitter(FxKit.quad(fire_tex, 2.0, true, 1.0), FxKit.count(28, 10), 0.7, true,
		[[0.0, Color(1, 0.8, 0.4, 1)], [0.25, Color(1, 0.42, 0.06, 0.95)], [0.6, Color(0.7, 0.15, 0.02, 0.6)],
			[1.0, Color(0.2, 0.04, 0.01, 0)]],
		[[0.0, 0.4], [0.4, 1.5], [1.0, 2.0]], Vector2(3.0, 7.0), 180.0, Vector3(0, 1.5, 0), 7.0, 90.0, 0.3))
	# Sparks / burning fragments flung out, falling.
	root.add_child(FxKit.emitter(FxKit.quad(FxKit.spark_texture(), 0.07, true, 3.0), FxKit.count(40, 10), 1.1, true,
		[[0.0, Color(1, 0.9, 0.55, 1)], [0.6, Color(1, 0.5, 0.15, 1)], [1.0, Color(0.6, 0.15, 0.03, 0)]],
		[[0.0, 1.0], [1.0, 0.6]], Vector2(6.0, 15.0), 85.0, Vector3(0, -11.0, 0), 1.5, 0.0, 0.2))
	# Dark smoke: rises and spreads, lingers.
	var smoke := FxKit.emitter(FxKit.quad(smoke_tex, 2.2, false), FxKit.count(30, 10), 4.5, true,
		[[0.0, Color(0.18, 0.16, 0.14, 0)], [0.08, Color(0.22, 0.2, 0.18, 0.85)], [0.6, Color(0.33, 0.32, 0.3, 0.55)],
			[1.0, Color(0.45, 0.44, 0.42, 0)]],
		[[0.0, 0.5], [0.3, 1.5], [1.0, 2.6]], Vector2(1.5, 4.0), 70.0, Vector3(0, 0.9, 0), 3.0, 25.0, 0.4)
	smoke.position.y = 0.3
	root.add_child(smoke)
	# Dust kicked along the ground by the blast wave.
	var dust := FxKit.emitter(FxKit.quad(smoke_tex, 1.0, false), FxKit.count(18, 6), 1.8, true,
		[[0.0, Color(0.5, 0.45, 0.38, 0.7)], [1.0, Color(0.55, 0.5, 0.44, 0)]],
		[[0.0, 0.6], [1.0, 2.0]], Vector2(5.0, 9.0), 12.0, Vector3.ZERO, 5.0, 20.0, 0.3)
	dust.direction = Vector3(1, 0, 0)
	dust.spread = 180.0
	dust.flatness = 1.0
	dust.position.y = -0.05
	root.add_child(dust)
	# Debris: small dark chips (lit, spinning) thrown out.
	var chips := BoxMesh.new()
	chips.size = Vector3(0.05, 0.03, 0.04)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.13, 0.12, 0.1)
	cm.vertex_color_use_as_albedo = false
	chips.material = cm
	var debris := FxKit.emitter(chips, FxKit.count(16, 6), 1.4, true, [[0.0, Color.WHITE], [1.0, Color.WHITE]],
		[[0.0, 1.0], [1.0, 1.0]], Vector2(5.0, 11.0), 70.0, Vector3(0, -14.0, 0), 0.5, 720.0, 0.15)
	debris.particle_flag_rotate_y = true
	root.add_child(debris)
	# A scorch mark left on the floor.
	var mark_root := Node3D.new()
	parent.add_child(mark_root)
	mark_root.global_position = pos
	FxKit.ground_mark(mark_root, FxKit.scorch_texture(), 3.2, 18.0)
	mark_root.get_tree().create_timer(22.0).timeout.connect(mark_root.queue_free)
	Audio.play_3d(&"explosion", pos, 2.0, 140.0, randf_range(0.95, 1.08), 12.0)
	_shake_nearby(root, pos)
	root.get_tree().create_timer(LIFETIME + 1.5).timeout.connect(root.queue_free)
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
	light.light_energy = 18.0
	light.omni_range = 16.0
	root.add_child(light)
	# Blinding white core, a ring of white-hot sparks, a puff of grey smoke.
	root.add_child(FxKit.emitter(FxKit.quad(FxKit.fire_texture(), 1.8, true, 4.0), 3, 0.15, true,
		[[0.0, Color(1, 1, 1, 1)], [1.0, Color(0.85, 0.9, 1, 0)]], [[0.0, 0.5], [1.0, 1.8]],
		Vector2(0, 0.2), 180.0, Vector3.ZERO, 0.0, 0.0, 0.05))
	root.add_child(FxKit.emitter(FxKit.quad(FxKit.spark_texture(), 0.06, true, 3.5), FxKit.count(30, 8), 0.5, true,
		[[0.0, Color(1, 1, 1, 1)], [1.0, Color(0.8, 0.85, 1, 0)]], [[0.0, 1.0], [1.0, 0.5]],
		Vector2(5.0, 10.0), 180.0, Vector3(0, -6.0, 0), 2.0, 0.0, 0.05))
	var smoke := FxKit.emitter(FxKit.quad(FxKit.smoke_texture(), 0.8, false), FxKit.count(10, 4), 2.2, true,
		[[0.0, Color(0.7, 0.7, 0.72, 0)], [0.1, Color(0.7, 0.7, 0.72, 0.6)], [1.0, Color(0.75, 0.75, 0.77, 0)]],
		[[0.0, 0.5], [1.0, 2.2]], Vector2(0.5, 1.5), 180.0, Vector3(0, 0.4, 0), 1.5, 20.0, 0.1)
	root.add_child(smoke)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
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
