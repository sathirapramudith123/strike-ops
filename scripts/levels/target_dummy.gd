class_name TargetDummy
extends Node3D
## Shooting-range target: flashes when hit, falls over when killed,
## respawns after a delay (server-driven). Can optionally strafe left/right —
## the strafe is time-based so it looks the same on every peer.

@export var respawn_time: float = 3.0
## Strafe distance (metres) to each side; 0 = static target.
@export var move_distance: float = 0.0
@export var move_speed: float = 2.0

@onready var health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _hitboxes: Array[Node] = find_children("*", "Hitbox", true, false)

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _flash: float = 0.0
var _respawn_timer: float = 0.0
var _origin: Vector3
var _time: float = 0.0


func _ready() -> void:
	_origin = position
	for mesh: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
			continue # stripped on dedicated-server exports
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		if mat:
			mat = mat.duplicate() as StandardMaterial3D
			mesh.material_override = mat
			_materials.append(mat)
			_base_colors.append(mat.albedo_color)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)


func _process(delta: float) -> void:
	if health.is_dead:
		_visual.rotation.x = lerpf(_visual.rotation.x, -PI * 0.5, clampf(delta * 8.0, 0.0, 1.0))
		# Only the server decides when targets come back; clients get `revived`.
		if multiplayer.is_server():
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				health.revive()
		return

	_visual.rotation.x = lerpf(_visual.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if move_distance > 0.0:
		_time = NetworkManager.server_time()
		position = _origin + basis.x * sin(_time * move_speed / move_distance) * move_distance

	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		for i in _materials.size():
			_materials[i].albedo_color = _base_colors[i].lerp(Color(1, 0.25, 0.2), _flash)


func _on_damaged(_amount: float, _source: Node, _is_headshot: bool) -> void:
	_flash = 1.0


func _on_died(_source: Node) -> void:
	_respawn_timer = respawn_time
	for hb: Node in _hitboxes:
		(hb as Hitbox).get_child(0).set_deferred("disabled", true)


func _on_revived() -> void:
	for hb: Node in _hitboxes:
		(hb as Hitbox).get_child(0).set_deferred("disabled", false)
