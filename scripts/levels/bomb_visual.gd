class_name BombVisual
extends Node3D
## The bomb as seen by every player: carried on the carrier's back, lying
## on the ground when dropped, blinking + beeping faster when planted, and an
## explosion flash. Purely visual — the state comes from Match.bomb.

const BEEP_SLOW := 1.0
const BEEP_FAST := 0.12

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _flash: OmniLight3D
var _beep_timer: float = 0.0
var _flash_t: float = 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.18, 0.26)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.08, 0.06)
	box.material = mat
	_mesh.mesh = box
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.15, 0.1)
	_light.omni_range = 2.5
	_light.light_energy = 0.0
	_light.position.y = 0.15
	add_child(_light)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.7, 0.35)
	_flash.omni_range = 25.0
	_flash.light_energy = 0.0
	add_child(_flash)
	Match.bomb.bomb_exploded.connect(_on_exploded)


func _process(delta: float) -> void:
	var b := Match.bomb
	var level := get_parent() as Level
	visible = Match.mode == GameConfig.Mode.BOMB and b.round_number > 0
	if not visible:
		return
	_mesh.visible = true
	match b.bomb_state:
		BombRules.BombState.CARRIED:
			var carrier := level.get_player(b.bomb_carrier) if level else null
			if carrier == null or carrier.is_local or carrier.health.is_dead:
				_mesh.visible = false # you don't see the bomb on your own back
			else:
				# On the carrier's back.
				global_position = carrier.global_position + Vector3.UP * 1.15 + carrier.global_basis.z * 0.32
				global_rotation = carrier.global_rotation
			_light.light_energy = 0.0
		BombRules.BombState.DROPPED:
			global_position = b.bomb_position + Vector3.UP * 0.09
			_light.light_energy = 0.3
		BombRules.BombState.PLANTED:
			global_position = b.bomb_position + Vector3.UP * 0.09
			_tick(delta, b.phase_time_left / maxf(b.bomb_time, 1.0))
		BombRules.BombState.DEFUSED:
			global_position = b.bomb_position + Vector3.UP * 0.09
			_light.light_energy = 0.0
		BombRules.BombState.EXPLODED:
			_mesh.visible = false
			_light.light_energy = 0.0
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		_flash.light_energy = 16.0 * _flash_t


## Beeps get faster as the timer runs out (fraction 1 → 0).
func _tick(delta: float, fraction: float) -> void:
	var interval := lerpf(BEEP_FAST, BEEP_SLOW, clampf(fraction, 0.0, 1.0))
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = interval
		Audio.play_3d(&"bomb_beep", global_position, -2.0, 40.0, 1.0, 6.0)
		_light.light_energy = 3.0
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 20.0)


func _on_exploded(pos: Vector3) -> void:
	global_position = pos + Vector3.UP * 0.5
	Audio.play_3d(&"explosion", global_position, 0.0, 250.0, 1.0, 25.0)
	_flash_t = 1.0
