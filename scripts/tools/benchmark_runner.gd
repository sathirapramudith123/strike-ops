class_name BenchmarkRunner
extends Node
## Built-in performance benchmark.
##
## Loads each map offline, spawns moving bot players that fire now and then
## (muzzle lights, impacts, sounds), flies the camera along the spawn points
## while turning, and records frame times plus renderer / CPU counters.
## Results are printed, saved as JSON to user://benchmarks/ and returned.
##
## Run it:
##   • Settings → Graphics → "Run benchmark"
##   • godot --path . -- --benchmark [--duration 10] [--bots 12] [--maps warehouse,courtyard]
##     (add --quit to exit when done, --no-batching to compare without
##     StaticBatcher; use a real window, not --headless)
##
## Use it on the minimum-spec PC: the "1% low" is what players feel.

signal finished(results: Dictionary)

const RESULTS_DIR := "user://benchmarks/"
const WARMUP := 1.0
## A preset "passes" when the 1% low stays above this (Settings auto-detect).
const TARGET_1PCT_LOW_FPS := 50.0

var duration: float = 10.0
var bot_count: int = 12
var maps: Array[String] = []
var quit_when_done: bool = false
## -1 = keep the player's current graphics settings.
var preset_override: int = -1
## GraphicsPreset property -> value, applied for this run only.
var graphics_overrides: Dictionary = {}
var dynamic_resolution: bool = false

## Last finished run (kept for the main menu to show).
static var last_results: Dictionary = {}

var _frame_ms := PackedFloat32Array()
var _draw_calls: float = 0.0
var _primitives: float = 0.0
var _render_scale: float = 0.0
var _samples: int = 0
var _measuring: bool = false


## Parses `-- --benchmark ...` command line options. Returns null if absent.
static func from_args(args: PackedStringArray) -> BenchmarkRunner:
	if not "--benchmark" in args:
		return null
	var r := BenchmarkRunner.new()
	for i in args.size():
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		if "=" in key:
			value = key.get_slice("=", 1)
			key = key.get_slice("=", 0)
		match key:
			"--duration": r.duration = maxf(value.to_float(), 2.0)
			"--bots": r.bot_count = clampi(value.to_int(), 0, 32)
			"--maps":
				for id in value.split(","):
					r.maps.append(GameConfig.map_path(id.strip_edges()))
			"--quit": r.quit_when_done = true
			"--no-batching": Level.batching_disabled = true # A/B comparison
			"--dynamic-resolution": r.dynamic_resolution = true
			"--preset":
				r.preset_override = ["low", "medium", "high", "ultra"].find(value.to_lower())
			"--set":
				# A/B any graphics option for this run only: --set dynamic_lights=false
				r.graphics_overrides[value.get_slice("=", 0)] = str_to_var(value.get_slice("=", 1))
	return r


func _ready() -> void:
	name = "BenchmarkRunner"
	if maps.is_empty():
		for m: Dictionary in GameConfig.MAPS:
			maps.append(m.path)
	_run.call_deferred()


func _process(delta: float) -> void:
	if not _measuring:
		return
	_frame_ms.append(delta * 1000.0)
	_draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_render_scale += get_viewport().scaling_3d_scale
	_samples += 1


