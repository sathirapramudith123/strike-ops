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

## Currently active graphics settings (a copy — safe to edit for "Custom").
var graphics: GraphicsPreset

# Display
var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN
var vsync: bool = true
var max_fps: int = 0 # 0 = unlimited
var field_of_view: float = 90.0
var show_perf_overlay: bool = false

# Audio (linear 0..1 per bus)
var bus_volumes: Dictionary = {
	&"Master": 1.0, &"Music": 0.6, &"SFX": 0.9, &"Voice": 1.0, &"UI": 0.8,
}

# Voice chat
var voice_enabled: bool = true
var voice_mode: VoiceMode = VoiceMode.PUSH_TO_TALK
var voice_activation_threshold: float = 0.05 # linear peak 0..1
var voice_input_device: String = "Default"
var mic_volume: float = 1.0
var proximity_chat_enabled: bool = true
## Noise gate + automatic gain control on the microphone.
var voice_processing: bool = true

# Controls
var mouse_sensitivity: float = 0.15
var invert_y: bool = false

# Multiplayer
var player_name: String = "Player"
var last_join_address: String = "127.0.0.1"
var host_port: int = 7777
var host_mode: int = 1 # GameConfig.Mode.FFA
var selected_map: String = "res://scenes/levels/test_map.tscn"
## Primary weapon id for the loadout (see GameConfig.PRIMARY_WEAPONS).
var preferred_primary: String = "rifle"

var _config := ConfigFile.new()


func _ready() -> void:
	var first_launch := _config.load(SETTINGS_PATH) != OK
	_load_all(first_launch)
	if first_launch:
		save()
	apply_all()
	_ensure_renderer_matches()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func apply_all() -> void:
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


## Picks a sensible starting preset from the hardware (used on first launch).
static func detect_recommended_quality() -> GraphicsPreset.Quality:
	var adapter_type := RenderingServer.get_video_adapter_type()
	var ram_gb := float(OS.get_memory_info().get("physical", 0)) / (1024.0 * 1024.0 * 1024.0)
	var cores := OS.get_processor_count()

	if adapter_type in [RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU]:
		return GraphicsPreset.Quality.LOW
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

	for bus: StringName in AUDIO_BUSES:
		_config.set_value("audio", String(bus).to_lower(), bus_volumes[bus])

	_config.set_value("voice", "enabled", voice_enabled)
	_config.set_value("voice", "mode", voice_mode)
	_config.set_value("voice", "activation_threshold", voice_activation_threshold)
	_config.set_value("voice", "input_device", voice_input_device)
	_config.set_value("voice", "mic_volume", mic_volume)
	_config.set_value("voice", "proximity_chat", proximity_chat_enabled)
	_config.set_value("voice", "processing", voice_processing)

	_config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	_config.set_value("controls", "invert_y", invert_y)

	_config.set_value("network", "player_name", player_name)
	_config.set_value("network", "last_join_address", last_join_address)
	_config.set_value("network", "host_port", host_port)
	_config.set_value("network", "host_mode", host_mode)
	_config.set_value("network", "selected_map", selected_map)
	_config.set_value("controls", "preferred_primary", preferred_primary)

	var err := _config.save(SETTINGS_PATH)
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

	voice_enabled = _config.get_value("voice", "enabled", voice_enabled)
	voice_mode = _config.get_value("voice", "mode", voice_mode)
	voice_activation_threshold = _config.get_value("voice", "activation_threshold", voice_activation_threshold)
	voice_input_device = _config.get_value("voice", "input_device", voice_input_device)
	mic_volume = _config.get_value("voice", "mic_volume", mic_volume)
	proximity_chat_enabled = _config.get_value("voice", "proximity_chat", proximity_chat_enabled)
	voice_processing = _config.get_value("voice", "processing", voice_processing)

	mouse_sensitivity = _config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = _config.get_value("controls", "invert_y", invert_y)

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
	var args := PackedStringArray()
	var skip_next := false
	for arg in OS.get_cmdline_args():
		if skip_next:
			skip_next = false
		elif arg == RENDERER_ARG:
			skip_next = true
		else:
			args.append(arg)
	args.append_array([RENDERER_ARG, graphics.rendering_method])
	OS.set_restart_on_exit(true, args)
	get_tree().quit.call_deferred()


func _graphics_property_names() -> PackedStringArray:
	var names := PackedStringArray()
	for p in graphics.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.name not in ["quality", "display_name"]:
			names.append(p.name)
	return names
