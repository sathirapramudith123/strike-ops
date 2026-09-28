class_name BotManager
extends Node
## Training bots (child of the Match autoload: /root/Match/Bots).
##
## Bots are players in the roster (with "bot": true and ids from
## BOT_ID_BASE) that the server spawns like anyone else, so every peer sees
## them as ordinary remote players: they take teams, score, die, respawn,
## earn and buy in Bomb Defusal. On the server a BotBrain drives each one.
##
## They find their way on a navigation mesh baked from the level's collision
## when a map loads (well under 0.1 s on every map). Set how many and how
## good in the main menu (Settings → saved) or add / remove them in the Esc
## menu while hosting.

enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES: PackedStringArray = ["Easy", "Normal", "Hard"]
const BOT_ID_BASE := 2_000_000_000
const MAX_BOTS := 15
const NAMES: PackedStringArray = ["Nuwan", "Saman", "Kamal", "Dilan", "Ruwan", "Chamara", "Tharindu", "Isuru",
	"Lahiru", "Pasindu", "Kasun", "Dasun", "Sahan", "Janith", "Malith"]
## Every third bot is a woman (a female body and a random look to match).
const FEMALE_NAMES: PackedStringArray = ["Nimali", "Sanduni", "Dilini", "Hasini", "Kavindi"]

var difficulty: int = Difficulty.NORMAL

var _nav_region: NavigationRegion3D


static func is_bot(peer_id: int) -> bool:
	return peer_id >= BOT_ID_BASE


## Bot ids in the roster.
func bot_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in NetworkManager.roster:
		if is_bot(id):
			ids.append(id)
	ids.sort()
	return ids


func count() -> int:
	return bot_ids().size()


## Server: add or remove bots until there are `n`.
func set_count(n: int) -> void:
	if not multiplayer.is_server():
		return
	n = clampi(n, 0, MAX_BOTS)
	var ids := bot_ids()
	while ids.size() > n:
		remove_bot(ids.pop_back())
	while ids.size() < n:
		ids.append(add_bot())


## Server: a new bot joins (and spawns now if a level is running). Returns its id.
func add_bot() -> int:
	var id := BOT_ID_BASE
	while NetworkManager.roster.has(id):
		id += 1
	var n := id - BOT_ID_BASE
	var female := n % 3 == 2
	var bot_name: String = FEMALE_NAMES[int(n / 3.0) % FEMALE_NAMES.size()] if female else NAMES[n % NAMES.size()]
	var entry := NetworkManager._new_entry("BOT %s" % bot_name)
	entry.bot = true
	entry.look = CharacterLook.pack(CharacterLook.random(id, 1 if female else 0))
	NetworkManager.roster[id] = entry
	NetworkManager.roster[id].team = Match.assign_team(id)
	NetworkManager.broadcast_roster()
	var level := NetworkManager.current_level()
	if level and not level.preview_only and (level.get_player(1) != null or NetworkManager.is_dedicated()):
		_ensure_navigation(level)
		NetworkManager._server_spawn(id)
	return id


## Server: a bot leaves.
func remove_bot(id: int) -> void:
	if not is_bot(id) or not NetworkManager.roster.has(id):
		return
	var level := NetworkManager.current_level()
	var p := level.get_player(id) if level else null
	Match.on_player_left(id, p.global_position if p else Vector3.ZERO)
	NetworkManager.roster.erase(id)
	if level:
		level.despawn_player(id)
	NetworkManager.send_to_ready(NetworkManager, &"_despawn_player", [id])
	NetworkManager.broadcast_roster()


## Server: a level finished loading — bake its navigation and spawn the bots.
func on_level_loaded(level: Level) -> void:
	_nav_region = null
	var ids := bot_ids()
	if ids.is_empty():
		return
	_ensure_navigation(level)
	for id in ids:
		NetworkManager._server_spawn(id)


## The navigation map bots path on (baked on first use per level).
func nav_map(level: Level) -> RID:
	_ensure_navigation(level)
	return level.get_world_3d().navigation_map


func _ensure_navigation(level: Level) -> void:
	if level == null or (is_instance_valid(_nav_region) and _nav_region.get_parent() == level):
		return
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.35
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	var source := NavigationMeshSourceGeometryData3D.new()
	var root: Node = level.get_node_or_null("Geometry")
	if root == null:
		root = level # hand-made maps (Test Range)
	NavigationServer3D.parse_source_geometry_data(nm, source, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "BotNavigation"
	_nav_region.navigation_mesh = nm
	level.add_child(_nav_region)
	print("[bots] navigation baked: %d polygons" % nm.get_polygon_count())
