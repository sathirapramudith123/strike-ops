class_name Level
extends Node3D
## Base script for playable maps. Applies graphics settings to the map's
## environment and sun, spawns the local player and wires up the HUD.

const DEFAULT_PLAYER_SCENE := "res://scenes/player/player.tscn"

## Loaded at runtime (not preloaded) to avoid compile-time dependency cycles.
@export var player_scene: PackedScene
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var spawn_points: Array[Marker3D] = []

var player: PlayerController

@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	_apply_graphics(SettingsManager.graphics)
	SettingsManager.graphics_changed.connect(_apply_graphics)
	spawn_local_player()


func spawn_local_player() -> void:
	if player_scene == null:
		player_scene = load(DEFAULT_PLAYER_SCENE)
	player = player_scene.instantiate() as PlayerController
	var spawn := _pick_spawn()
	add_child(player)
	player.global_transform = spawn
	player.set_spawn_transform(spawn)
	hud.bind_player(player)
	pause_menu.player = player


func _pick_spawn() -> Transform3D:
	if spawn_points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP)
	return spawn_points.pick_random().global_transform


func _apply_graphics(_preset: GraphicsPreset) -> void:
	if world_environment:
		SettingsManager.apply_to_environment(world_environment.environment)
	if sun:
		SettingsManager.apply_to_directional_light(sun)
