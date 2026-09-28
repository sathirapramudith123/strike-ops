class_name HardwareTest
extends Node
## Full hardware test (Phase 7b): measures every graphics preset on BOTH
## renderers plus the cost of each expensive option on this PC, and writes a
## report players can send in. The reports tune the presets and the first-launch
## auto-detect (tools/tune_presets.py → resources/settings/gpu_tiers.cfg).
##
##   Settings → Graphics → "Full hardware test"   (≈5 min, restarts the game once)
##   godot --path . -- --hardware-test [--quick] [--quit]   (command line; --quit exits at the end)
##
## The renderer can only change at startup, so the test runs in two stages:
## the current renderer's configurations, then a restart with the other
## renderer, then a restart back to the player's own settings. Progress lives
## in STATE_PATH, so a crash in one stage (e.g. a broken Vulkan driver) is
## recorded and the test carries on instead of looping.

signal finished(report: Dictionary)

const DIR := "user://benchmarks/"
const STATE_PATH := DIR + "hardware_test_state.json"
## Written when a report is ready; the main menu shows it once.
const PENDING_PATH := DIR + "hardware_report_pending.txt"
const REPORT_FORMAT := 1
const RENDERERS: Array[String] = ["gl_compatibility", "forward_plus"]
const RENDERER_NAMES := { "gl_compatibility": "OpenGL", "forward_plus": "Vulkan" }
## One indoor map with lamps + the biggest outdoor map.
const MAPS: Array[String] = ["office", "docks"]
const DURATION := 5.0
const BOTS := 12
const TARGET_AVG_FPS := 60.0
const TARGET_LOW_FPS := BenchmarkRunner.TARGET_1PCT_LOW_FPS
const PLAYABLE_LOW_FPS := 30.0
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]

## What each stage measures. "vs" = the baseline an option is compared with.
const CONFIGS := {
	"gl_compatibility": [
		{ "name": "Low", "preset": 0 },
		{ "name": "Low, render scale 0.5", "preset": 0, "set": { "render_scale": 0.5 }, "vs": "Low" },
		{ "name": "Low, render scale 1.0", "preset": 0, "set": { "render_scale": 1.0 }, "vs": "Low" },
		{ "name": "Low + shadows", "preset": 0, "set": { "shadows_enabled": true }, "vs": "Low" },
		{ "name": "Low + lamps", "preset": 0, "set": { "dynamic_lights": true }, "vs": "Low" },
		{ "name": "Low + glow", "preset": 0, "set": { "glow": true }, "vs": "Low" },
		{ "name": "Low + FXAA", "preset": 0, "set": { "fxaa": true }, "vs": "Low" },
	],
	"forward_plus": [
		{ "name": "Medium", "preset": 1 },
		{ "name": "High", "preset": 2 },
		{ "name": "Ultra", "preset": 3 },
		{ "name": "Low (Vulkan)", "preset": 0 },
		{ "name": "Medium + SSAO", "preset": 1, "set": { "ssao": true }, "vs": "Medium" },
		{ "name": "Medium + SSR", "preset": 1, "set": { "ssr": true }, "vs": "Medium" },
		{ "name": "Medium + volumetric fog", "preset": 1, "set": { "volumetric_fog": true }, "vs": "Medium" },
		{ "name": "Medium + TAA", "preset": 1, "set": { "taa": true, "fxaa": false }, "vs": "Medium" },
		{ "name": "Medium + MSAA 2×", "preset": 1, "set": { "msaa": Viewport.MSAA_2X }, "vs": "Medium" },
		{ "name": "Medium, 2048 shadows", "preset": 1, "set": { "directional_shadow_size": 2048, "directional_shadow_cascades": 2 }, "vs": "Medium" },
		{ "name": "Medium, render scale 1.0", "preset": 1, "set": { "render_scale": 1.0 }, "vs": "Medium" },
		{ "name": "Medium + SDFGI", "preset": 1, "set": { "sdfgi": true }, "vs": "Medium" },
	],
}

## Short run (tests): 2 configs per stage, 1 map, 1.5 s each.
var quick: bool = false
## Restart for the other renderer (off in headless tests: that stage is skipped).
var allow_restart: bool = true

var _label: Label


