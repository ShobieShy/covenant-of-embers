class_name LevelGate
extends Node3D
## A travel gate (step 39): F within REACH sends the player to `target` (GameFlow level id).
## Greybox: a glowing ember-coloured pillar with a label.

signal used(target: String)
signal blocked(text: String)  ## step 111: used while `requires` is unset

const REACH := 2.5

@export var target := "breach"
var uses := 0
var player: Player
var requires := ""  ## step 111: a story flag that must be set before the gate works
var locked_text := "Locked."
var flags: StoryFlags


func _init(t := "breach") -> void:
	target = t


func _ready() -> void:
	Interaction.register(self, 1.2, 0.8)
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


func interact_prompt() -> String:
	return "[F] Gate: %s" % target.capitalize()


## Looked at (t60u camera-centre cone/sphere-cast, Interaction) and within range.
func in_reach(p: Player) -> bool:
	return near(p) and Interaction.is_target(p, self)


## Plain proximity (attunement, bot walking); interaction itself goes by look (t60u).
func near(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH + 1.0


func locked() -> bool:
	return requires != "" and (flags == null or not flags.has(requires))


func use() -> bool:
	if locked():
		blocked.emit(locked_text)
		return false
	uses += 1
	used.emit(target)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if player and not player.ui_open and event.is_action_pressed(&"interact") and in_reach(player):
		use()
		get_viewport().set_input_as_handled()
