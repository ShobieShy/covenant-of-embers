class_name Gamepad
extends RefCounted
## Controller support (BUILD_PLAN step 77). Godot maps every pad through the SDL game
## controller database, so JoyButton/JoyAxis ids are the same on Windows (XInput) and Linux
## (evdev/SDL) - one default table serves both (step 86 checks this).
##  * install(): adds the default joypad event to every rebindable action + "menu" (keeps
##    keyboard/mouse events; idempotent). Movement = left stick, look = right stick.
##  * Settings stores pad events as {"joy": button} / {"axis": a, "dir": +-1} and a pad
##    rebind replaces only the pad events of that action (step 77 rebinding).
##  * look_vector(): right stick with a radial dead zone -> Player turns at LOOK_DEG_PER_SEC.
##  * focus_first(root): every menu grabs focus on its first enabled control when opened, so
##    ui_up/ui_down/ui_accept (Godot's default pad bindings) navigate every screen.

const DEADZONE := 0.2
const LOOK_DEG_PER_SEC := 180.0
const EXTRA_ACTIONS: Array[StringName] = [&"menu"]
const DEFAULTS := {
	&"forward": {"axis": JOY_AXIS_LEFT_Y, "dir": -1},
	&"back": {"axis": JOY_AXIS_LEFT_Y, "dir": 1},
	&"left": {"axis": JOY_AXIS_LEFT_X, "dir": -1},
	&"right": {"axis": JOY_AXIS_LEFT_X, "dir": 1},
	&"jump": {"joy": JOY_BUTTON_A},
	&"action_primary": {"axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1},
	&"action_secondary": {"axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1},
	&"sprint": {"joy": JOY_BUTTON_LEFT_STICK},
	&"dash": {"joy": JOY_BUTTON_B},
	&"crouch": {"joy": JOY_BUTTON_RIGHT_STICK},
	&"interact": {"joy": JOY_BUTTON_X},
	&"slot_1": {"joy": JOY_BUTTON_DPAD_LEFT},
	&"slot_2": {"joy": JOY_BUTTON_DPAD_RIGHT},
	&"slot_3": {"joy": JOY_BUTTON_DPAD_UP},
	&"slot_4": {"joy": JOY_BUTTON_DPAD_DOWN},
	&"quickslot_prev_wieldable": {"joy": JOY_BUTTON_LEFT_SHOULDER},
	&"quickslot_next_wieldable": {"joy": JOY_BUTTON_RIGHT_SHOULDER},
	&"use_potion": {"joy": JOY_BUTTON_MISC1},  # step 136: Y went to reload
	&"reload": {"joy": JOY_BUTTON_Y},
	&"inventory": {"joy": JOY_BUTTON_BACK},
	&"skills": {"joy": JOY_BUTTON_TOUCHPAD},
	&"menu": {"joy": JOY_BUTTON_START},
}


static func actions() -> Array[StringName]:
	var a := Settings.rebindable()
	a.append_array(EXTRA_ACTIONS)
	return a


static func is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


static func has_pad_event(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if is_pad(e):
			return true
	return false


static func install() -> void:
	for a in DEFAULTS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
		if not has_pad_event(a):
			InputMap.action_add_event(a, Settings.dict_to_event(DEFAULTS[a]))


static func look_vector(device := 0) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	return deadzone(v)


static func deadzone(v: Vector2) -> Vector2:
	var l := v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	return v / l * minf((l - DEADZONE) / (1.0 - DEADZONE), 1.0)


static func focus_first(root: Node) -> Control:
	var c := _first_focusable(root)
	if c != null and c.is_inside_tree():
		c.grab_focus()
	return c


static func _first_focusable(n: Node) -> Control:
	for ch in n.get_children():
		var c := ch as Control
		if c != null and not c.is_visible_in_tree() and c.is_inside_tree():
			continue
		if c != null and c.focus_mode != Control.FOCUS_NONE and not (c is BaseButton and (c as BaseButton).disabled):
			return c
		var deeper := _first_focusable(ch)
		if deeper != null:
			return deeper
	return null
