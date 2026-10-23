class_name PlayerInput
extends RefCounted
## One physics tick of player input: held actions and press edges (InputMap action names).
## Built from Input in game (from_input) or by hand in tests (hold), so the controller
## can be driven deterministically.

const ACTIONS: Array[StringName] = [
	&"forward", &"back", &"left", &"right", &"jump", &"action_primary", &"action_secondary",
	&"sprint", &"dash", &"crouch", &"interact", &"slot_1", &"slot_2", &"slot_3", &"slot_4",
	&"quickslot_prev_wieldable", &"quickslot_next_wieldable",
]

var held: Dictionary = {}      # StringName -> true
var pressed: Dictionary = {}   # StringName -> true (press edge this tick; also held)

static func hold(held_actions: Array = [], pressed_actions: Array = []) -> PlayerInput:
	var i := PlayerInput.new()
	for a in held_actions:
		i.held[StringName(a)] = true
	for a in pressed_actions:
		i.held[StringName(a)] = true
		i.pressed[StringName(a)] = true
	return i

static func from_input() -> PlayerInput:
	var i := PlayerInput.new()
	for a in ACTIONS:
		if InputMap.has_action(a):
			if Input.is_action_pressed(a):
				i.held[a] = true
			if Input.is_action_just_pressed(a):
				i.pressed[a] = true
	return i

func down(a: StringName) -> bool:
	return held.has(a)

func was_pressed(a: StringName) -> bool:
	return pressed.has(a)

func move_forward() -> float:
	return (1.0 if down(&"forward") else 0.0) - (1.0 if down(&"back") else 0.0)

func move_right() -> float:
	return (1.0 if down(&"right") else 0.0) - (1.0 if down(&"left") else 0.0)