func _run() -> void:
	# Uncapped: V-Sync and FPS limits would hide the real cost.
	var saved_vsync := SettingsManager.vsync
	var saved_fps := SettingsManager.max_fps
	var saved_dynres := SettingsManager.dynamic_resolution
	SettingsManager.vsync = false
	SettingsManager.max_fps = 0
	# Measure the preset as configured (dynamic resolution would hide the cost).
	SettingsManager.dynamic_resolution = dynamic_resolution
	SettingsManager.apply_display()
	# Temporary graphics changes (not saved).
	var saved_graphics := SettingsManager.graphics
	if preset_override >= 0 or not graphics_overrides.is_empty():
		SettingsManager.graphics = SettingsManager.load_preset(preset_override) \
			if preset_override >= 0 else saved_graphics.duplicate()
		for key: String in graphics_overrides:
			SettingsManager.graphics.set(key, graphics_overrides[key])
		SettingsManager.apply_graphics()

	var per_map := []
	for map_path in maps:
		per_map.append(await _run_map(map_path))

	var tested := SettingsManager.graphics
	SettingsManager.graphics = saved_graphics
	SettingsManager.apply_graphics()
	SettingsManager.vsync = saved_vsync
	SettingsManager.max_fps = saved_fps
	SettingsManager.dynamic_resolution = saved_dynres
	SettingsManager.apply_display()

	var results := {
		"version": ProjectSettings.get_setting("application/config/version", "0"),
		"date": Time.get_datetime_string_from_system(),
		"preset": tested.display_name,
		"overrides": graphics_overrides,
		"batching": not Level.batching_disabled,
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"render_scale": tested.render_scale,
		"dynamic_resolution": dynamic_resolution,
		"resolution": get_viewport().get_visible_rect().size,
		"bots": bot_count,
		"duration": duration,
		"maps": per_map,
		"summary": _summary(per_map),
	}
	last_results = results
	_print(results)
	_save(results)
	finished.emit(results)
	if quit_when_done:
		get_tree().quit()
	else:
		NetworkManager.leave()
		queue_free()


func _run_map(map_path: String) -> Dictionary:
	NetworkManager.start_offline(map_path)
	var level: Level = null
	while level == null or level.player == null:
		await get_tree().process_frame
		level = get_tree().current_scene as Level
	level.hud.visible = true
	var player := level.player
	player.input_enabled = false
	var bots := _spawn_bots(level)

	var waypoints: Array[Vector3] = []
	for m in level.spawn_points:
		waypoints.append(m.global_position)
	if waypoints.is_empty():
		waypoints.append(Vector3.UP)

	_reset_counters()
	var t := 0.0
	var fire_timer := 0.0
	while t < duration + WARMUP:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_measuring = t > WARMUP
		# Camera: glide between spawn points while turning a full circle every 6 s.
		var seg := t / (duration + WARMUP) * waypoints.size()
		var a := waypoints[int(seg) % waypoints.size()]
		var b := waypoints[(int(seg) + 1) % waypoints.size()]
		player.global_position = a.lerp(b, seg - floorf(seg)) + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.rotation.y = t * TAU / 6.0
		player.head.rotation.x = sin(t * 0.7) * 0.2
		# Bots: circle around their spawn; fire a few times per second in total.
		_move_bots(bots, t)
		fire_timer -= dt
		if fire_timer <= 0.0 and not bots.is_empty():
			fire_timer = 0.25
			var shooter: PlayerController = bots.pick_random()
			var fwd := -shooter.global_basis.z
			shooter.current_weapon._play_remote_fx(
				PackedVector3Array([shooter.global_position + fwd * 8.0 + Vector3.UP]), PackedVector3Array([-fwd]))
	_measuring = false
	var stats := _stats(GameConfig.map_name(map_path))
	stats["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	stats["video_mem_mb"] = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)
	return stats


func _spawn_bots(level: Level) -> Array[PlayerController]:
	var bots: Array[PlayerController] = []
	var spawns := level.spawn_points
	for i in bot_count:
		var m: Marker3D = spawns[i % spawns.size()] if not spawns.is_empty() else null
		var pos := m.global_position if m else Vector3(i * 2.0, 0, 0)
		bots.append(level.spawn_player(5000 + i, "Bot %d" % (i + 1), Transform3D(Basis.IDENTITY, pos)))
	return bots


## Feeds the bots' network interpolation with snapshots, like real players.
func _move_bots(bots: Array[PlayerController], t: float) -> void:
	var now := NetworkManager.server_time()
	for i in bots.size():
		var bot := bots[i]
		var origin: Vector3 = bot.get_meta(&"origin", bot.global_position)
		bot.set_meta(&"origin", origin)
		var ang := t * 0.8 + i
		var pos := origin + Vector3(cos(ang), 0, sin(ang)) * 2.5
		bot.net_sync._push_snapshot(now, pos, -ang, 0.0, bot.stand_height, 0)


func _reset_counters() -> void:
	_frame_ms.clear()
	_draw_calls = 0.0
	_primitives = 0.0
	_render_scale = 0.0
	_samples = 0


func _stats(map_name: String) -> Dictionary:
	var n := maxi(_samples, 1)
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var avg_ms := total / maxf(sorted.size(), 1)
	# 1% low: average of the slowest 1% of frames.
	var worst := maxi(int(sorted.size() * 0.01), 1)
	var worst_total := 0.0
	for i in worst:
		worst_total += sorted[sorted.size() - 1 - i] if sorted.size() > i else 0.0
	var low_ms := worst_total / worst
	return {
		"map": map_name,
		"frames": sorted.size(),
		"avg_fps": snappedf(1000.0 / maxf(avg_ms, 0.001), 0.1),
		"one_percent_low_fps": snappedf(1000.0 / maxf(low_ms, 0.001), 0.1),
		"avg_frame_ms": snappedf(avg_ms, 0.01),
		"max_frame_ms": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, 0.01),
		"spikes_over_50ms": sorted.size() - sorted.bsearch(50.0, false), # sorted ascending
		"draw_calls": roundi(_draw_calls / n),
		"primitives": roundi(_primitives / n),
		"avg_render_scale": snappedf(_render_scale / n, 0.01),
	}


