class_name GlassPane
extends Node3D
## A pane of window glass (placed by tools/greybox.py: Map.pane). It blocks
## players and grenades but not the view; the first bullet cracks it round
## the hit, a second hit (or a knife, or a nearby HE / flash) shatters the
## whole pane into falling shards — then the window is an open hole you can
## shoot, throw and climb through.
##
## Server-authoritative like Door; late joiners get the state (NET_GROUP).

const GROUP := &"glass"
## Damage that shatters it at once (the knife, a sniper round).
const SHATTER_DAMAGE := 50.0
const THICKNESS := 0.03
const GLASS := Color(0.62, 0.78, 0.86, 0.28)

@export var width: float = 1.2
@export var height: float = 1.2

var broken: bool = false
var cracked: bool = false
var _body: StaticBody3D
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _cracks: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Door.NET_GROUP)
	_material = StandardMaterial3D.new()
	_material.albedo_color = GLASS
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 0.05
	_material.metallic_specular = 0.9
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta(&"breakable", self)
	add_child(_body)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, THICKNESS)
	_mesh.mesh = box
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, THICKNESS)
	shape.shape = bs
	_body.add_child(shape)
	_cracks = Node3D.new()
	_cracks.name = "Cracks"
	_body.add_child(_cracks)


## Server: a bullet or the knife hit the pane at `point`.
func server_hit(_body_node: Node, point: Vector3, damage: float) -> void:
	if not multiplayer.is_server() or broken:
		return
	var local := to_local(point)
	if cracked or damage >= SHATTER_DAMAGE:
		_shatter(Vector2(local.x, local.y))
		NetworkManager.send_to_ready(self, &"_client_shatter", [Vector2(local.x, local.y)])
	else:
		_crack(Vector2(local.x, local.y))
		NetworkManager.send_to_ready(self, &"_client_crack", [Vector2(local.x, local.y)])


## Server: an explosion (HE, flash) within `radius` shatters it.
func server_blast(pos: Vector3, radius: float, _damage: float) -> void:
	if not multiplayer.is_server() or broken or global_position.distance_to(pos) > radius:
		return
	var local := to_local(pos)
	_shatter(Vector2(local.x, local.y))
	NetworkManager.send_to_ready(self, &"_client_shatter", [Vector2(local.x, local.y)])


@rpc("authority", "call_remote", "reliable")
func _client_crack(at: Vector2) -> void:
	_crack(at)


@rpc("authority", "call_remote", "reliable")
func _client_shatter(at: Vector2) -> void:
	_shatter(at)


## A star of white crack lines round the hit.
func _crack(at: Vector2) -> void:
	cracked = true
	Audio.play_3d(&"glass_crack", to_global(Vector3(at.x, at.y, 0)), -6.0, 25.0, randf_range(0.9, 1.1), 3.0)
	if NetworkManager.is_dedicated():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.97, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var length := rng.randf_range(0.15, 0.45)
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length, 0.006, THICKNESS + 0.004)
		line.mesh = bm
		line.material_override = mat
		line.position = Vector3(at.x + cos(a) * length * 0.5, at.y + sin(a) * length * 0.5, 0)
		line.rotation.z = a
		_cracks.add_child(line)


func _shatter(at: Vector2) -> void:
	if broken:
		return
	broken = true
	_body.visible = false
	for c in _body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred(&"disabled", true)
	Audio.play_3d(&"glass_break", to_global(Vector3(at.x, at.y, 0)), -2.0, 40.0, randf_range(0.95, 1.08), 3.0)
	if NetworkManager.is_dedicated() or not is_inside_tree():
		return
	# Shards: small glassy flakes falling out of the frame.
	var p := CPUParticles3D.new()
	p.amount = clampi(int(width * height * 40.0), 16, 80)
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.5, height * 0.5, 0.02)
	p.direction = Vector3(0, 0, 1)
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.07, 0.1)
	var mat := _material.duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.8, 0.9, 0.95, 0.6)
	mesh.material = mat
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func send_state_to(peer_id: int) -> void:
	if is_inside_tree():
		_state.rpc_id(peer_id, broken, cracked)


@rpc("authority", "call_remote", "reliable")
func _state(is_broken: bool, is_cracked: bool) -> void:
	if is_cracked and not cracked:
		_crack(Vector2.ZERO)
	if is_broken and not broken:
		broken = true
		_body.visible = false
		for c in _body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
