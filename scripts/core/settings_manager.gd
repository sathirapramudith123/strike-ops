extends Node
## Global settings (autoload: SettingsManager).
##
## Owns graphics, display, audio, voice-chat and control settings, saves them to
## user://settings.cfg and applies them at startup. On first launch the graphics
## preset is picked automatically from the detected hardware.
##
## Levels should call apply_to_environment() / apply_to_directional_light() on
## their WorldEnvironment / sun, and listen to graphics_changed to re-apply.

signal graphics_changed(preset: GraphicsPreset)
signal audio_changed
signal voice_changed
signal controls_changed
## Emitted when a setting needs a restart to take effect (e.g. switching renderer).
signal restart_required(reason: String)

const SETTINGS_PATH := "user://settings.cfg"
## Used when running anything under res://tests/ so tests never touch (or
## depend on) the player's real settings.
const TEST_SETTINGS_PATH := "user://settings_test.cfg"
## GPU name → starting preset (see gpu_tier()).
const GPU_TIERS_PATH := "res://resources/settings/gpu_tiers.cfg"
const PRESET_DIR := "res://resources/settings/graphics_presets/"
const PRESET_FILES := {
	GraphicsPreset.Quality.LOW: "low.tres",
	GraphicsPreset.Quality.MEDIUM: "medium.tres",
	GraphicsPreset.Quality.HIGH: "high.tres",
	GraphicsPreset.Quality.ULTRA: "ultra.tres",
}
const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Voice", &"UI"]
const RENDERER_ARG := "--rendering-method"

enum VoiceMode { PUSH_TO_TALK, VOICE_ACTIVATION }

## Actions the player can rebind, in the order shown in Settings → Controls.
## (Pause/Esc is fixed so nobody can lock themselves out of the menu.)
const REMAPPABLE_ACTIONS := {
	&"move_forward": "Move forward", &"move_back": "Move back",
	&"move_left": "Move left", &"move_right": "Move right",
	&"sprint": "Sprint (hold)", &"crouch": "Crouch", &"jump": "Jump", &"slide": "Slide",
	&"lean_left": "Lean left", &"lean_right": "Lean right", &"walk_toggle": "Walk / run toggle",
	&"weapon_1": "Primary weapon", &"weapon_2": "Secondary weapon", &"weapon_3": "Knife",
	&"weapon_4": "Grenades (press again to switch)", &"throw_grenade": "Quick-throw grenade",
	&"weapon_next": "Next weapon / scope zoom in", &"weapon_prev": "Previous weapon / scope zoom out",
	&"reload": "Reload", &"shoot": "Fire", &"aim": "Aim down sights", &"fire_mode": "Switch fire mode",
	&"interact": "Use / pick up / plant / defuse", &"map": "Map", &"buy_menu": "Buy menu (Bomb Defusal)",
	&"chat_all": "Chat (all)", &"chat_team": "Chat (team)",
	&"push_to_talk_team": "Voice chat (team)", &"push_to_talk_proximity": "Voice chat (proximity)",
	&"scoreboard": "Scoreboard", &"toggle_perf_overlay": "Performance overlay",
}

const CROSSHAIR_COLORS := {
	"White": Color(1, 1, 1, 0.9), "Green": Color(0.3, 1, 0.4, 0.95), "Yellow": Color(1, 0.9, 0.2, 0.95),
	"Cyan": Color(0.3, 0.95, 1, 0.95), "Red": Color(1, 0.3, 0.3, 0.95), "Magenta": Color(1, 0.35, 1, 0.95),
}

## Currently active graphics settings (a copy — safe to edit for "Custom").
var graphics: GraphicsPreset

# Display
var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN
var vsync: bool = true
var max_fps: int = 0 # 0 = unlimited
var field_of_view: float = 90.0
var show_perf_overlay: bool = false
## Window size used in windowed mode.
var window_size: Vector2i = Vector2i(1280, 720)
## 0.5..1.5, applied through the level's Environment.
var brightness: float = 1.0
## Lower the 3D resolution automatically to hold the target FPS (in matches).
var dynamic_resolution: bool = true
var dynamic_resolution_target_fps: int = 60

