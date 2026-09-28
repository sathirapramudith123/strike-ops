extends SceneTree
## Finds "sometimes jumpable" ledges on the maps: ledges between
## Climb.BORDERLINE_LOW and Climb.BORDERLINE_HIGH that are not climbable
## (whether a jump gets you up there depends on the run-up). Maps should have
## none — make such props climbable, lower or taller. Ramps (sloped tops) and
## spots only reachable from out-of-bounds roofs (ceilings, backdrop
## buildings) are skipped.
##
##   godot --headless --path . --script res://tools/ledge_check.gd [map_id …]

const SPACING := 1.0
const DIRS := 8

static var _floor_names := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = GameConfig.MAPS.map(func(m: Dictionary) -> String: return m.id)
	var total := 0
	for id: String in ids:
		var level := (load(GameConfig.map_path(id)) as PackedScene).instantiate() as Level
		level.preview_only = true
		root.add_child(level)
		await physics_frame
		await physics_frame
		var found := scan(level)
		total += found.size()
		print("%s: %d borderline ledge(s)" % [id, found.size()])
		for f: String in found.slice(0, 40):
			print("   ", f)
		level.queue_free()
		await process_frame
	print("TOTAL %d" % total)
	quit(1 if total > 0 else 0)


## "name @ position (height)" for every borderline, non-climbable ledge.
static func scan(level: Node3D) -> PackedStringArray:
	var space := level.get_world_3d().direct_space_state
	var bounds := AABB()
	var first := true
	for body in level.get_node("Geometry").get_children():
		var shape_node := body.get_node_or_null("Collision") as CollisionShape3D
		if shape_node == null:
			continue
		var box := (body as Node3D).global_transform * shape_node.shape.get_debug_mesh().get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var seen := {}
	var out := PackedStringArray()
	var x := bounds.position.x
	while x <= bounds.end.x:
		var z := bounds.position.z
		while z <= bounds.end.z:
			for feet in _floors(space, Vector3(x, bounds.end.y + 1.0, z), bounds.position.y - 1.0):
				for i in DIRS:
					var a := TAU * i / DIRS
					var ledge := Climb.find_ledge(space, feet, Vector3(sin(a), 0, cos(a)))
					if ledge.is_empty() or ledge.climbable or ledge.normal.y < 0.98:
						continue
					var h: float = ledge.height
					if h > Climb.BORDERLINE_LOW and h < Climb.BORDERLINE_HIGH:
						var body := ledge.collider as Node
						var key: String = body.name if body else "?"
						if not seen.has(key):
							seen[key] = true
							out.append("%s @ %s (%.2f m) from %s on %s" % [key, (ledge.top as Vector3).snappedf(0.1), h, feet.snappedf(0.1), _floor_names.get(feet, "?")])
			z += SPACING
		x += SPACING
	return out


static func _out_of_bounds(body_name: String) -> bool:
	return body_name.begins_with("Ceiling") or body_name.begins_with("Building")


## Every surface under the column at `top` a player can stand on.
static func _floors(space: PhysicsDirectSpaceState3D, top: Vector3, bottom_y: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var from := top
	for n in 6:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, bottom_y, from.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var p: Vector3 = hit.position
		var on: String = (hit.collider as Node).name if hit.collider is Node else ""
		if hit.normal.y > 0.7 and not _out_of_bounds(on) and Climb.has_room(space, p):
			result.append(p)
			_floor_names[p] = on
		# The next ray starts inside the solid under this surface, which
		# rays ignore, so it finds the next floor below.
		from = p - Vector3.UP * 0.05
	return result
