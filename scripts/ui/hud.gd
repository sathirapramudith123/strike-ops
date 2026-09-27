class_name Hud
extends CanvasLayer
## In-game HUD: crosshair, hit markers, health, ammo, reload bar,
## damage flash and the F3 performance overlay.

@onready var _crosshair: Crosshair = %Crosshair
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reserve_label: Label = %ReserveLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _perf_label: Label = %PerfLabel
@onready var _dead_label: Label = %DeadLabel

var _player: PlayerController
var _weapon: Weapon


func bind_player(player: PlayerController) -> void:
	_player = player
	player.health.health_changed.connect(_on_health_changed)
	player.health.damaged.connect(func(_a: float, _s: Node, _h: bool) -> void: _damage_flash.color.a = 0.35)
	_on_health_changed(player.health.current, player.health.max_health)
	_bind_weapon(player.current_weapon)


func _ready() -> void:
	_perf_label.visible = SettingsManager.show_perf_overlay
	_reload_bar.visible = false
	_dead_label.visible = false
	_damage_flash.color.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_perf_overlay"):
		SettingsManager.show_perf_overlay = not SettingsManager.show_perf_overlay
		SettingsManager.save()
		_perf_label.visible = SettingsManager.show_perf_overlay


func _process(delta: float) -> void:
	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta * 0.8)
	if _player:
		_dead_label.visible = _player.health.is_dead
		if _player.current_weapon != _weapon:
			_bind_weapon(_player.current_weapon)
	if _weapon:
		_update_crosshair()
		_reload_bar.visible = _weapon.is_reloading
		_reload_bar.value = _weapon.get_reload_progress()
	if _perf_label.visible:
		_update_perf()


func _bind_weapon(weapon: Weapon) -> void:
	_weapon = weapon
	if weapon == null:
		return
	_weapon_label.text = weapon.data.display_name
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.hit_confirmed.connect(func(kill: bool, _head: bool) -> void: _crosshair.show_hit(kill))
	_on_ammo_changed(weapon.ammo_in_magazine, weapon.ammo_reserve)


func _update_crosshair() -> void:
	# Convert the spread angle into screen pixels so the crosshair is honest.
	var cam := _player.camera
	var half_h := get_viewport().get_visible_rect().size.y * 0.5
	var px := tan(deg_to_rad(_weapon.current_spread)) / tan(deg_to_rad(cam.fov * 0.5)) * half_h
	_crosshair.gap = maxf(px, 3.0)
	_crosshair.ads = _weapon.ads_blend


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = str(ceili(current))


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	_ammo_label.text = str(in_magazine)
	_reserve_label.text = "/ %d" % reserve
	var low := _weapon and in_magazine <= _weapon.data.magazine_size / 4
	_ammo_label.modulate = Color(1, 0.35, 0.3) if low else Color.WHITE


func _update_perf() -> void:
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	_perf_label.text = "FPS %d  (%.1f ms)\nDraw calls %d  |  Tris %dk\nVRAM %.0f MB\nPreset %s  |  %s" % [
		fps, frame_ms, draw_calls, prims / 1000, vram,
		SettingsManager.graphics.display_name, RenderingServer.get_current_rendering_method()]
