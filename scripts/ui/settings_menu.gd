class_name SettingsMenu
extends Control
## Full settings screen, shared by the main menu and the in-game Esc menu.
##
## Tabs: Graphics (preset + every option — editing one makes it "Custom"),
## Display, Audio, Voice, Controls (incl. key remapping) and Gameplay.
## Every change is applied and saved immediately (SettingsManager).
## The rows are built in code, so adding a setting is one line below.

@warning_ignore_start("static_called_on_instance") # static helpers on autoloads (NetworkManager, SettingsManager…)
signal closed

const TAB_NAMES: PackedStringArray = ["Graphics", "Display", "Audio", "Voice", "Controls", "Gameplay"]
const FPS_CAPS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const WINDOW_MODES := {
	"Windowed": DisplayServer.WINDOW_MODE_WINDOWED,
	"Borderless fullscreen": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"Exclusive fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
}

@onready var _tabs: TabContainer = %Tabs
@onready var _status: Label = %Status
@onready var _restart_button: Button = %RestartButton

var _mic_bar: ProgressBar
## Action currently waiting for a key press (&"" = none).
var _capturing: StringName = &""
var _binding_buttons: Dictionary = {} # action -> Button
var _pad_buttons: Dictionary = {} # action -> Button (controller column)
var _capturing_pad: bool = false
var _capture_started_ms: int = 0


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%ResetButton.pressed.connect(_reset_current_tab)
	_restart_button.pressed.connect(SettingsManager.restart_game)
	_restart_button.visible = false
	SettingsManager.restart_required.connect(func(reason: String) -> void:
		_status.text = "%s Restart to apply." % reason
		_restart_button.visible = true)
	for tab_name in TAB_NAMES:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.name = "Grid"
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override(&"h_separation", 24)
		grid.add_theme_constant_override(&"v_separation", 8)
		scroll.add_child(grid)
		_tabs.add_child(scroll)
	_build_all()
	visibility_changed.connect(_on_visibility_changed)
	_tabs.tab_changed.connect(func(_i: int) -> void:
		if _capturing != &"":
			_cancel_capture()
			_status.text = "")


func open() -> void:
	show()
	_build_all()
	_status.text = ""
	_tabs.get_tab_bar().grab_focus()


func close() -> void:
	_cancel_capture()
	hide()
	SettingsManager.save()
	closed.emit()


## Controller B / Esc goes back (unless a binding is being captured).
func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and _capturing == &"" and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _mic_bar and is_visible_in_tree():
		_mic_bar.value = VoiceChat.input_level


func _on_visibility_changed() -> void:
	# Run the microphone while the settings are open so the level meter works.
	VoiceChat.monitoring = visible
	if not visible:
		VoiceChat.loopback = false


# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

func _build_all() -> void:
	_binding_buttons.clear()
	_mic_bar = null
	for tab_name in TAB_NAMES:
		var grid := _grid(tab_name)
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_build_graphics()
	_build_display()
	_build_audio()
	_build_voice()
	_build_controls()
	_build_gameplay()


func _grid(tab_name: String) -> GridContainer:
	return _tabs.get_node(tab_name).get_node("Grid") as GridContainer


