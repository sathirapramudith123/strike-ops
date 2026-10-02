class_name StaticBatcher
extends RefCounted
## Load-time optimisation for level geometry (Phase 7).
##
## Greybox maps are made of many small boxes — one draw call each (plus one
## per shadow pass). This merges every MeshInstance3D under the level's
## "Geometry" node into a few big meshes:
##   • grouped by material (one draw call per material) and by 16 m grid cell
##     (so frustum culling still skips what the camera can't see);
##   • small props go into separate "detail" batches with a visibility range
##     tied to the Draw distance setting;
##   • large solid boxes also get an occluder, so geometry hidden behind walls
##     is culled before it is drawn.
## Collision shapes are untouched. The world-space grid shader makes merged
## geometry look identical.

const CELL_SIZE := 16.0
## Props smaller than this (m³) are "detail": culled beyond DETAIL_DISTANCE.
const DETAIL_VOLUME := 4.0
const DETAIL_DISTANCE := 60.0
## Boxes at least this thick in every direction become occluders.
const OCCLUDER_MIN_SIZE := 0.9
const OCCLUDER_MIN_VOLUME := 6.0


## Merges the meshes under `root`. Returns stats and the detail batches
## (whose visibility range the level updates when Draw distance changes).
static func batch(root: Node3D, draw_distance_scale: float = 1.0) -> Dictionary:
	var groups := {} # key -> { material, tool, detail }
	var sources: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible or mi.mesh.get_surface_count() == 0:
			continue
		var aabb := mi.global_transform * mi.mesh.get_aabb()
		var size := aabb.size
		var detail := size.x * size.y * size.z < DETAIL_VOLUME
		var center := aabb.get_center()
		# Each surface joins the batch of its material (a prop with a
		# painted body and steel doors goes into two).
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface)
			var key := "%d_%d_%d_%d" % [mat.get_instance_id() if mat else 0, floori(center.x / CELL_SIZE),
				floori(center.z / CELL_SIZE), int(detail)]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = { "material": mat, "tool": st, "detail": detail, "count": 0 }
			var g: Dictionary = groups[key]
			(g.tool as SurfaceTool).append_from(mi.mesh, surface, mi.global_transform)
			g.count += 1
		sources.append(mi)
		add_occluder(root, mi)

	var batches := Node3D.new()
	batches.name = "Batches"
	root.add_child(batches)
	var details: Array[MeshInstance3D] = []
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mesh := (g.tool as SurfaceTool).commit()
		if g.material:
			mesh.surface_set_material(0, g.material)
		var out := MeshInstance3D.new()
		out.name = "Batch_%s" % key
		out.mesh = mesh
		batches.add_child(out)
		if g.detail:
			out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			details.append(out)
	set_detail_distance(details, draw_distance_scale)

	# The originals are no longer drawn — free them (fewer nodes too).
	for mi in sources:
		mi.queue_free()
	return {
		"source_meshes": sources.size(),
		"batches": groups.size(),
		"details": details,
		"occluders": root.find_children("*", "OccluderInstance3D", true, false).size(),
	}


static func set_detail_distance(details: Array[MeshInstance3D], draw_distance_scale: float) -> void:
	for d in details:
		d.visibility_range_end = DETAIL_DISTANCE * draw_distance_scale
		d.visibility_range_end_margin = 4.0
		d.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## An occluder for a big solid greybox box (walls, buildings), else nothing.
static func add_occluder(root: Node3D, mi: MeshInstance3D) -> void:
	var box := mi.mesh as BoxMesh
	if box == null:
		return
	var s := box.size * mi.global_transform.basis.get_scale()
	if minf(s.x, minf(s.y, s.z)) < OCCLUDER_MIN_SIZE or s.x * s.y * s.z < OCCLUDER_MIN_VOLUME:
		return
	var occ := OccluderInstance3D.new()
	var shape := BoxOccluder3D.new()
	shape.size = box.size
	occ.occluder = shape
	root.add_child(occ)
	occ.global_transform = mi.global_transform
