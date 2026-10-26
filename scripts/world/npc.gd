class_name Npc
extends Node3D
## A talkable townsperson (BUILD_PLAN step 65). Greybox capsule + name label; Interact within
## REACH emits `talked(speaker)`, which main.gd routes to the DialogueRunner (speaker = a
## data/story/dialogue.toml speaker).

signal talked(speaker: String)

const REACH := 2.5

@export var speaker := ""
var talks := 0
var player: Player


func _init(s := "") -> void:
	speaker = s


func _ready() -> void:
	Interaction.register(self, 1.2, 0.5)
	var model := CharacterModel.make_for_speaker(speaker)  # batch_02 art
	if model:
		add_child(model)
	else:
		_placeholder_body()
	var l := Label3D.new()
	l.text = "%s  [F]" % speaker
	l.position.y = 2.2
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)


func _placeholder_body() -> void:
	var body := CSGCylinder3D.new()
	body.radius = 0.35
	body.height = 1.8
	body.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.85)
	body.material = m
	add_child(body)


func interact_prompt() -> String:
	return "[F] Talk to %s" % speaker


## Looked at (t60u camera-centre cone/sphere-cast, Interaction) and within range.
func in_reach(p: Player) -> bool:
	return near(p) and Interaction.is_target(p, self)


## Plain proximity (attunement, bot walking); interaction itself goes by look (t60u).
func near(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH + 1.0


func talk() -> void:
	talks += 1
	talked.emit(speaker)


func _unhandled_input(event: InputEvent) -> void:
	if player and not player.ui_open and event.is_action_pressed(&"interact") and in_reach(player):
		talk()
		get_viewport().set_input_as_handled()
