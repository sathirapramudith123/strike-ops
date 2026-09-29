class_name IconRenderer
extends RefCounted
## Small pictures for the HUD, rendered once from the real models and cached
## (no image files): a player's portrait from their CharacterLook (head and
## shoulders, lit from the front) and a weapon's white side silhouette from
## WeaponModel. Rendering takes a few frames in an off-screen viewport, so
## ask with request_*() and read cached_*() — null until it is ready (and
## always in headless mode, where the HUD draws its fallbacks).

const PORTRAIT_SIZE := Vector2i(96, 96)
const WEAPON_SIZE := Vector2i(192, 72)

static var _portraits: Dictionary = {} # look key -> Texture2D
static var _weapons: Dictionary = {} # weapon id -> Texture2D
static var _pending: Dictionary = {} # key -> true while rendering
static var _queue: Array = [] # [kind, key, arg]
static var _busy := false


static func cached_portrait(look: Dictionary) -> Texture2D:
	return _portraits.get(CharacterLook.key_of(CharacterLook.sanitize(look)))


static func cached_weapon(weapon_id: String) -> Texture2D:
	return _weapons.get(weapon_id)


## Queues a portrait of `look` (no-op if cached or queued).
static func request_portrait(host: Node, look: Dictionary) -> void:
	var clean := CharacterLook.sanitize(look)
	var key := "p:" + CharacterLook.key_of(clean)
	if _portraits.has(key.substr(2)) or _pending.has(key):
		return
	_pending[key] = true
	_queue.append(["portrait", key, clean])
	_pump(host)


static func request_weapon(host: Node, weapon_id: String) -> void:
	var key := "w:" + weapon_id
	if _weapons.has(weapon_id) or _pending.has(key) or not WeaponModel.has_model(weapon_id):
		return
	_pending[key] = true
	_queue.append(["weapon", key, weapon_id])
	_pump(host)


## Renders the queue one picture at a time.
static func _pump(host: Node) -> void:
	if _busy or _queue.is_empty() or host == null or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		_queue.clear()
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var tree := host.get_tree()
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = PORTRAIT_SIZE if job[0] == "portrait" else WEAPON_SIZE
	tree.root.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	if job[0] == "portrait":
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.62, 0.68)
		env.environment = e
		vp.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-20, 25, 0)
		light.light_energy = 1.2
		vp.add_child(light)
		var model := PlayerModel.new()
		vp.add_child(model)
		model.set_look(job[2])
		model.set_team_color(Color(0.55, 0.6, 0.66))
		model.rotation.y = PI
		cam.fov = 26.0
		cam.position = Vector3(0, 1.58, 1.15)
		cam.look_at(Vector3(0, 1.56, 0))
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = WeaponModel.get_mesh(job[2])
		var white := StandardMaterial3D.new()
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		white.albedo_color = Color.WHITE
		mesh.material_override = white
		vp.add_child(mesh)
		mesh.rotation.y = -PI * 0.5 # side on, the muzzle (-Z) pointing right
		var aabb := mesh.get_aabb()
		var length := maxf(aabb.size.z, 0.3)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = length * 0.42
		var mid := aabb.get_center()
		var center := Vector3(-mid.z, mid.y, 0)
		cam.position = center + Vector3(0, 0, 2)
		cam.look_at(center)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		if job[0] == "portrait":
			_portraits[String(job[1]).substr(2)] = tex
		else:
			_weapons[job[2]] = tex
	_pending.erase(job[1])
	vp.queue_free()
	_busy = false
	if is_instance_valid(host) and host.is_inside_tree():
		_pump(host)
	elif not _queue.is_empty() and tree:
		_pump(tree.root)
