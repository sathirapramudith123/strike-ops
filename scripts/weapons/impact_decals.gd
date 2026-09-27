class_name ImpactDecals
extends MultiMeshInstance3D
## Bullet-hole decals for a whole level in ONE node and ONE draw call.
##
## A MultiMesh ring buffer: each impact overwrites the oldest instance.
## (Before Phase 7 every weapon owned 32 MeshInstance3D nodes — ~160 nodes
## per player.)

const MAX_DECALS := 256
const GROUP := &"impact_decals"

var _next: int = 0


func _init() -> void:
	name = "ImpactDecals"
	add_to_group(GROUP)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = MAX_DECALS
	multimesh.visible_instance_count = 0
	# Decals are spread over the whole map: skip per-frame culling math.
	custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 400, 2000))


## The level's decal node (created on first use).
static func get_for(node: Node) -> ImpactDecals:
	var existing := node.get_tree().get_first_node_in_group(GROUP) as ImpactDecals
	if existing:
		return existing
	var decals := ImpactDecals.new()
	var parent := node.get_tree().current_scene if node.get_tree().current_scene else node.get_tree().root
	parent.add_child(decals)
	return decals


func add(pos: Vector3, normal: Vector3) -> void:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	multimesh.set_instance_transform(_next, Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.005))
	_next = (_next + 1) % MAX_DECALS
	multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, MAX_DECALS)


## Removes every decal (used after the shader warm-up).
func clear() -> void:
	multimesh.visible_instance_count = 0
	_next = 0