## Starts a new test from the current renderer.
static func start(quick_run: bool = false) -> HardwareTest:
	DirAccess.make_dir_recursive_absolute(DIR)
	_write_json(STATE_PATH, {
		"started": Time.get_datetime_string_from_system(),
		"quick": quick_run,
		"requested": RenderingServer.get_current_rendering_method(),
		"running": "",
		"stages": {},
	})
	var test := HardwareTest.new()
	test.quick = quick_run
	Engine.get_main_loop().root.add_child.call_deferred(test)
	return test


## After a restart: continues an unfinished test (called by SettingsManager).
static func resume_if_pending() -> HardwareTest:
	if not FileAccess.file_exists(STATE_PATH):
		return null
	var state := _read_json(STATE_PATH)
	var test := HardwareTest.new()
	test.quick = state.get("quick", false)
	return test


static func is_running() -> bool:
	return FileAccess.file_exists(STATE_PATH)


## Path of a finished report the main menu hasn't shown yet ("" = none).
static func take_pending_report() -> String:
	if not FileAccess.file_exists(PENDING_PATH):
		return ""
	var path := FileAccess.get_file_as_string(PENDING_PATH).strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PATH))
	return path if FileAccess.file_exists(path) else ""


func _ready() -> void:
	name = "HardwareTest"
	allow_restart = allow_restart and DisplayServer.get_name() != "headless"
	var layer := CanvasLayer.new()
	layer.layer = 100
	_label = Label.new()
	_label.position = Vector2(16, 56)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)
	_run.call_deferred()


func _run() -> void:
	var state := _read_json(STATE_PATH)
	if state.is_empty():
		queue_free()
		return
	var renderer := RenderingServer.get_current_rendering_method()
	var requested: String = state.get("requested", renderer)
	var stages: Dictionary = state.stages
	if requested != renderer and not stages.has(requested):
		# Asked for Vulkan, got OpenGL: the driver can't run Forward+.
		stages[requested] = { "status": "unsupported" }
	if not stages.has(renderer):
		if state.running == renderer:
			# We were here before and never finished: the stage crashed the game.
			stages[renderer] = { "status": "crashed" }
		else:
			state.running = renderer
			_write_json(STATE_PATH, state)
			var results := await _run_stage(renderer)
			stages[renderer] = { "status": "ok", "results": results }
		state.running = ""
		_write_json(STATE_PATH, state)

	for other in RENDERERS:
		if not stages.has(other):
			if allow_restart:
				state.requested = other
				_write_json(STATE_PATH, state)
				_restart(other)
				return
			stages[other] = { "status": "skipped" }

	var report := build_report(state)
	var path := save_report(report)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
	var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if f:
		f.store_string(path)
		f.close()
	print(report.markdown)
	finished.emit(report)
	if "--quit" in OS.get_cmdline_user_args():
		get_tree().quit()
	elif allow_restart and RenderingServer.get_current_rendering_method() != SettingsManager.graphics.rendering_method:
		SettingsManager.restart_game() # back to the player's own renderer
	else:
		NetworkManager.leave() # main menu shows the report
		queue_free()


func _run_stage(renderer: String) -> Array:
	var configs: Array = CONFIGS[renderer]
	if quick:
		configs = configs.slice(0, 2)
	var map_paths: Array[String] = []
	for id in (MAPS.slice(0, 1) if quick else MAPS):
		map_paths.append(GameConfig.map_path(id))
	var results := []
	for i in configs.size():
		var c: Dictionary = configs[i]
		_label.text = "Hardware test — %s stage %d/2 — %d/%d: %s\nPlease don't touch the mouse or keyboard." % [
			RENDERER_NAMES[renderer], RENDERERS.find(renderer) + 1, i + 1, configs.size(), c.name]
		var bench := BenchmarkRunner.new()
		bench.duration = 1.5 if quick else DURATION
		bench.bot_count = BOTS
		bench.maps = map_paths
		bench.preset_override = c.preset
		bench.graphics_overrides = c.get("set", {})
		bench.save_results = false
		bench.leave_when_done = false
		add_child(bench)
		var r: Dictionary = await bench.finished
		results.append(result_entry(c, renderer, r))
	return results


