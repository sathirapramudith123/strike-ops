class_name Level
extends Node3D
## Base script for playable maps. Applies graphics settings to the map's
## environment and sun, spawns players (local and remote) and wires up the HUD.
##
## Spawning is driven by NetworkManager: the server decides who spawns where and
## every peer calls spawn_player() with the same arguments, so node paths
## (/root/<Map>/Players/<peer_id>) match everywhere and RPCs find their target.

const DEFAULT_PLAYER_SCENE := "res://scenes/player/player.tscn"

## Loaded at runtime (not preloaded) to avoid compile-time dependency cycles.
@export var player_scene: PackedScene
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Free-for-all spawns (also used in team modes if a team has none).
@export var spawn_points: Array[Marker3D] = []
@export var blue_spawn_points: Array[Marker3D] = []
@export var red_spawn_points: Array[Marker3D] = []
## Bomb Defusal sites (Marker3D named "A", "B" at the centre of each site).
## In Bomb Defusal the red spawns are the attackers' side and the blue spawns
## the defenders', whichever team is attacking.
@export var bomb_sites: Array[Marker3D] = []
## Merge the static meshes under "Geometry" at load time (see StaticBatcher).
@export var static_batching: bool = true
## Benchmark A/B switch (`--no-batching`).
static var batching_disabled: bool = false
## Real art for a map, built in Blender over its blockout (README → Real 3D
## art): res://assets/maps/<map>/<map>.glb. It replaces the greybox meshes
## that use the same materials (Mat_brick …); collision stays the greybox's.
const ART_DIR := "res://assets/maps"
## Draw the greybox even when the map has art (`--no-art`, blockout export).
static var art_disabled: bool = false
## Set before adding to the tree to load the map for a menu preview only:
## no players, network, HUD or menus (see MapPreview).
var preview_only: bool = false

## The local player (null on a dedicated server or before spawning).
var player: PlayerController
var players_root: Node3D

var _spawn_index: int = 0
var _spectate_index: int = 0
var _spectating: PlayerController
var _detail_batches: Array[MeshInstance3D] = []
var dynamic_resolution: DynamicResolution
## What StaticBatcher did (shown by the benchmark / tests).
var batch_stats: Dictionary = {}
## The map's art scene under Geometry (null when the map has none).
var art: Node3D
## How many greybox meshes the art replaced.
var art_replaced: int = 0
## The art's materials by name (Mat_metal …), shared with the detail layer.
var art_materials: Dictionary = {}
## The map's High/Ultra detail layer while GraphicsPreset.map_detail is on.
var detail: MapDetail

@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	_load_art(get_node_or_null("Geometry") as Node3D)
	if preview_only:
		hud.queue_free()
		pause_menu.queue_free()
		if world_environment:
			SettingsManager.apply_to_environment(world_environment.environment)
		_update_detail()
		return
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	add_child(ImpactDecals.new())
	if not NetworkManager.is_dedicated():
		dynamic_resolution = DynamicResolution.new()
		add_child(dynamic_resolution)
		dynamic_resolution.struggling.connect(hud.show_performance_hint)
	var geometry := get_node_or_null("Geometry") as Node3D
	# (A dedicated server draws nothing — no need to batch there.)
	if static_batching and not batching_disabled and geometry and not NetworkManager.is_dedicated():
		batch_stats = StaticBatcher.batch(geometry, SettingsManager.graphics.draw_distance_scale)
		_detail_batches = batch_stats.details
	if player_scene == null:
		player_scene = load(DEFAULT_PLAYER_SCENE)
	_apply_graphics(SettingsManager.graphics)
	SettingsManager.graphics_changed.connect(_apply_graphics)
	if NetworkManager.is_dedicated():
		hud.visible = false
	if not bomb_sites.is_empty() and not NetworkManager.is_dedicated():
		var visual := BombVisual.new()
		visual.name = "BombVisual"
		add_child(visual)
	NetworkManager.on_level_loaded(self)
	Audio.play_music(&"match")
	if not NetworkManager.is_dedicated() and DisplayServer.get_name() != "headless":
		add_child.call_deferred(ShaderWarmup.new())


func _process(_delta: float) -> void:
	if not preview_only:
		_update_spectator()


func spawn_player(peer_id: int, player_name: String, xform: Transform3D,
		primary: String = GameConfig.DEFAULT_PRIMARY, slot: int = 0) -> PlayerController:
	var existing := get_player(peer_id)
	if existing:
		return existing
	# A player despawned this frame still holds the name — move it aside.
	var stale := players_root.get_node_or_null(str(peer_id))
	if stale:
		stale.name = "%d_despawned" % peer_id
	var p := player_scene.instantiate() as PlayerController
	p.name = str(peer_id)
	p.peer_id = peer_id
	p.player_name = player_name
	p.primary_id = primary
	p.current_slot = slot
	p.transform = xform
	players_root.add_child(p)
	if p.is_local:
		player = p
		hud.bind_player(p)
		pause_menu.player = p
	return p


func despawn_player(peer_id: int) -> void:
	var p := get_player(peer_id)
	if p:
		if p == player:
			player = null
		p.queue_free()


func get_player(peer_id: int) -> PlayerController:
	var p := players_root.get_node_or_null(str(peer_id)) as PlayerController
	return p if p and not p.is_queued_for_deletion() else null