# Audio (linear 0..1 per bus)
var bus_volumes: Dictionary = {
	&"Master": 1.0, &"Music": 0.6, &"SFX": 0.9, &"Voice": 1.0, &"UI": 0.8,
}
## 0 = Low (16 sounds at once, no reverb), 1 = High (40 sounds, reverb +
## continuous occlusion). Low-end PCs get Low on first launch.
var audio_quality: int = 1
## Quiet background music during matches (menu music is always on).
var match_music: bool = true
## Hit marker / headshot / kill confirmation sounds.
var hit_sounds: bool = true

# Voice chat
var voice_enabled: bool = true
var voice_mode: VoiceMode = VoiceMode.PUSH_TO_TALK
var voice_activation_threshold: float = 0.05 # linear peak 0..1
var voice_input_device: String = "Default"
var mic_volume: float = 1.0
var proximity_chat_enabled: bool = true
## Noise gate + automatic gain control on the microphone.
var voice_processing: bool = true
## Send voice with Opus when everyone in the match supports it (else ADPCM).
var voice_opus: bool = true

# Controls
var mouse_sensitivity: float = 0.15
var invert_y: bool = false
## Extra multiplier on top of each weapon's own ADS sensitivity.
var ads_sensitivity_scale: float = 1.0
## Toggle instead of hold (accessibility).
var aim_toggle: bool = false
var crouch_toggle: bool = false

# Controller (see GamepadInput)
## Look speed at full stick tilt, degrees per second.
var pad_sensitivity: float = 180.0
var pad_invert_y: bool = false
var pad_deadzone: float = 0.15
## GamepadInput.RESPONSE_CURVES index (0 Linear, 1 Default, 2 Precise).
var pad_curve: int = 1
## Look slows down while the crosshair is on an enemy (controller only).
var aim_assist: bool = true
var vibration: bool = true

# Gameplay / HUD
var crosshair_color_name: String = "White"
var crosshair_size: float = 1.0
var crosshair_dot: bool = true

# Multiplayer
var player_name: String = "Player"
var last_join_address: String = "127.0.0.1"
var host_port: int = 7777
var host_mode: int = 1 # GameConfig.Mode.FFA
var selected_map: String = "res://scenes/levels/test_map.tscn"
## Primary weapon id for the loadout (see GameConfig.PRIMARY_WEAPONS).
var preferred_primary: String = "rifle"

var settings_path: String = SETTINGS_PATH

var _config := ConfigFile.new()
## action -> Array[InputEvent] as defined in project.godot (for "Reset").
var _default_bindings: Dictionary = {}
## Version of the default key layout. Settings files from an older layout
## saved every key; their keyboard keys are dropped once so the new defaults
## apply (controller bindings are kept). Since layout 2 only keys that
## differ from the defaults are saved.
const BINDINGS_LAYOUT := 2


func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			settings_path = TEST_SETTINGS_PATH
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	GamepadInput.install_defaults()
	for action: StringName in REMAPPABLE_ACTIONS:
		_default_bindings[action] = InputMap.action_get_events(action).map(func(e: InputEvent) -> InputEvent: return e.duplicate())
	var first_launch := _config.load(settings_path) != OK
	_load_all(first_launch)
	if first_launch:
		save()
	apply_all()
	_ensure_renderer_matches()
	# `-- --benchmark` runs the built-in benchmark (see BenchmarkRunner).
	var bench := BenchmarkRunner.from_args(OS.get_cmdline_user_args())
	if bench:
		get_tree().root.add_child.call_deferred(bench)
	# Full hardware test: `-- --hardware-test`, or continuing after its restart.
	# (Never inside test runs or on a dedicated server.)
	var server_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if settings_path != TEST_SETTINGS_PATH and not OS.has_feature("dedicated_server") and not "--server" in server_args:
		if "--hardware-test" in OS.get_cmdline_user_args() and not HardwareTest.is_running():
			HardwareTest.start("--quick" in OS.get_cmdline_user_args())
		else:
			var test := HardwareTest.resume_if_pending()
			if test:
				get_tree().root.add_child.call_deferred(test)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func apply_all() -> void:
	apply_bindings()
	apply_display()
	apply_graphics()
	apply_audio()
	apply_voice()


## Switches to one of the built-in presets and applies it.
func set_graphics_quality(quality: GraphicsPreset.Quality) -> void:
	var previous_method := graphics.rendering_method if graphics else ""
	graphics = load_preset(quality)
	apply_graphics()
	save()
	if previous_method != "" and previous_method != graphics.rendering_method:
		restart_required.emit("Renderer changed to %s." % graphics.rendering_method)


