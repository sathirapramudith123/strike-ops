class_name GamepadInput
extends RefCounted
## Controller support: default layout, stick look, button names, rumble.
##
## Default layout (Xbox names — on PlayStation: A = ✕, B = ○, X = □, Y = △,
## LB/RB = L1/R1, LT/RT = L2/R2, L3/R3 = stick clicks):
##
##   Left stick  move              Right stick  look
##   RT  shoot    LT  aim          LB  interact (plant/defuse)   RB  grenade
##   A   jump     B   crouch       X   reload    Y   next weapon
##   L3  sprint   R3  slide        D-pad ←/→ primary/secondary, ↑ team voice, ↓ proximity voice
##   View/Back  scoreboard         Menu/Start  pause
##
## Every action keeps one keyboard/mouse binding and one controller binding;
## both can be remapped in Settings → Controls. Menus work with the D-pad /
## left stick, A to select and B to go back.

const LOOK_ACTIONS: Array[StringName] = [&"look_left", &"look_right", &"look_up", &"look_down"]
const RESPONSE_CURVES: Array[float] = [1.0, 2.0, 3.0] # Linear / Default / Precise
const RESPONSE_NAMES: Array[String] = ["Linear", "Default", "Precise"]
## Look speed is multiplied by this while the crosshair is on an enemy.
const AIM_ASSIST_SLOWDOWN := 0.5
const AIM_ASSIST_RANGE := 80.0

## True when the last input came from a controller (for rumble and prompts).
static var using_pad: bool = false


## The default controller event for each action (null = unbound).
static func default_bindings() -> Dictionary:
	return {
		&"move_forward": axis(JOY_AXIS_LEFT_Y, -1.0), &"move_back": axis(JOY_AXIS_LEFT_Y, 1.0),
		&"move_left": axis(JOY_AXIS_LEFT_X, -1.0), &"move_right": axis(JOY_AXIS_LEFT_X, 1.0),
		&"look_left": axis(JOY_AXIS_RIGHT_X, -1.0), &"look_right": axis(JOY_AXIS_RIGHT_X, 1.0),
		&"look_up": axis(JOY_AXIS_RIGHT_Y, -1.0), &"look_down": axis(JOY_AXIS_RIGHT_Y, 1.0),
		&"shoot": axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), &"aim": axis(JOY_AXIS_TRIGGER_LEFT, 1.0),
		&"jump": button(JOY_BUTTON_A), &"crouch": button(JOY_BUTTON_B), &"reload": button(JOY_BUTTON_X),
		&"weapon_next": button(JOY_BUTTON_Y), &"sprint": button(JOY_BUTTON_LEFT_STICK),
		&"slide": button(JOY_BUTTON_RIGHT_STICK), &"interact": button(JOY_BUTTON_LEFT_SHOULDER),
		&"throw_grenade": button(JOY_BUTTON_RIGHT_SHOULDER),
		&"weapon_1": button(JOY_BUTTON_DPAD_LEFT), &"weapon_2": button(JOY_BUTTON_DPAD_RIGHT),
		&"push_to_talk_team": button(JOY_BUTTON_DPAD_UP), &"push_to_talk_proximity": button(JOY_BUTTON_DPAD_DOWN),
		&"scoreboard": button(JOY_BUTTON_BACK), &"pause": button(JOY_BUTTON_START),
	}


## Adds the look actions and the default controller events (before the
## player's saved bindings are applied). Actions that already have a
## controller event (e.g. set in project.godot) are left alone.
static func install_defaults() -> void:
	for action in LOOK_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.0) # deadzone handled by look_vector()
	var defaults := default_bindings()
	for action: StringName in defaults:
		if not InputMap.has_action(action):
			continue
		if InputMap.action_get_events(action).any(is_pad_event):
			continue
		InputMap.action_add_event(action, defaults[action])
	# Triggers are analog: count them as pressed from 30 %.
	for action: StringName in [&"shoot", &"aim"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, 0.3)


static func button(index: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.device = -1 # any controller
	return e


static func axis(index: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = index
	e.axis_value = signf(direction)
	e.device = -1
	return e


static func is_pad_event(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


## Right-stick look with a radial deadzone and a response curve
## (small movements are finer, full tilt is full speed).
static func look_vector(deadzone: float, curve: float) -> Vector2:
	var raw := Vector2(
		Input.get_action_raw_strength(&"look_right") - Input.get_action_raw_strength(&"look_left"),
		Input.get_action_raw_strength(&"look_down") - Input.get_action_raw_strength(&"look_up"))
	return shape_stick(raw, deadzone, curve)


static func shape_stick(raw: Vector2, deadzone: float, curve: float) -> Vector2:
	var m := minf(raw.length(), 1.0)
	if m <= deadzone:
		return Vector2.ZERO
	var scaled := (m - deadzone) / maxf(1.0 - deadzone, 0.001)
	return raw.normalized() * pow(scaled, curve)


## Short controller vibration (off in Settings, or when playing with mouse).
static func rumble(weak: float, strong: float, duration: float) -> void:
	if not using_pad or not SettingsManager.vibration:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Button / stick names shown in Settings and prompts.
static func event_text(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		var names := {
			JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
			JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_GUIDE: "Guide",
			JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
			JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
			JOY_BUTTON_MISC1: "Share", JOY_BUTTON_TOUCHPAD: "Touchpad",
		}
		var b := (e as InputEventJoypadButton).button_index
		return names.get(b, "Button %d" % b)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_LEFT_X: return "Left stick ←" if m.axis_value < 0.0 else "Left stick →"
			JOY_AXIS_LEFT_Y: return "Left stick ↑" if m.axis_value < 0.0 else "Left stick ↓"
			JOY_AXIS_RIGHT_X: return "Right stick ←" if m.axis_value < 0.0 else "Right stick →"
			JOY_AXIS_RIGHT_Y: return "Right stick ↑" if m.axis_value < 0.0 else "Right stick ↓"
		return "Axis %d%s" % [m.axis, "-" if m.axis_value < 0.0 else "+"]
	return "—"


## A clean, device-independent copy of a controller event for binding
## (null if it isn't a clear press / full stick push).
static func clean(e: InputEvent) -> InputEvent:
	if e is InputEventJoypadButton:
		return button((e as InputEventJoypadButton).button_index)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		if absf(m.axis_value) < 0.6:
			return null
		return axis(m.axis, m.axis_value)
	return null


static func serialize(e: InputEvent) -> Dictionary:
	if e is InputEventJoypadButton:
		return { "type": "joy_button", "button": (e as InputEventJoypadButton).button_index }
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return { "type": "joy_axis", "axis": m.axis, "dir": signf(m.axis_value) }
	return {}


static func deserialize(data: Dictionary) -> InputEvent:
	match data.get("type", ""):
		"joy_button": return button(int(data.get("button", 0)))
		"joy_axis": return axis(int(data.get("axis", 0)), float(data.get("dir", 1.0)))
	return null