## One measured configuration, condensed for the report.
static func result_entry(config: Dictionary, renderer: String, bench: Dictionary) -> Dictionary:
	var ms := 0.0
	var low_ms := 0.0
	for m: Dictionary in bench.maps:
		ms += m.avg_frame_ms
		low_ms += 1000.0 / maxf(m.one_percent_low_fps, 0.001)
	var n := maxf(bench.maps.size(), 1)
	var entry := {
		"name": config.name,
		"renderer": renderer,
		"preset": config.preset,
		"set": config.get("set", {}),
		"vs": config.get("vs", ""),
		"avg_fps": bench.summary.avg_fps,
		"low_fps": bench.summary.worst_one_percent_low_fps,
		"avg_frame_ms": snappedf(ms / n, 0.01),
		"low_frame_ms": snappedf(low_ms / n, 0.01),
		"draw_calls": roundi(bench.maps.reduce(func(a: float, m: Dictionary) -> float: return a + m.draw_calls, 0.0) / n),
		"video_mem_mb": bench.maps.reduce(func(a: float, m: Dictionary) -> float: return maxf(a, m.get("video_mem_mb", 0.0)), 0.0),
	}
	return entry


# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

static func system_info() -> Dictionary:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	var types := ["other", "integrated", "discrete", "virtual", "cpu"]
	var t := RenderingServer.get_video_adapter_type()
	return {
		"game": NetworkManager.version_string(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": OS.get_processor_name(),
		"threads": OS.get_processor_count(),
		"ram_gb": snappedf(float(OS.get_memory_info().get("physical", 0)) / 1073741824.0, 0.1),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_type": types[t] if t >= 0 and t < types.size() else "other",
		"driver": RenderingServer.get_video_adapter_api_version(),
		"screen": "%dx%d" % [screen.x, screen.y],
		"window": "%dx%d" % [SettingsManager.window_size.x, SettingsManager.window_size.y],
	}


static func verdict(avg_fps: float, low_fps: float) -> String:
	if avg_fps >= TARGET_AVG_FPS and low_fps >= TARGET_LOW_FPS:
		return "smooth"
	if low_fps >= PLAYABLE_LOW_FPS:
		return "playable"
	return "too slow"


## Turns the stage results into the report (dictionary + Markdown text).
static func build_report(state: Dictionary) -> Dictionary:
	var results: Array = []
	var stage_status := {}
	for r in RENDERERS:
		var st: Dictionary = state.stages.get(r, { "status": "skipped" })
		stage_status[r] = st.status
		results.append_array(st.get("results", []))
	var by_name := {}
	for e: Dictionary in results:
		by_name[e.name] = e
		e["verdict"] = verdict(e.avg_fps, e.low_fps)
	# Option costs relative to their baseline.
	var costs := []
	for e: Dictionary in results:
		var base: Dictionary = by_name.get(e.vs, {})
		if e.vs != "" and not base.is_empty():
			var d: float = e.avg_frame_ms - base.avg_frame_ms
			costs.append({ "name": e.name, "renderer": e.renderer, "delta_ms": snappedf(d, 0.01),
				"delta_pct": snappedf(100.0 * d / maxf(base.avg_frame_ms, 0.01), 0.1) })
	costs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.delta_ms > b.delta_ms)
	# Recommendation: the highest preset that is smooth; else the best playable one.
	var recommended := ""
	for want in ["smooth", "playable"]:
		for i in range(PRESET_NAMES.size() - 1, -1, -1):
			var e: Dictionary = by_name.get(PRESET_NAMES[i], {})
			if not e.is_empty() and e.verdict == want:
				recommended = PRESET_NAMES[i]
				break
		if recommended != "":
			break
	var report := {
		"format": REPORT_FORMAT,
		"date": Time.get_datetime_string_from_system(),
		"quick": state.get("quick", false),
		"system": system_info(),
		"stages": stage_status,
		"maps": MAPS,
		"bots": BOTS,
		"results": results,
		"option_costs": costs,
		"recommended": recommended,
	}
	report["markdown"] = markdown(report)
	return report


