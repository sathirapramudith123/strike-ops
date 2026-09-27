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
@export var spawn_points: Array[Marker3D] = []

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


func spawn_player(peer_id: int, player_name: String, xform: Transform3D) -> PlayerController:
	var existing := get_player(peer_id)
	if existing:
		return existing
	var p := player_scene.instantiate() as PlayerController
	p.name = str(peer_id)
	p.peer_id = peer_id
	p.player_name = player_name
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


## Server: next spawn point (round robin).
func next_spawn_transform() -> Transform3D:
	if spawn_points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP)
	var marker := spawn_points[_spawn_index % spawn_points.size()]
	_spawn_index += 1
	return marker.global_transform


func _apply_graphics(_preset: GraphicsPreset) -> void:
	if world_environment:
		SettingsManager.apply_to_environment(world_environment.environment)
	if sun:
		SettingsManager.apply_to_directional_light(sun)