## Marks the current graphics settings as custom after the player edits a value.
func mark_graphics_custom() -> void:
	graphics.quality = GraphicsPreset.Quality.CUSTOM
	graphics.display_name = "Custom"
	apply_graphics()
	save()


static func load_preset(quality: GraphicsPreset.Quality) -> GraphicsPreset:
	var file: String = PRESET_FILES.get(quality, PRESET_FILES[GraphicsPreset.Quality.MEDIUM])
	var preset := load(PRESET_DIR + file) as GraphicsPreset
	return preset.duplicate() as GraphicsPreset


## True when the project asked for Forward+ (Vulkan) but the driver couldn't
## provide it and Godot fell back to the Compatibility renderer.
static func vulkan_fallback_happened() -> bool:
	var wanted: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	var forced := RENDERER_ARG in OS.get_cmdline_args()
	return wanted == "forward_plus" and not forced \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility" \
		and DisplayServer.get_name() != "headless"


## Preset for a GPU name from GPU_TIERS_PATH, or -1 if it isn't listed.
static func gpu_tier(adapter_name: String, path: String = GPU_TIERS_PATH) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return -1
	var gpu := normalize_gpu_name(adapter_name)
	for pattern in cfg.get_sections():
		if pattern in gpu:
			return ["low", "medium", "high", "ultra"].find(str(cfg.get_value(pattern, "preset", "")).to_lower())
	return -1


## "Mesa Intel(R) UHD Graphics 620 (KBL GT2)" → "intel uhd graphics 620", so one
## entry matches the same GPU on every OS/driver. Keep in sync with
## normalize_gpu() in tools/tune_presets.py.
static func normalize_gpu_name(adapter_name: String) -> String:
	var s := adapter_name.to_lower().replace("(r)", "").replace("(tm)", "").get_slice("/", 0)
	var trailing := RegEx.create_from_string("\\s*\\([^()]*\\)\\s*$")
	var before := ""
	while before != s:
		before = s
		s = trailing.sub(s, "")
	s = s.strip_edges().trim_prefix("mesa ")
	return RegEx.create_from_string("\\s+").sub(s, " ", true).strip_edges()


## Picks a sensible starting preset from the hardware (used on first launch).
static func detect_recommended_quality() -> GraphicsPreset.Quality:
	var adapter_type := RenderingServer.get_video_adapter_type()
	var ram_gb := float(OS.get_memory_info().get("physical", 0)) / (1024.0 * 1024.0 * 1024.0)
	var cores := OS.get_processor_count()

	if adapter_type in [RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU]:
		return GraphicsPreset.Quality.LOW
	# Software rendering (no real GPU driver).
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	for soft in ["llvmpipe", "softpipe", "swiftshader", "software", "microsoft basic render"]:
		if soft in adapter:
			return GraphicsPreset.Quality.LOW
	# Vulkan unavailable: Godot fell back to OpenGL, so only Low is a good fit
	# (the other presets are tuned for Forward+).
	if vulkan_fallback_happened():
		return GraphicsPreset.Quality.LOW
	# Measured / known GPUs (resources/settings/gpu_tiers.cfg, from hardware reports).
	var tier := gpu_tier(adapter)
	if tier >= 0:
		return tier as GraphicsPreset.Quality
	if adapter_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return GraphicsPreset.Quality.LOW if ram_gb < 7.5 else GraphicsPreset.Quality.MEDIUM
	if ram_gb > 0.0 and ram_gb < 7.5 or cores <= 2:
		return GraphicsPreset.Quality.MEDIUM
	# Discrete GPU: stay conservative, players can raise it to Ultra themselves.
	return GraphicsPreset.Quality.HIGH


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(window_mode)
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen := DisplayServer.screen_get_size()
		var size := Vector2i(mini(window_size.x, screen.x), mini(window_size.y, screen.y))
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


