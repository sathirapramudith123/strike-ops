extends SceneTree
## Exports each map's geometry as a glTF file (.glb) to open in Blender as the
## base for real art: every mesh at its place, named after its node in the
## map (Sand1, Wall12 …), with a plain material per surface kind in the map's
## colours (Mat_wood, Mat_metal …). Spawns and bomb sites come along as empties
## (SPAWN_Blue1, SITE_A …) so you can see where the gameplay happens.
## Build the new art over the blockout without moving walls that matter for
## the layout, then export it back as .glb (see README → Real 3D art).
##
##   godot --headless --path . --script res://tools/export_blockout.gd [map_id …]
##
## Files go to assets/blockouts/<map_id>.glb.

const OUT_DIR := "res://assets/blockouts"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = GameConfig.MAPS.map(func(m: Dictionary) -> String: return m.id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := 0
	for id: String in ids:
		var level := (load(GameConfig.map_path(id)) as PackedScene).instantiate() as Level
		level.preview_only = true
		root.add_child(level)
		await process_frame
		var out := _flatten(level, id)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := "%s/%s.glb" % [OUT_DIR, id]
		var err := doc.append_from_scene(out, state)
		if err == OK:
			err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
		print("%s: %s (%d meshes)" % [id, path if err == OK else "FAILED (%s)" % error_string(err),
			out.get_child_count()])
		if err != OK:
			failed += 1
		out.free()
		level.queue_free()
		await process_frame
	quit(1 if failed > 0 else 0)


## A flat copy of the map: meshes with their world transforms, plain
## materials, and empties for the spawns and bomb sites.
func _flatten(level: Level, id: String) -> Node3D:
	var out := Node3D.new()
	out.name = id
	var materials := {}
	var names := {}
	for mi: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		# Named after the map node (the body), not "Mesh".
		var base := String(mi.get_parent().name if mi.name == &"Mesh" else mi.name)
		names[base] = int(names.get(base, 0)) + 1
		copy.name = base if names[base] == 1 else "%s_%d" % [base, names[base]]
		copy.transform = mi.global_transform
		for s in mi.mesh.get_surface_count():
			copy.set_surface_override_material(s, _plain(mi.get_active_material(s), materials))
		out.add_child(copy)
	for list: Array in [level.blue_spawn_points, level.red_spawn_points, level.spawn_points]:
		for m: Marker3D in list:
			if m and not out.has_node("SPAWN_" + m.name):
				_empty(out, "SPAWN_" + m.name, m.global_transform)
	for site: Marker3D in level.bomb_sites:
		if site:
			_empty(out, "SITE_" + site.name, site.global_transform)
	return out


func _empty(parent: Node3D, n: String, xf: Transform3D) -> void:
	var e := Node3D.new()
	e.name = n
	e.transform = xf
	parent.add_child(e)


## The map's grid shader doesn't survive glTF: a StandardMaterial3D in its
## base colour, one per source material, named after it.
func _plain(src: Material, cache: Dictionary) -> StandardMaterial3D:
	if src == null:
		src = StandardMaterial3D.new()
	if cache.has(src):
		return cache[src]
	var m := StandardMaterial3D.new()
	var n := src.resource_name
	if n == "":
		n = src.resource_scene_unique_id
	m.resource_name = n if n != "" else "Mat_%d" % cache.size()
	if src is ShaderMaterial:
		var c: Variant = (src as ShaderMaterial).get_shader_parameter(&"base_color")
		m.albedo_color = c if c is Color else Color(0.6, 0.6, 0.6)
		var e: Variant = (src as ShaderMaterial).get_shader_parameter(&"emission_energy")
		if e is float and e > 0.0:
			m.emission_enabled = true
			m.emission = m.albedo_color
	elif src is BaseMaterial3D:
		m.albedo_color = (src as BaseMaterial3D).albedo_color
		m.transparency = (src as BaseMaterial3D).transparency
	cache[src] = m
	return m