func get_players() -> Array[PlayerController]:
	var result: Array[PlayerController] = []
	for child in players_root.get_children():
		if child is PlayerController and not child.is_queued_for_deletion():
			result.append(child)
	return result


## Server: where `peer_id` should (re)spawn — their team's spawns in team
## modes, and the spawn furthest from living enemies ("safe spawn").
func next_spawn_transform(peer_id: int = -1) -> Transform3D:
	var candidates := spawn_points
	if Match.is_team_mode():
		var side := Match.get_team(peer_id)
		if Match.mode == GameConfig.Mode.BOMB and side >= 0:
			side = 1 if Match.bomb.is_attacker(peer_id) else 0
		match side:
			0: candidates = blue_spawn_points if not blue_spawn_points.is_empty() else spawn_points
			1: candidates = red_spawn_points if not red_spawn_points.is_empty() else spawn_points
	if candidates.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP)

	var enemies: Array[Vector3] = []
	for p in get_players():
		if p.peer_id != peer_id and not p.health.is_dead and not Match.is_friendly(peer_id, p.peer_id):
			enemies.append(p.global_position)
	if enemies.is_empty():
		# Nobody to avoid: rotate through the spawns.
		var marker := candidates[_spawn_index % candidates.size()]
		_spawn_index += 1
		return marker.global_transform

	var best: Marker3D = candidates[0]
	var best_score := -1.0
	for m in candidates:
		var nearest := INF
		for e in enemies:
			nearest = minf(nearest, m.global_position.distance_to(e))
		# Small random jitter so equal spawns don't always pick the same one.
		var score := nearest + randf() * 2.0
		if score > best_score:
			best_score = score
			best = m
	return best.global_transform


## Bomb Defusal: while dead, watch a living teammate (Shoot = next player).
func _update_spectator() -> void:
	if player == null:
		return
	var want := player.health.is_dead and Match.mode == GameConfig.Mode.BOMB
	if not want:
		if _spectating:
			_spectating = null
			player.camera.current = true
		return
	var mates := get_players().filter(func(p: PlayerController) -> bool:
		return p != player and not p.health.is_dead and Match.is_friendly(p.peer_id, player.peer_id))
	if mates.is_empty():
		if _spectating:
			_spectating = null
			player.camera.current = true
		return
	if Input.is_action_just_pressed(&"shoot"):
		_spectate_index += 1
	var target: PlayerController = mates[_spectate_index % mates.size()]
	if target != _spectating:
		_spectating = target
		target.camera.current = true


## Swaps the greybox look for the map's art, if it has any: greybox meshes
## whose material the art also has (by name) are hidden — their big boxes
## still become occluders — and the art goes under Geometry, so StaticBatcher
## merges it like the greybox. Doors and glass aren't under Geometry.
func _load_art(geometry: Node3D) -> void:
	if art_disabled or geometry == null or NetworkManager.is_dedicated():
		return
	var id := scene_file_path.get_file().get_basename()
	var path := "%s/%s/%s.glb" % [ART_DIR, id, id]
	if id == "" or not ResourceLoader.exists(path):
		return
	art = (load(path) as PackedScene).instantiate() as Node3D
	art.name = "Art"
	art_materials.clear()
	for mi: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m:
				art_materials[m.resource_name] = m
			# Photo textures seen at a glance angle (floors, long walls)
			# blur without it; cheap next to the fill cost.
			if m is BaseMaterial3D:
				(m as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for mi: MeshInstance3D in geometry.find_children("*", "MeshInstance3D", true, false):
		var m := mi.get_active_material(0) if mi.mesh else null
		if m and art_materials.has(m.resource_scene_unique_id):
			StaticBatcher.add_occluder(geometry, mi)
			mi.visible = false # (StaticBatcher skips hidden meshes)
			mi.queue_free()
			art_replaced += 1
	geometry.add_child(art)


## Adds or removes the map's detail layer (assets/maps/<map>/<map>_detail.tscn)
## to follow the Map detail graphics option.
func _update_detail() -> void:
	var want := SettingsManager.graphics.map_detail and not art_disabled and not NetworkManager.is_dedicated()
	if want == (detail != null):
		return
	if detail:
		detail.restore()
		detail.queue_free()
		detail = null
		return
	var id := scene_file_path.get_file().get_basename()
	var path := "%s/%s/%s_detail.tscn" % [ART_DIR, id, id]
	if id == "" or not ResourceLoader.exists(path):
		return
	detail = (load(path) as PackedScene).instantiate() as MapDetail
	detail.name = "Detail"
	add_child(detail)
	detail.apply(self)


## Bounding box of the map geometry (used to frame previews).
func world_bounds() -> AABB:
	var box := AABB()
	var first := true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Who the local player is watching (null when not spectating).
func spectating() -> PlayerController:
	return _spectating


func _apply_graphics(_preset: GraphicsPreset) -> void:
	_update_detail()
	StaticBatcher.set_detail_distance(_detail_batches, SettingsManager.graphics.draw_distance_scale)
	if detail and detail.batch_stats.has("details"):
		StaticBatcher.set_detail_distance(detail.batch_stats.details, SettingsManager.graphics.draw_distance_scale)
	var lights := get_node_or_null("Lights")
	if lights:
		lights.visible = SettingsManager.graphics.dynamic_lights
	if world_environment:
		SettingsManager.apply_to_environment(world_environment.environment)
	if sun:
		SettingsManager.apply_to_directional_light(sun)