func apply_graphics() -> void:
	var vp := get_viewport()
	var g := graphics
	var is_compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"

	vp.scaling_3d_scale = g.render_scale
	# FSR is not available in the Compatibility renderer.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if is_compat else g.scaling_mode
	vp.fsr_sharpness = g.fsr_sharpness
	vp.msaa_3d = g.msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if g.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = g.taa and not is_compat
	vp.texture_mipmap_bias = g.texture_mipmap_bias
	vp.mesh_lod_threshold = g.mesh_lod_threshold
	vp.positional_shadow_atlas_size = g.positional_shadow_atlas_size if g.shadows_enabled else 0

	RenderingServer.directional_shadow_atlas_set_size(g.directional_shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(g.shadow_filter_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(g.shadow_filter_quality)
	RenderingServer.global_shader_parameter_set(&"surface_detail", 1.0 if g.surface_detail else 0.0)

	graphics_changed.emit(g)


## Applies post-processing toggles to a level's Environment resource.
func apply_to_environment(env: Environment) -> void:
	if env == null:
		return
	var g := graphics
	env.ssao_enabled = g.ssao
	env.ssil_enabled = g.ssil
	env.ssr_enabled = g.ssr
	env.sdfgi_enabled = g.sdfgi
	env.glow_enabled = g.glow
	env.volumetric_fog_enabled = g.volumetric_fog
	env.adjustment_enabled = not is_equal_approx(brightness, 1.0)
	env.adjustment_brightness = brightness


## Applies shadow settings to a level's main DirectionalLight3D (the sun).
func apply_to_directional_light(light: DirectionalLight3D) -> void:
	if light == null:
		return
	light.shadow_enabled = graphics.shadows_enabled
	match graphics.directional_shadow_cascades:
		1:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		2, 3:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 100.0 * graphics.draw_distance_scale


## Applies depth-of-field (Ultra) to a camera's CameraAttributes.
func apply_to_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.fov = field_of_view
	var attrs := camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_enabled = graphics.depth_of_field
	camera.far = 500.0 * graphics.draw_distance_scale


func set_bus_volume(bus: StringName, linear: float) -> void:
	bus_volumes[bus] = clampf(linear, 0.0, 1.0)
	apply_audio()
	save()


func apply_audio() -> void:
	for bus: StringName in AUDIO_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var linear: float = bus_volumes.get(bus, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.0)
	audio_changed.emit()


func apply_voice() -> void:
	if voice_input_device in AudioServer.get_input_device_list():
		AudioServer.input_device = voice_input_device
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	if voice_bus >= 0:
		AudioServer.set_bus_mute(voice_bus, not voice_enabled or bus_volumes[&"Voice"] <= 0.0)
	voice_changed.emit()


func save() -> void:
	_config.set_value("graphics", "quality", graphics.quality)
	if graphics.quality == GraphicsPreset.Quality.CUSTOM:
		for prop in _graphics_property_names():
			_config.set_value("graphics_custom", prop, graphics.get(prop))
	elif _config.has_section("graphics_custom"):
		_config.erase_section("graphics_custom")

	_config.set_value("display", "window_mode", window_mode)
	_config.set_value("display", "vsync", vsync)
	_config.set_value("display", "max_fps", max_fps)
	_config.set_value("display", "field_of_view", field_of_view)
	_config.set_value("display", "show_perf_overlay", show_perf_overlay)
	_config.set_value("display", "window_size", window_size)
	_config.set_value("display", "brightness", brightness)
	_config.set_value("display", "dynamic_resolution", dynamic_resolution)
	_config.set_value("display", "dynamic_resolution_target_fps", dynamic_resolution_target_fps)

	for bus: StringName in AUDIO_BUSES:
		_config.set_value("audio", String(bus).to_lower(), bus_volumes[bus])
	_config.set_value("audio", "quality", audio_quality)
	_config.set_value("audio", "match_music", match_music)
	_config.set_value("audio", "hit_sounds", hit_sounds)

	_config.set_value("voice", "enabled", voice_enabled)
	_config.set_value("voice", "mode", voice_mode)
	_config.set_value("voice", "activation_threshold", voice_activation_threshold)
	_config.set_value("voice", "input_device", voice_input_device)
	_config.set_value("voice", "mic_volume", mic_volume)
	_config.set_value("voice", "proximity_chat", proximity_chat_enabled)
	_config.set_value("voice", "processing", voice_processing)
	_config.set_value("voice", "opus", voice_opus)

	_config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	_config.set_value("controls", "invert_y", invert_y)
	_config.set_value("controls", "ads_sensitivity_scale", ads_sensitivity_scale)
	_config.set_value("controls", "aim_toggle", aim_toggle)
	_config.set_value("controls", "crouch_toggle", crouch_toggle)
	for p in ["pad_sensitivity", "pad_invert_y", "pad_deadzone", "pad_curve", "aim_assist", "vibration"]:
		_config.set_value("controller", p, get(p))
	_config.set_value("gameplay", "crosshair_color", crosshair_color_name)
	_config.set_value("gameplay", "crosshair_size", crosshair_size)
	_config.set_value("gameplay", "crosshair_dot", crosshair_dot)
	_save_bindings()

	_config.set_value("network", "player_name", player_name)
	_config.set_value("network", "last_join_address", last_join_address)
	_config.set_value("network", "host_port", host_port)
	_config.set_value("network", "host_mode", host_mode)
	_config.set_value("network", "selected_map", selected_map)
	_config.set_value("controls", "preferred_primary", preferred_primary)

	var err := _config.save(settings_path)
	if err != OK:
		push_error("SettingsManager: failed to save settings (%s)" % error_string(err))


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _load_all(first_launch: bool) -> void:
	var quality: int = detect_recommended_quality() if first_launch \
		else _config.get_value("graphics", "quality", GraphicsPreset.Quality.MEDIUM)
	if quality == GraphicsPreset.Quality.CUSTOM:
		graphics = load_preset(GraphicsPreset.Quality.MEDIUM)
		for prop in _graphics_property_names():
			if _config.has_section_key("graphics_custom", prop):
				graphics.set(prop, _config.get_value("graphics_custom", prop))
		graphics.quality = GraphicsPreset.Quality.CUSTOM
		graphics.display_name = "Custom"
	else:
		graphics = load_preset(quality)

	window_mode = _config.get_value("display", "window_mode", window_mode)
	vsync = _config.get_value("display", "vsync", vsync)
	max_fps = _config.get_value("display", "max_fps", max_fps)
	field_of_view = _config.get_value("display", "field_of_view", field_of_view)
	show_perf_overlay = _config.get_value("display", "show_perf_overlay", show_perf_overlay)

	for bus: StringName in AUDIO_BUSES:
		bus_volumes[bus] = _config.get_value("audio", String(bus).to_lower(), bus_volumes[bus])
	if first_launch and quality == GraphicsPreset.Quality.LOW:
		audio_quality = 0
	audio_quality = clampi(_config.get_value("audio", "quality", audio_quality), 0, 1)
	match_music = _config.get_value("audio", "match_music", match_music)
	hit_sounds = _config.get_value("audio", "hit_sounds", hit_sounds)

	voice_enabled = _config.get_value("voice", "enabled", voice_enabled)
	voice_mode = _config.get_value("voice", "mode", voice_mode)
	voice_activation_threshold = _config.get_value("voice", "activation_threshold", voice_activation_threshold)
	voice_input_device = _config.get_value("voice", "input_device", voice_input_device)
	mic_volume = _config.get_value("voice", "mic_volume", mic_volume)
	proximity_chat_enabled = _config.get_value("voice", "proximity_chat", proximity_chat_enabled)
	voice_processing = _config.get_value("voice", "processing", voice_processing)
	voice_opus = _config.get_value("voice", "opus", voice_opus)

	mouse_sensitivity = _config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = _config.get_value("controls", "invert_y", invert_y)
	ads_sensitivity_scale = _config.get_value("controls", "ads_sensitivity_scale", ads_sensitivity_scale)
	aim_toggle = _config.get_value("controls", "aim_toggle", aim_toggle)
	crouch_toggle = _config.get_value("controls", "crouch_toggle", crouch_toggle)
	for p in ["pad_sensitivity", "pad_invert_y", "pad_deadzone", "pad_curve", "aim_assist", "vibration"]:
		set(p, _config.get_value("controller", p, get(p)))
	pad_curve = clampi(pad_curve, 0, GamepadInput.RESPONSE_CURVES.size() - 1)
	crosshair_color_name = _config.get_value("gameplay", "crosshair_color", crosshair_color_name)
	crosshair_size = _config.get_value("gameplay", "crosshair_size", crosshair_size)
	crosshair_dot = _config.get_value("gameplay", "crosshair_dot", crosshair_dot)
	window_size = _config.get_value("display", "window_size", window_size)
	brightness = _config.get_value("display", "brightness", brightness)
	dynamic_resolution = _config.get_value("display", "dynamic_resolution", dynamic_resolution)
	dynamic_resolution_target_fps = _config.get_value("display", "dynamic_resolution_target_fps", dynamic_resolution_target_fps)

	player_name = _config.get_value("network", "player_name", player_name)
	last_join_address = _config.get_value("network", "last_join_address", last_join_address)
	host_port = _config.get_value("network", "host_port", host_port)
	host_mode = _config.get_value("network", "host_mode", host_mode)
	selected_map = _config.get_value("network", "selected_map", selected_map)
	preferred_primary = _config.get_value("controls", "preferred_primary", preferred_primary)


## The renderer can only be chosen at startup. If the saved preset wants a
## different renderer than the one running, restart once with the right one.
func _ensure_renderer_matches() -> void:
	var wanted := graphics.rendering_method
	var current := RenderingServer.get_current_rendering_method()
	if wanted == current:
		return
	# Never restart from the editor, headless runs, or if we already tried
	# (e.g. Vulkan unsupported and Godot fell back to OpenGL) — avoids loops.
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless" \
			or RENDERER_ARG in OS.get_cmdline_args():
		return
	restart_game()


## Restarts the game using the renderer required by the current preset.
func restart_game() -> void:
	OS.set_restart_on_exit(true, restart_args(graphics.rendering_method))
	get_tree().quit.call_deferred()


## Command line for restarting with `renderer`. User arguments (after `--`,
## e.g. --hardware-test) are dropped on purpose. Godot consumes `--path`, so
## it is added back when running from source with the editor binary.
static func restart_args(renderer: String) -> PackedStringArray:
	var args := PackedStringArray()
	var skip_next := false
	for arg in OS.get_cmdline_args():
		if skip_next:
			skip_next = false
		elif arg == RENDERER_ARG:
			skip_next = true
		else:
			args.append(arg)
	if OS.has_feature("editor") and not "--path" in args:
		args.append_array(["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")])
	args.append_array([RENDERER_ARG, renderer])
	return args


func _graphics_property_names() -> PackedStringArray:
	var names := PackedStringArray()
	for p in graphics.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.name not in ["quality", "display_name"]:
			names.append(p.name)
	return names


# -----------------------------------------------------------------------------
# Key bindings
# -----------------------------------------------------------------------------

func crosshair_color() -> Color:
	return CROSSHAIR_COLORS.get(crosshair_color_name, CROSSHAIR_COLORS["White"])


## The (first) event bound to `action`, or null.
## The keyboard / mouse binding of `action` (null = none).
func get_binding(action: StringName) -> InputEvent:
	return _binding_of_kind(action, false)


## The controller binding of `action` (null = none).
func get_pad_binding(action: StringName) -> InputEvent:
	return _binding_of_kind(action, true)


func pad_binding_text(action: StringName) -> String:
	return GamepadInput.event_text(get_pad_binding(action))


## Keyboard or controller name, whichever the player is using right now.
func prompt_text(action: StringName) -> String:
	if GamepadInput.using_pad and get_pad_binding(action):
		return pad_binding_text(action)
	return binding_text(action)


func _binding_of_kind(action: StringName, pad: bool) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if GamepadInput.is_pad_event(e) == pad:
			return e
	return null


## Replaces the binding of one kind (keyboard/mouse or controller) only.
func _set_binding(action: StringName, pad: bool, event: InputEvent) -> void:
	for e in InputMap.action_get_events(action):
		if GamepadInput.is_pad_event(e) == pad:
			InputMap.action_erase_event(action, e)
	if event:
		InputMap.action_add_event(action, event)


## Human-readable name of the key / button bound to `action`.
func binding_text(action: StringName) -> String:
	return event_text(get_binding(action))


static func event_text(e: InputEvent) -> String:
	if e == null:
		return "—"
	if GamepadInput.is_pad_event(e):
		return GamepadInput.event_text(e)
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.physical_keycode == KEY_NONE:
			return OS.get_keycode_string(k.keycode)
		# Show the label of the player's keyboard layout (e.g. AZERTY) when known.
		var shown := KEY_NONE
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return OS.get_keycode_string(shown if shown != KEY_NONE else k.physical_keycode)
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			var b: return "Mouse %d" % b
	return e.as_text()


## Binds `event` to `action`. If another remappable action already uses the
## same key, the two actions swap keys. Returns that other action (or &"").
func rebind(action: StringName, event: InputEvent) -> StringName:
	var pad := GamepadInput.is_pad_event(event)
	var clean := GamepadInput.clean(event) if pad else _clean_event(event)
	if clean == null or not REMAPPABLE_ACTIONS.has(action):
		return &""
	# Only bindings of the same kind are touched (keyboard vs controller).
	var previous := _binding_of_kind(action, pad)
	var swapped: StringName = &""
	for other: StringName in REMAPPABLE_ACTIONS:
		if other != action and _same_input(_binding_of_kind(other, pad), clean):
			swapped = other
			_set_binding(other, pad, previous)
	_set_binding(action, pad, clean)
	save()
	controls_changed.emit()
	return swapped


func reset_bindings() -> void:
	for action: StringName in _default_bindings:
		InputMap.action_erase_events(action)
		for e: InputEvent in _default_bindings[action]:
			InputMap.action_add_event(action, e.duplicate())
	save()
	controls_changed.emit()


## Re-applies the saved bindings to the InputMap (startup).
func apply_bindings() -> void:
	if int(_config.get_value("bindings_meta", "layout", 1)) < BINDINGS_LAYOUT:
		if _config.has_section("bindings"):
			_config.erase_section("bindings")
		_config.set_value("bindings_meta", "layout", BINDINGS_LAYOUT)
	for action: StringName in REMAPPABLE_ACTIONS:
		# (has_section_key first: get_value(..., null) counts as "no default"
		# and logs an error for actions newer than the saved settings file.)
		if _config.has_section_key("bindings", String(action)):
			var e := _deserialize_event(_config.get_value("bindings", String(action)))
			if e:
				_set_binding(action, false, e)
		if not _config.has_section_key("pad_bindings", String(action)):
			continue
		var data: Variant = _config.get_value("pad_bindings", String(action))
		if data is Dictionary:
			# {} = deliberately unbound on the controller.
			_set_binding(action, true, GamepadInput.deserialize(data))


## Saves only the keys and buttons that differ from the defaults, so a new
## default layout reaches everyone who didn't change that action.
func _save_bindings() -> void:
	_config.set_value("bindings_meta", "layout", BINDINGS_LAYOUT)
	for action: StringName in REMAPPABLE_ACTIONS:
		var e := get_binding(action)
		var key: Dictionary = _serialize_event(e) if e else {}
		var def_key := _default_of_kind(action, false)
		if key == (_serialize_event(def_key) if def_key else {}):
			if _config.has_section_key("bindings", String(action)):
				_config.erase_section_key("bindings", String(action))
		else:
			_config.set_value("bindings", String(action), key)
		var p := get_pad_binding(action)
		var pad: Dictionary = GamepadInput.serialize(p) if p else {}
		var def := _default_of_kind(action, true)
		if pad == (GamepadInput.serialize(def) if def else {}):
			if _config.has_section_key("pad_bindings", String(action)):
				_config.erase_section_key("pad_bindings", String(action))
		else:
			_config.set_value("pad_bindings", String(action), pad)


## The default (project.godot / GamepadInput) keyboard or controller event of `action`.
func _default_of_kind(action: StringName, pad: bool) -> InputEvent:
	for e: InputEvent in _default_bindings.get(action, []):
		if GamepadInput.is_pad_event(e) == pad:
			return e
	return null


static func _serialize_event(e: InputEvent) -> Dictionary:
	if GamepadInput.is_pad_event(e):
		return GamepadInput.serialize(e)
	if e is InputEventKey:
		var k := e as InputEventKey
		return { "type": "key", "code": k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode,
			"physical": k.physical_keycode != KEY_NONE }
	if e is InputEventMouseButton:
		return { "type": "mouse", "button": (e as InputEventMouseButton).button_index }
	return {}


static func _deserialize_event(data: Variant) -> InputEvent:
	if not data is Dictionary:
		return null
	match data.get("type", ""):
		"key":
			var k := InputEventKey.new()
			if data.get("physical", true):
				k.physical_keycode = data.code
			else:
				k.keycode = data.code
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = data.button
			return m
	return null


## Strips modifiers/pressed state so the event matches like the defaults do.
static func _clean_event(e: InputEvent) -> InputEvent:
	if e is InputEventKey:
		var k := InputEventKey.new()
		var src := e as InputEventKey
		# Bind by physical position (like the defaults), so layouts don't matter.
		k.physical_keycode = src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
		return k
	if e is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = (e as InputEventMouseButton).button_index
		return m
	return null


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	return _serialize_event(a) == _serialize_event(b)


## Remembers whether the player is on a controller or keyboard/mouse
## (rumble, button prompts).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		GamepadInput.using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton \
			or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0):
		GamepadInput.using_pad = false
