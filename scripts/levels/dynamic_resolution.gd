class_name DynamicResolution
extends Node
## Keeps the frame rate at the target by lowering the 3D render resolution
## when frames get slow and raising it again when there is headroom
## (never above the preset's render scale; never below MIN_SCALE).
## The HUD is always drawn at full resolution.
##
## Uses the measured GPU/CPU render time when the renderer reports it (so it
## still works with V-Sync on), otherwise the frame time.

const MIN_SCALE := 0.5
const STEP := 0.05
const INTERVAL := 0.5 # seconds between adjustments
const SMOOTHING := 0.1

## Emitted once per match when even the lowest resolution can't hold the
## target for a while — the HUD suggests a lower preset.
signal struggling

## Seconds at minimum scale while still too slow before `struggling` fires.
const STRUGGLE_SECONDS := 20.0

## Current 3D render scale chosen by the controller.
var scale: float = 1.0
var _struggle_time: float = 0.0
var _warned: bool = false
var _avg_ms: float = 0.0
var _timer: float = 0.0
var _viewport_rid: RID


func _ready() -> void:
	name = "DynamicResolution"
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	scale = SettingsManager.graphics.render_scale
	SettingsManager.graphics_changed.connect(func(_p: GraphicsPreset) -> void:
		scale = minf(scale, SettingsManager.graphics.render_scale) if SettingsManager.dynamic_resolution \
			else SettingsManager.graphics.render_scale
		_apply())


func _process(delta: float) -> void:
	if not SettingsManager.dynamic_resolution:
		return
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
	var ms := maxf(gpu, cpu) if gpu > 0.0 else delta * 1000.0
	update(ms, delta)


## Feeds one frame's cost in milliseconds (public for tests).
func update(frame_ms: float, delta: float) -> void:
	_avg_ms = frame_ms if _avg_ms == 0.0 else lerpf(_avg_ms, frame_ms, SMOOTHING)
	_timer += delta
	if _timer < INTERVAL:
		return
	_timer = 0.0
	var target_ms := 1000.0 / maxf(SettingsManager.dynamic_resolution_target_fps, 1.0)
	var max_scale := SettingsManager.graphics.render_scale
	if _avg_ms > target_ms * 1.05:
		if scale <= MIN_SCALE + 0.001:
			_struggle_time += INTERVAL
			if _struggle_time >= STRUGGLE_SECONDS and not _warned:
				_warned = true
				struggling.emit()
		scale = maxf(scale - STEP, MIN_SCALE)
	elif _avg_ms < target_ms * 0.75:
		scale = minf(scale + STEP, max_scale)
		_struggle_time = 0.0
	scale = minf(scale, max_scale)
	_apply()


func _apply() -> void:
	get_viewport().scaling_3d_scale = scale
