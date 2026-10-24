class_name LevelGate
extends Node3D
## A travel gate (step 39): F within REACH sends the player to `target` (GameFlow level id).
## Greybox: a glowing ember-coloured pillar with a label.

signal used(target: String)

const REACH := 2.5

@export var target := "breach"
var uses := 0
var player: Player


func _init(t := "breach") -> void:
	target = t


func _ready() -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(1.0, 2.4, 0.3)
	box.position.y = 1.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.05)
	m.emission_energy_multiplier = 2.0
	box.material = m
	add_child(box)
	var l := Label3D.new()
	l.text = "Gate: %s  [F]" % target.capitalize()
	l.position.y = 2.8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)


func in_reach(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH


func use() -> void:
	uses += 1
	used.emit(target)


func _unhandled_input(event: InputEvent) -> void:
	if player and not player.ui_open and event.is_action_pressed(&"interact") and in_reach(player):
		use()
		get_viewport().set_input_as_handled()
