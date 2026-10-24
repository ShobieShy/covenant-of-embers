class_name Settings
extends RefCounted
## Player settings (BUILD_PLAN step 32): key bindings over the project.godot InputMap
## (PlayerInput.ACTIONS + UI actions), look + accessibility options, in user://keybinds.cfg.
## Bindings are stored as event lists ({key: physical keycode} / {mouse: button index}); an
## action missing from the file keeps its project default. apply_input_map() rewrites the
## InputMap; apply_to(player) pushes the options into a spawned player.

const PATH := "user://keybinds.cfg"
const UI_ACTIONS: Array[StringName] = [&"inventory"]
const BOB_PRESETS: PackedFloat64Array = [0.0, 0.1, 0.7, 1.0]   ## Cogito HEADBOBBLE
const RAW_LOOK := 1.0 / 0.6784   ## Magewar-like raw look sensitivity

var bindings := {}            ## StringName -> Array[Dictionary]; only rebound actions
var invert_y := false
var hip_fov := 75.0
var focus_toggle := false
var crouch_toggle := false
var reduced_motion := false
var head_bob := 1.0
var aim_sensitivity := 1.0
var master_volume := 1.0      ## step 37 buses
var sfx_volume := 1.0
var music_volume := 1.0

static func rebindable() -> Array[StringName]:
	var a: Array[StringName] = PlayerInput.ACTIONS.duplicate()
	a.append_array(UI_ACTIONS)
	return a

static func event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"key": int(k.physical_keycode if k.physical_keycode != 0 else k.keycode)}
	if e is InputEventMouseButton:
		return {"mouse": int((e as InputEventMouseButton).button_index)}
	return {}

static func dict_to_event(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(d["key"])
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d["mouse"])
		return m
	return null

static func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	return "?"

static func action_label(a: StringName) -> String:
	var parts: PackedStringArray = []
	if InputMap.has_action(a):
		for e in InputMap.action_get_events(a):
			parts.append(event_label(e))
	return ", ".join(parts) if not parts.is_empty() else "(unbound)"

## Binds `action` to exactly `e` (key or mouse button); false for an unknown action/event.
func rebind(action: StringName, e: InputEvent) -> bool:
	var d := event_to_dict(e)
	if d.is_empty() or not rebindable().has(action):
		return false
	bindings[action] = [d]
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, dict_to_event(d))
	return true

func apply_input_map() -> void:
	for a in bindings:
		if not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		for d in bindings[a]:
			var e := dict_to_event(d)
			if e:
				InputMap.action_add_event(a, e)

func apply_to(p: Player) -> void:
	if p == null:
		return
	p.invert_y = invert_y
	p.aim_sensitivity = aim_sensitivity
	p.focus_toggle = focus_toggle
	p.crouch_toggle = crouch_toggle
	p.set_hip_fov(hip_fov)
	p.set_reduced_motion(reduced_motion)
	p.feel.set_bob_scale(head_bob)

func save(path := PATH) -> Error:
	var c := ConfigFile.new()
	for k in _options():
		c.set_value("options", k, get(k))
	for a in bindings:
		c.set_value("bindings", String(a), bindings[a])
	return c.save(path)

## Loads `path` (missing file = defaults, OK). Values out of range are clamped.
static func load_from(path := PATH) -> Settings:
	var s := Settings.new()
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return s
	for k in s._options():
		s.set(k, c.get_value("options", k, s.get(k)))
	if c.has_section("bindings"):
		for a in c.get_section_keys("bindings"):
			var v = c.get_value("bindings", a, [])
			if v is Array and rebindable().has(StringName(a)):
				s.bindings[StringName(a)] = v
	s.hip_fov = clampf(s.hip_fov, 60.0, 110.0)
	s.aim_sensitivity = clampf(s.aim_sensitivity, 0.1, 5.0)
	s.head_bob = clampf(s.head_bob, 0.0, 1.0)
	return s

func _options() -> PackedStringArray:
	return ["invert_y", "hip_fov", "focus_toggle", "crouch_toggle", "reduced_motion", "head_bob",
		"aim_sensitivity", "master_volume", "sfx_volume", "music_volume"]
