class_name MapPreview
extends RefCounted
## Renders a small bird's-eye picture of a map for the map selection screen.
##
## The map scene is loaded into its own off-screen world (Level.preview_only:
## no players, network or HUD), photographed once from above at an angle,
## and the image is cached for the rest of the session — no image files to
## keep in sync when maps change.

const SIZE := Vector2i(384, 216)

static var _cache: Dictionary = {}


## The preview if it was already rendered this session (else null).
static func cached(map_path: String) -> Texture2D:
	return _cache.get(map_path)


## Returns the preview texture (null in headless mode). `host` is any node in
## the tree to attach the temporary viewport to.
static func render(host: Node, map_path: String) -> Texture2D:
	if _cache.has(map_path):
		return _cache[map_path]
	if DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)

	var level := (load(map_path) as PackedScene).instantiate() as Level
	level.preview_only = true
	vp.add_child(level)
	await host.get_tree().process_frame
	if not is_instance_valid(vp):
		return null

	var bounds := level.world_bounds()
	var center := bounds.get_center()
	var extent := maxf(bounds.size.x, bounds.size.z) * 0.5
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = extent * 6.0
	level.add_child(cam)
	cam.global_position = center + Vector3(0, extent * 1.35, extent * 1.25)
	cam.look_at(center, Vector3.UP)
	cam.current = true

	for i in 3:
		await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return null # the menu that asked went away meanwhile
	var tex: Texture2D = null
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
		_cache[map_path] = tex
	vp.queue_free()
	return tex