func _summary(per_map: Array) -> Dictionary:
	var worst_low := INF
	var avg := 0.0
	for m: Dictionary in per_map:
		worst_low = minf(worst_low, m.one_percent_low_fps)
		avg += m.avg_fps
	avg /= maxf(per_map.size(), 1)
	return {
		"avg_fps": snappedf(avg, 0.1),
		"worst_one_percent_low_fps": snappedf(worst_low, 0.1),
		"passes_target": worst_low >= TARGET_1PCT_LOW_FPS,
	}


func _print(r: Dictionary) -> void:
	print("\n[benchmark] %s · %s · %s · render scale %.2f%s · %d bots" % [
		r.preset, r.renderer, r.gpu, r.render_scale, " (dynamic)" if r.dynamic_resolution else "", r.bots])
	# (Performance TIME_* monitors refresh once a second, so frame times are
	# measured directly from the frame deltas instead.)
	print("[benchmark] %-12s %8s %8s %8s %8s %7s %7s %8s %6s %6s" % [
		"map", "avg fps", "1% low", "avg ms", "max ms", "spikes", "draws", "tris", "nodes", "scale"])
	for m: Dictionary in r.maps:
		print("[benchmark] %-12s %8.1f %8.1f %8.2f %8.2f %7d %7d %8d %6d %6.2f" % [
			m.map, m.avg_fps, m.one_percent_low_fps, m.avg_frame_ms, m.max_frame_ms, m.spikes_over_50ms,
			m.draw_calls, m.primitives, m.nodes, m.avg_render_scale])
	print("[benchmark] summary: avg %.1f fps, worst 1%% low %.1f fps → %s" % [
		r.summary.avg_fps, r.summary.worst_one_percent_low_fps,
		"OK" if r.summary.passes_target else "below %d fps target" % TARGET_1PCT_LOW_FPS])


## One-paragraph result + advice for the main menu.
static func summary_text(r: Dictionary) -> String:
	var s: Dictionary = r.summary
	var text := "Benchmark (%s): average %.0f FPS, worst 1%% low %.0f FPS. " % [r.preset, s.avg_fps, s.worst_one_percent_low_fps]
	if s.passes_target:
		text += "Smooth — you could try a higher preset."
	elif r.preset == "Low":
		text += "Below %d FPS: turn on Dynamic resolution or lower Render scale." % TARGET_1PCT_LOW_FPS
	else:
		text += "Below %d FPS: try a lower preset or Dynamic resolution." % TARGET_1PCT_LOW_FPS
	return text


func _save(r: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS_DIR)
	var path := RESULTS_DIR + "benchmark_%s_%s.json" % [
		String(r.preset).to_lower(), Time.get_datetime_string_from_system().replace(":", "-")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r, "  "))
		print("[benchmark] saved %s" % ProjectSettings.globalize_path(path))