static func markdown(r: Dictionary) -> String:
	var s: Dictionary = r.system
	var lines := PackedStringArray()
	lines.append("## Hardware report — %s" % s.gpu)
	lines.append("")
	lines.append("- **GPU:** %s (%s, %s) · driver %s" % [s.gpu, s.gpu_vendor, s.gpu_type, s.driver])
	lines.append("- **CPU:** %s · %d threads · **RAM:** %.1f GB" % [s.cpu, s.threads, s.ram_gb])
	lines.append("- **OS:** %s · screen %s · window %s · game %s" % [s.os, s.screen, s.window, s.game])
	var st: Dictionary = r.stages
	lines.append("- **Renderers:** OpenGL %s · Vulkan %s%s" % [st.get("gl_compatibility", "?"), st.get("forward_plus", "?"),
		" · (quick test)" if r.quick else ""])
	lines.append("")
	lines.append("| Preset | Renderer | Avg FPS | 1% low | Verdict |")
	lines.append("|---|---|---:|---:|---|")
	var names: Array[String] = []
	names.assign(PRESET_NAMES)
	names.append("Low (Vulkan)")
	for e: Dictionary in r.results:
		if e.name in names:
			lines.append("| %s | %s | %.0f | %.0f | %s |" % [e.name, RENDERER_NAMES.get(e.renderer, e.renderer),
				e.avg_fps, e.low_fps, { "smooth": "✔ smooth", "playable": "~ playable", "too slow": "✘ too slow" }[e.verdict]])
	if not r.option_costs.is_empty():
		lines.append("")
		lines.append("| Option | Extra frame time |")
		lines.append("|---|---:|")
		for c: Dictionary in r.option_costs:
			lines.append("| %s | %+.2f ms (%+.0f%%) |" % [c.name, c.delta_ms, c.delta_pct])
	lines.append("")
	lines.append("**Recommended preset:** %s" % (r.recommended if r.recommended != "" else
		"none reaches %d FPS — use Low with Dynamic resolution" % int(PLAYABLE_LOW_FPS)))
	return "\n".join(lines)


## The report for the in-game dialog (real tables instead of Markdown).
static func bbcode(r: Dictionary) -> String:
	var s: Dictionary = r.system
	var st: Dictionary = r.stages
	var out := "[b]%s[/b]\n%s · %d threads · %.1f GB RAM · %s\nOpenGL: %s · Vulkan: %s%s\n\n" % [
		s.gpu, s.cpu, s.threads, s.ram_gb, s.os, st.get("gl_compatibility", "?"), st.get("forward_plus", "?"),
		" · quick test" if r.quick else ""]
	var colors := { "smooth": "#7ddc7d", "playable": "#e8c75a", "too slow": "#ef7a6b" }
	out += "[table=5][cell][b]Preset   [/b][/cell][cell][b]Renderer   [/b][/cell][cell][b]Avg FPS   [/b][/cell][cell][b]1% low   [/b][/cell][cell][b]Verdict[/b][/cell]"
	for e: Dictionary in r.results:
		if e.name in PRESET_NAMES or e.name == "Low (Vulkan)":
			out += "[cell]%s[/cell][cell]%s[/cell][cell]%.0f[/cell][cell]%.0f[/cell][cell][color=%s]%s[/color][/cell]" % [
				e.name, RENDERER_NAMES.get(e.renderer, e.renderer), e.avg_fps, e.low_fps, colors[e.verdict], e.verdict]
	out += "[/table]\n"
	if not r.option_costs.is_empty():
		out += "\n[b]What each option costs on this PC[/b]\n[table=2]"
		for c: Dictionary in r.option_costs:
			out += "[cell]%s   [/cell][cell]%+.1f ms (%+.0f%%)[/cell]" % [c.name, c.delta_ms, c.delta_pct]
		out += "[/table]\n"
	out += "\n[b]Recommended preset: %s[/b]" % (r.recommended if r.recommended != "" else
		"Low with Dynamic resolution (no preset reaches %d FPS)" % int(PLAYABLE_LOW_FPS))
	out += "\n\nSending the report helps tune the presets for PCs like yours."
	return out


static func save_report(report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := DIR + "hardware_report_%s.json" % stamp
	_write_json(path, report)
	var md := FileAccess.open(path.replace(".json", ".md"), FileAccess.WRITE)
	if md:
		md.store_string(report.markdown)
	print("[hardware-test] report saved: %s" % ProjectSettings.globalize_path(path))
	return path


## Pre-filled "Hardware report" issue on GitHub (the report is also copied
## to the clipboard in case the page is too long for a URL).
static func issue_url(report: Dictionary) -> String:
	return "%s?template=hardware_report.yml&title=%s&gpu=%s&report=%s" % [
		BugReport.ISSUES_URL, ("Hardware report: %s" % report.system.gpu).uri_encode(),
		String(report.system.gpu).uri_encode(), String(report.markdown).uri_encode()]


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _restart(renderer: String) -> void:
	_label.text = "Hardware test — restarting with %s…" % RENDERER_NAMES[renderer]
	OS.set_restart_on_exit(true, SettingsManager.restart_args(renderer))
	get_tree().quit.call_deferred()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
