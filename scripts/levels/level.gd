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

## The local player (null on a dedicated server or before spawning).
var player: PlayerController
var players_root: Node3D

var _spawn_index: int = 0

@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	if player_scene == null:
		player_scene = load(DEFAULT_PLAYER_SCENE)
	_apply_graphics(SettingsManager.graphics)
	SettingsManager.graphics_changed.connect(_apply_graphics)
	if NetworkManager.is_dedicated():
		hud.visible = false
	NetworkManager.on_level_loaded(self)


func spawn_player(peer_id: int, player_name: String, xform: Transform3D,
		primary: String = GameConfig.DEFAULT_PRIMARY, slot: int = 0) -> PlayerController:
	var existing := get_player(peer_id)
	if existing:
		return existing
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
	return players_root.get_node_or_null(str(peer_id)) as PlayerController


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
		match Match.get_team(peer_id):
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


func _apply_graphics(_preset: GraphicsPreset) -> void:
	if world_environment:
		SettingsManager.apply_to_environment(world_environment.environment)
	if sun:
		SettingsManager.apply_to_directional_light(sun)
