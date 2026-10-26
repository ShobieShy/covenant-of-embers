class_name Waystone
extends Node3D
## A fast-travel waystone (BUILD_PLAN step 68): attunes when the player comes within REACH;
## Interact opens the map screen (`opened`).

signal attuned(point: String)
signal opened(point: String)

const REACH := 3.0

var point := ""
var travel: FastTravel
var player: Player


func _init(p := "", ft: FastTravel = null) -> void:
	point = p
	travel = ft


func _ready() -> void:
	Interaction.register(self, 1.0, 0.5)
	var c := CSGCylinder3D.new()
	c.radius = 0.25
	c.height = 1.6
	c.sides = 6
	c.position.y = 0.8
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.8, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.7, 1.0)
	c.material = m
	add_child(c)
	var l := Label3D.new()
	l.text = "Waystone: %s  [F]" % String(FastTravel.POINTS.get(point, {}).get("name", point))
	l.position.y = 2.0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)


func interact_prompt() -> String:
	return "[F] Waystone: %s" % String(FastTravel.POINTS.get(point, {}).get("name", point))


## Looked at (t60u camera-centre cone/sphere-cast, Interaction) and within range.
func in_reach(p: Player) -> bool:
	return Interaction.is_target(p, self)


## Plain proximity (attunement, bot walking); interaction itself goes by look (t60u).
func near(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH


## Attunes when the player is in reach; true when it newly attuned.
func check_attune() -> bool:
	if travel and near(player) and travel.attune(point):
		attuned.emit(point)
		return true
	return false


func _physics_process(_dt: float) -> void:
	check_attune()


func _unhandled_input(event: InputEvent) -> void:
	if player and not player.ui_open and event.is_action_pressed(&"interact") and in_reach(player):
		opened.emit(point)
		get_viewport().set_input_as_handled()