func _build_graphics() -> void:
	var t := "Graphics"
	var g := SettingsManager.graphics
	var names: Array[String] = ["Low", "Medium", "High", "Ultra", "Custom"]
	var q: int = g.quality
	_add_option(t, "Quality preset", names, q, func(i: int) -> void:
		if i < 4:
			SettingsManager.set_graphics_quality(i as GraphicsPreset.Quality)
			_status.text = "%s preset applied." % names[i]
			_build_all())
	_add_button(t, "", "Run benchmark (≈30 s, uses the current settings)", func() -> void:
		close()
		var bench := BenchmarkRunner.new()
		bench.duration = 8.0
		get_tree().root.add_child(bench))
	_add_button(t, "", "Full hardware test (≈5 min, restarts the game once)", func() -> void:
		close()
		HardwareTest.start())
	_add_button(t, "", "Auto-detect for this PC", func() -> void:
		var best := SettingsManager.detect_recommended_quality()
		SettingsManager.set_graphics_quality(best)
		_status.text = "Detected: %s." % names[best]
		_build_all())

	_add_section(t, "Rendering")
	_gfx_option(t, "Renderer", "rendering_method", ["Compatibility (OpenGL — fastest)", "Forward+ (Vulkan)"],
		["gl_compatibility", "forward_plus"], true)
	_gfx_slider(t, "Render scale", "render_scale", 0.5, 1.0, 0.05, "%d%%", 100.0)
	_add_check(t, "Dynamic resolution (holds target FPS)", SettingsManager.dynamic_resolution, func(on: bool) -> void:
		SettingsManager.dynamic_resolution = on
		SettingsManager.graphics_changed.emit(SettingsManager.graphics)
		SettingsManager.save())
	var targets: Array[int] = [30, 60, 90, 120, 144]
	_add_option(t, "Target FPS", targets.map(func(v: int) -> String: return str(v)),
		maxi(targets.find(SettingsManager.dynamic_resolution_target_fps), 1), func(i: int) -> void:
			SettingsManager.dynamic_resolution_target_fps = targets[i]
			SettingsManager.save())
	_gfx_option(t, "Upscaler", "scaling_mode", ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2 (Forward+)"], [0, 1, 2])
	_gfx_option(t, "MSAA", "msaa", ["Off", "2×", "4×", "8×"], [0, 1, 2, 3])
	_gfx_check(t, "FXAA", "fxaa")
	_gfx_check(t, "TAA (Forward+)", "taa")

	_add_section(t, "Detail")
	_gfx_option(t, "Texture detail", "texture_mipmap_bias", ["Low", "Medium", "High", "Ultra"], [1.0, 0.5, 0.0, -0.5])
	_gfx_option(t, "Model detail (LOD)", "mesh_lod_threshold", ["Low", "Medium", "High", "Ultra"], [4.0, 2.0, 1.0, 0.5])
	_gfx_slider(t, "Draw distance", "draw_distance_scale", 0.25, 1.5, 0.05, "%d%%", 100.0)
	_gfx_slider(t, "Foliage density", "foliage_density", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_gfx_slider(t, "Particles", "particle_amount", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_gfx_check(t, "Surface detail (procedural materials)", "surface_detail")
	_gfx_check(t, "Map detail (sky, skyline, props)", "map_detail")
	_gfx_check(t, "Realistic soldiers (next round)", "realistic_characters")

	_add_section(t, "Shadows")
	_gfx_check(t, "Shadows", "shadows_enabled")
	_gfx_option(t, "Shadow resolution", "directional_shadow_size", ["512", "1024", "2048", "4096"], [512, 1024, 2048, 4096])
	_gfx_option(t, "Shadow filtering", "shadow_filter_quality", ["Hard", "Very low", "Low", "Medium", "High", "Ultra"], [0, 1, 2, 3, 4, 5])
	_gfx_option(t, "Shadow cascades", "directional_shadow_cascades", ["1", "2", "4"], [1, 2, 4])

	_add_section(t, "Lights")
	_gfx_check(t, "Dynamic lights (lamps, muzzle flash)", "dynamic_lights")

	_add_section(t, "Effects (Forward+)")
	_gfx_check(t, "Ambient occlusion (SSAO)", "ssao")
	_gfx_check(t, "Indirect lighting (SSIL)", "ssil")
	_gfx_check(t, "Reflections (SSR)", "ssr")
	_gfx_check(t, "Global illumination (SDFGI)", "sdfgi")
	_gfx_check(t, "Bloom / glow", "glow")
	_gfx_check(t, "Volumetric fog", "volumetric_fog")
	_gfx_check(t, "Depth of field", "depth_of_field")


func _build_display() -> void:
	var t := "Display"
	var mode_names: Array = WINDOW_MODES.keys()
	var current: int = WINDOW_MODES.values().find(SettingsManager.window_mode)
	_add_option(t, "Window mode", mode_names, current if current >= 0 else 1, func(i: int) -> void:
		SettingsManager.window_mode = WINDOW_MODES[mode_names[i]]
		_apply_display())
	var screen := DisplayServer.screen_get_size()
	var sizes: Array[Vector2i] = RESOLUTIONS.filter(func(r: Vector2i) -> bool: return r.x <= maxi(screen.x, 1280) and r.y <= maxi(screen.y, 720))
	var labels: Array[String] = []
	for r in sizes:
		labels.append("%d × %d" % [r.x, r.y])
	_add_option(t, "Window size (windowed)", labels, maxi(sizes.find(SettingsManager.window_size), 0), func(i: int) -> void:
		SettingsManager.window_size = sizes[i]
		_apply_display())
	_add_check(t, "V-Sync", SettingsManager.vsync, func(on: bool) -> void:
		SettingsManager.vsync = on
		_apply_display())
	var caps: Array[String] = []
	for c in FPS_CAPS:
		caps.append("Unlimited" if c == 0 else str(c))
	_add_option(t, "FPS limit", caps, maxi(FPS_CAPS.find(SettingsManager.max_fps), 0), func(i: int) -> void:
		SettingsManager.max_fps = FPS_CAPS[i]
		_apply_display())
	_add_slider(t, "Field of view", 70.0, 110.0, 1.0, SettingsManager.field_of_view, "%d°", 1.0, func(v: float) -> void:
		SettingsManager.field_of_view = v
		SettingsManager.save())
	_add_slider(t, "Brightness", 0.5, 1.5, 0.05, SettingsManager.brightness, "%d%%", 100.0, func(v: float) -> void:
		SettingsManager.brightness = v
		SettingsManager.graphics_changed.emit(SettingsManager.graphics) # levels re-apply their environment
		SettingsManager.save())
	_add_check(t, "Performance overlay (F3)", SettingsManager.show_perf_overlay, func(on: bool) -> void:
		SettingsManager.show_perf_overlay = on
		SettingsManager.save())


func _build_audio() -> void:
	var t := "Audio"
	var labels := { &"Master": "Master", &"Music": "Music", &"SFX": "Effects", &"Voice": "Voice chat", &"UI": "Interface" }
	for bus: StringName in SettingsManager.AUDIO_BUSES:
		_add_slider(t, "%s volume" % labels[bus], 0.0, 1.0, 0.05, SettingsManager.bus_volumes[bus], "%d%%", 100.0,
			func(v: float) -> void: SettingsManager.set_bus_volume(bus, v))
	_add_option(t, "Audio quality", ["Low (16 sounds, no reverb)", "High (40 sounds, reverb)"],
		SettingsManager.audio_quality, func(i: int) -> void:
			SettingsManager.audio_quality = i
			SettingsManager.apply_audio()
			SettingsManager.save())
	_add_check(t, "Music during matches", SettingsManager.match_music, func(on: bool) -> void:
		SettingsManager.match_music = on
		SettingsManager.apply_audio()
		SettingsManager.save())
	_add_check(t, "Hit & kill sounds", SettingsManager.hit_sounds, func(on: bool) -> void:
		SettingsManager.hit_sounds = on
		SettingsManager.save())


func _build_voice() -> void:
	var t := "Voice"
	_add_check(t, "Voice chat", SettingsManager.voice_enabled, func(on: bool) -> void:
		SettingsManager.voice_enabled = on
		_apply_voice())
	_add_option(t, "Transmit", ["Push-to-talk (V / B)", "Voice activation"], SettingsManager.voice_mode, func(i: int) -> void:
		SettingsManager.voice_mode = i as SettingsManager.VoiceMode
		_apply_voice())
	var devices: Array[String] = []
	devices.assign(AudioServer.get_input_device_list())
	_add_option(t, "Microphone", devices, maxi(devices.find(SettingsManager.voice_input_device), 0), func(i: int) -> void:
		SettingsManager.voice_input_device = devices[i]
		_apply_voice())
	_add_slider(t, "Mic volume", 0.0, 2.0, 0.05, SettingsManager.mic_volume, "%d%%", 100.0, func(v: float) -> void:
		SettingsManager.mic_volume = v
		_apply_voice())
	_add_slider(t, "Voice activation level", 0.005, 0.5, 0.005, SettingsManager.voice_activation_threshold, "%d%%", 100.0,
		func(v: float) -> void:
			SettingsManager.voice_activation_threshold = v
			_apply_voice())
	_mic_bar = ProgressBar.new()
	_mic_bar.max_value = 1.0
	_mic_bar.show_percentage = false
	_mic_bar.custom_minimum_size = Vector2(0, 12)
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_row(t, "Mic level", _mic_bar)
	_add_check(t, "Noise suppression + auto gain", SettingsManager.voice_processing, func(on: bool) -> void:
		SettingsManager.voice_processing = on
		_apply_voice())
	var opus := _add_check(t, "Opus codec (24 kbps instead of 64)" if VoiceCodec.opus_available()
			else "Opus codec (not available — using ADPCM)", SettingsManager.voice_opus, func(on: bool) -> void:
		SettingsManager.voice_opus = on
		_apply_voice())
	opus.disabled = not VoiceCodec.opus_available()
	opus.tooltip_text = "%s. Used when every player in the match has Opus; otherwise voice falls back to ADPCM." \
		% (VoiceCodec.opus_version() if VoiceCodec.opus_available() else "The Opus library isn't installed")
	_add_check(t, "Proximity chat (B)", SettingsManager.proximity_chat_enabled, func(on: bool) -> void:
		SettingsManager.proximity_chat_enabled = on
		_apply_voice())
	_add_check(t, "Hear myself (mic test)", VoiceChat.loopback, func(on: bool) -> void: VoiceChat.loopback = on)


func _build_controls() -> void:
	var t := "Controls"
	_add_slider(t, "Mouse sensitivity", 0.02, 1.0, 0.01, SettingsManager.mouse_sensitivity, "%.2f", 1.0, func(v: float) -> void:
		SettingsManager.mouse_sensitivity = v
		SettingsManager.save())
	_add_slider(t, "Aim (ADS) sensitivity", 0.25, 2.0, 0.05, SettingsManager.ads_sensitivity_scale, "%d%%", 100.0,
		func(v: float) -> void:
			SettingsManager.ads_sensitivity_scale = v
			SettingsManager.save())
	_add_check(t, "Invert mouse Y", SettingsManager.invert_y, func(on: bool) -> void:
		SettingsManager.invert_y = on
		SettingsManager.save())
	_add_option(t, "Aim down sights", ["Hold", "Toggle"], int(SettingsManager.aim_toggle), func(i: int) -> void:
		SettingsManager.aim_toggle = i == 1
		SettingsManager.save())
	_add_option(t, "Crouch", ["Hold", "Toggle"], int(SettingsManager.crouch_toggle), func(i: int) -> void:
		SettingsManager.crouch_toggle = i == 1
		SettingsManager.save())

	_add_section(t, "Controller")
	var pads := Input.get_connected_joypads().map(func(d: int) -> String: return Input.get_joy_name(d))
	var connected := Label.new()
	connected.text = ", ".join(pads) if not pads.is_empty() else "No controller connected (plug one in any time)"
	_add_row(t, "Connected", connected)
	_add_slider(t, "Look sensitivity", 60.0, 400.0, 10.0, SettingsManager.pad_sensitivity, "%d°/s", 1.0, func(v: float) -> void:
		SettingsManager.pad_sensitivity = v
		SettingsManager.save())
	_add_slider(t, "Stick deadzone", 0.05, 0.4, 0.01, SettingsManager.pad_deadzone, "%d%%", 100.0, func(v: float) -> void:
		SettingsManager.pad_deadzone = v
		SettingsManager.save())
	var curves: Array[String] = []
	curves.assign(GamepadInput.RESPONSE_NAMES)
	_add_option(t, "Response curve", curves, SettingsManager.pad_curve, func(i: int) -> void:
		SettingsManager.pad_curve = i
		SettingsManager.save())
	_add_check(t, "Invert look Y (controller)", SettingsManager.pad_invert_y, func(on: bool) -> void:
		SettingsManager.pad_invert_y = on
		SettingsManager.save())
	_add_check(t, "Aim assist (slows aim over enemies)", SettingsManager.aim_assist, func(on: bool) -> void:
		SettingsManager.aim_assist = on
		SettingsManager.save())
	_add_check(t, "Vibration", SettingsManager.vibration, func(on: bool) -> void:
		SettingsManager.vibration = on
		SettingsManager.save())

	_add_section(t, "Bindings — click, then press a key / mouse button, or a controller button")
	var header := HBoxContainer.new()
	for title in ["Keyboard / mouse", "Controller"]:
		var h := Label.new()
		h.text = title
		h.custom_minimum_size = Vector2(180, 0)
		header.add_child(h)
	_add_row(t, "", header)
	for action: StringName in SettingsManager.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = SettingsManager.binding_text(action)
		b.custom_minimum_size = Vector2(180, 0)
		b.pressed.connect(_start_capture.bind(action, false))
		_binding_buttons[action] = b
		row.add_child(b)
		var pb := Button.new()
		pb.text = SettingsManager.pad_binding_text(action)
		pb.custom_minimum_size = Vector2(180, 0)
		pb.pressed.connect(_start_capture.bind(action, true))
		_pad_buttons[action] = pb
		row.add_child(pb)
		_add_row(t, SettingsManager.REMAPPABLE_ACTIONS[action], row)
	_add_button(t, "", "Reset all bindings", func() -> void:
		SettingsManager.reset_bindings()
		_status.text = "Key bindings reset to defaults."
		_refresh_bindings())


func _build_gameplay() -> void:
	var t := "Gameplay"
	var name_edit := LineEdit.new()
	name_edit.text = SettingsManager.player_name
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(text: String) -> void:
		SettingsManager.player_name = text.strip_edges() if not text.strip_edges().is_empty() else "Player"
		NetworkManager.local_name = SettingsManager.player_name
		SettingsManager.save())
	_add_row(t, "Player name", name_edit)

	_add_section(t, "Crosshair")
	var colors: Array[String] = []
	colors.assign(SettingsManager.CROSSHAIR_COLORS.keys())
	var preview := Crosshair.new()
	_add_option(t, "Colour", colors, maxi(colors.find(SettingsManager.crosshair_color_name), 0), func(i: int) -> void:
		SettingsManager.crosshair_color_name = colors[i]
		SettingsManager.save())
	_add_slider(t, "Size", 0.5, 2.0, 0.1, SettingsManager.crosshair_size, "%d%%", 100.0, func(v: float) -> void:
		SettingsManager.crosshair_size = v
		SettingsManager.save())
	_add_check(t, "Centre dot", SettingsManager.crosshair_dot, func(on: bool) -> void:
		SettingsManager.crosshair_dot = on
		SettingsManager.save())
	_add_check(t, "Show grenade throw path", SettingsManager.grenade_arc, func(on: bool) -> void:
		SettingsManager.grenade_arc = on
		SettingsManager.save())
	var frame := ColorRect.new()
	frame.color = Color(0.25, 0.28, 0.32)
	frame.custom_minimum_size = Vector2(160, 90)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.gap = 6.0
	frame.add_child(preview)
	_add_row(t, "Preview", frame)


# -----------------------------------------------------------------------------
# Graphics helpers — editing any option switches the preset to Custom
# -----------------------------------------------------------------------------

func _gfx_option(t: String, label: String, prop: String, names: Array, values: Array, restart := false) -> void:
	var current: Variant = SettingsManager.graphics.get(prop)
	# Select the entry closest to the current value (custom values may sit between).
	var idx := 0
	var best := INF
	for i in values.size():
		var d := INF
		if values[i] is String or current is String:
			d = 0.0 if values[i] == current else INF
		else:
			d = absf(float(values[i]) - float(current))
		if d < best:
			best = d
			idx = i
	_add_option(t, label, names, idx, func(i: int) -> void:
		var before: Variant = SettingsManager.graphics.get(prop)
		SettingsManager.graphics.set(prop, values[i])
		if prop == "directional_shadow_size":
			SettingsManager.graphics.positional_shadow_atlas_size = values[i]
		_graphics_edited()
		if restart and before != values[i]:
			SettingsManager.restart_required.emit("Renderer changed."))


func _gfx_slider(t: String, label: String, prop: String, lo: float, hi: float, step: float, fmt: String, mult: float) -> void:
	_add_slider(t, label, lo, hi, step, SettingsManager.graphics.get(prop), fmt, mult, func(v: float) -> void:
		SettingsManager.graphics.set(prop, v)
		_graphics_edited())


func _gfx_check(t: String, label: String, prop: String) -> void:
	_add_check(t, label, SettingsManager.graphics.get(prop), func(on: bool) -> void:
		SettingsManager.graphics.set(prop, on)
		_graphics_edited())


func _graphics_edited() -> void:
	var was_custom := SettingsManager.graphics.quality == GraphicsPreset.Quality.CUSTOM
	SettingsManager.mark_graphics_custom()
	if not was_custom:
		# Update the preset dropdown to "Custom".
		var preset_option := _grid("Graphics").get_child(1) as OptionButton
		preset_option.select(GraphicsPreset.Quality.CUSTOM)
		_status.text = "Custom graphics settings."


# -----------------------------------------------------------------------------
# Key capture
# -----------------------------------------------------------------------------

func _start_capture(action: StringName, pad: bool = false) -> void:
	_cancel_capture()
	_capturing = action
	_capturing_pad = pad
	_capture_started_ms = Time.get_ticks_msec()
	if pad:
		(_pad_buttons[action] as Button).text = "Press a button…  (Menu / Esc = cancel)"
	else:
		(_binding_buttons[action] as Button).text = "Press a key…  (Esc = cancel)"
	_status.text = "Rebinding: %s" % SettingsManager.REMAPPABLE_ACTIONS[action]


func _cancel_capture() -> void:
	if _capturing != &"":
		_refresh_bindings()
	_capturing = &""


func _input(event: InputEvent) -> void:
	if _capturing == &"" or not is_visible_in_tree():
		return
	var is_esc: bool = event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	var is_menu: bool = event is InputEventJoypadButton and event.pressed \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	var accept: bool
	if _capturing_pad:
		accept = (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6)
	else:
		accept = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)
	if not (accept or is_esc or is_menu):
		return
	get_viewport().set_input_as_handled()
	if is_esc or is_menu:
		_cancel_capture()
		_status.text = "Cancelled."
		return
	# The controller press that opened the capture must not bind itself.
	if _capturing_pad and Time.get_ticks_msec() - _capture_started_ms < 250:
		return
	capture_event(event)


## Binds `event` to the action being captured (also used by tests).
func capture_event(event: InputEvent) -> void:
	var action := _capturing
	_capturing = &""
	var swapped := SettingsManager.rebind(action, event)
	_status.text = "%s → %s" % [SettingsManager.REMAPPABLE_ACTIONS[action],
		SettingsManager.pad_binding_text(action) if GamepadInput.is_pad_event(event) else SettingsManager.binding_text(action)]
	if swapped != &"":
		_status.text += "  (swapped with %s)" % SettingsManager.REMAPPABLE_ACTIONS[swapped]
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action: StringName in _binding_buttons:
		(_binding_buttons[action] as Button).text = SettingsManager.binding_text(action)
	for action: StringName in _pad_buttons:
		(_pad_buttons[action] as Button).text = SettingsManager.pad_binding_text(action)


# -----------------------------------------------------------------------------
# Reset
# -----------------------------------------------------------------------------

func _reset_current_tab() -> void:
	var tab := TAB_NAMES[_tabs.current_tab]
	var defaults: Node = SettingsManager.get_script().new() # fresh default values
	match tab:
		"Graphics":
			SettingsManager.set_graphics_quality(SettingsManager.detect_recommended_quality())
		"Display":
			for p in ["window_mode", "window_size", "vsync", "max_fps", "field_of_view", "brightness", "show_perf_overlay"]:
				SettingsManager.set(p, defaults.get(p))
			_apply_display()
			SettingsManager.graphics_changed.emit(SettingsManager.graphics)
		"Audio":
			for bus: StringName in SettingsManager.AUDIO_BUSES:
				SettingsManager.bus_volumes[bus] = defaults.bus_volumes[bus]
			for p in ["audio_quality", "match_music", "hit_sounds"]:
				SettingsManager.set(p, defaults.get(p))
			SettingsManager.apply_audio()
		"Voice":
			for p in ["voice_enabled", "voice_mode", "voice_activation_threshold", "voice_input_device",
					"mic_volume", "proximity_chat_enabled", "voice_processing", "voice_opus"]:
				SettingsManager.set(p, defaults.get(p))
			SettingsManager.apply_voice()
		"Controls":
			for p in ["mouse_sensitivity", "ads_sensitivity_scale", "invert_y", "aim_toggle", "crouch_toggle",
					"pad_sensitivity", "pad_invert_y", "pad_deadzone", "pad_curve", "aim_assist", "vibration"]:
				SettingsManager.set(p, defaults.get(p))
			SettingsManager.reset_bindings()
		"Gameplay":
			for p in ["crosshair_color_name", "crosshair_size", "crosshair_dot", "grenade_arc"]:
				SettingsManager.set(p, defaults.get(p))
	defaults.free()
	SettingsManager.save()
	_build_all()
	_status.text = "%s settings reset to defaults." % tab


func _apply_display() -> void:
	SettingsManager.apply_display()
	SettingsManager.save()


func _apply_voice() -> void:
	SettingsManager.apply_voice()
	SettingsManager.save()


# -----------------------------------------------------------------------------
# Row widgets
# -----------------------------------------------------------------------------

func _add_row(t: String, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(260, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid(t).add_child(l)
	_grid(t).add_child(control)


func _add_section(t: String, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_color_override(&"font_color", Color(1, 0.8, 0.4))
	_grid(t).add_child(l)
	_grid(t).add_child(Control.new())


func _add_option(t: String, label: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.select(clampi(selected, 0, maxi(items.size() - 1, 0)))
	o.item_selected.connect(on_select)
	_add_row(t, label, o)
	return o


func _add_check(t: String, label: String, value: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(on_toggle)
	_add_row(t, label, c)
	return c


func _add_slider(t: String, label: String, lo: float, hi: float, step: float, value: float,
		fmt: String, mult: float, on_change: Callable) -> HSlider:
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size = Vector2(56, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show_value := func(x: float) -> void:
		v.text = fmt % ((roundi(x * mult) as Variant) if fmt.contains("%d") else (x * mult as Variant))
	show_value.call(value)
	s.value_changed.connect(func(x: float) -> void:
		show_value.call(x)
		on_change.call(x))
	box.add_child(s)
	box.add_child(v)
	_add_row(t, label, box)
	return s


func _add_button(t: String, label: String, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	_add_row(t, label, b)
	return b
